// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import { IRevisedTNFT } from "./IRevisedTNFT.sol";
import { IFactory } from "./interfaces/IFactory.sol";
import { IOwnable } from "./interfaces/IOwnable.sol";
import { AdminAccess, AccessControl } from  "./abstract/AdminAccess.sol";
import { IStorageManager } from "./IStorageManager.sol";
import { IPassiveManager } from "./IPassiveManager.sol";
import { IRentManager } from "./IRentManager.sol";

import { ERC1155 } from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import { IERC1155Receiver, IERC165 } from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

/// @notice RevisedTangibleNFT is a revamped version of TangibleNFT.sol. It also contains the fraction
///         fucntionality of TangibleFractionsNFT.sol, but without an extra file.
contract RevisedTangibleNFT is AdminAccess, ERC1155, IRevisedTNFT {
    using Strings for uint256;

    // ~ State Variabls ~

    // 434 bytes -> 16 slots

    /// @notice A mapping from tokenId to bool. If a tokenId is set to true.
    ///         It can no longer be transferred unless to/from an admin.
    mapping(uint256 => bool) public override isBlacklisted;

    /// @notice A mapping from fingerprint identifier to productId identifier.
    mapping(uint256 => string) public override fingerprintToProductId;

    /// @notice A mapping from tokenId to fingerprint identifier.
    mapping(uint256 => uint256) public override tokensFingerprint;

    /// @notice A mapping from tokenId to bool. If tokenId is set to true, it is in the custody of Tangible.
    mapping(uint256 => bool) public override tnftCustody;

    /// @notice A mapping of tokenId to array of owners. In the event a
    ///         tokenId has more than one owner, this will be useful.
    mapping(uint256 => address[]) public owners;

    /// @notice Used to assign a unique tokenId identifier to each token minted.
    uint256 public override lastTokenId = 0;

    /// @notice The max balance of each tokenId.
    uint256 constant public MAX_BALANCE = 100;

    /// @notice Used to store the contract address of Factory.sol.
    address public override factory;
    
    /// @notice Used to assign whether or not this contract's tokens require storage.
    ///         If true, will need to be registered with the storageManager contract.
    bool public override storageRequired;

    /// @notice Used to assign whether or not this contract's tokens receive rent income.
    ///         If true, will need to be registered with the rentManager contract.
    bool public override rentRecipient;

    /// @notice Used to store the address and IStorageManager instance of the designated storageManager.
    IStorageManager public storageManager;

    /// @notice Used to store the address and IPassiveManager instance of the designated IPassiveManager.
    IPassiveManager public passiveManager;

    /// @notice Used to store the address of the RentManager contract.
    IRentManager public rentManager;

    /// @notice Array for storing fingerprint identifiers.
    uint256[] public fingeprintsInTnft;
    
    /// @notice Array for storing productIds identifiers.
    string[] public productIds;

    /// @notice Used to assign this contract with a custom category of products this
    ///         contract will be in charge of minting/stocking.
    string public override category;

    /// @notice Used to assign this contract with a custom symbol identifier.
    string public override symbol;

    /// @notice Used to assign a base metadata HTTP URI for appending/fetching token metadata.
    string private baseUri;


    // ~ Constructor ~

    /// @notice Initialize contract.
    /// @param _factory address of Factory contract.
    /// @param _category custom category name.
    /// @param _symbol custom unique symbol identifier for the contract.
    /// @param _uri base HTTP URI for fetching metadata. "/<tokenId>.json" will be
    ///             appended to this when fecthing unique token metadata.
    /// @param _storageManager address of StorageManager contract.
    /// @param _storageRequired boolean of whether a storage manager is required for this contract.
    /// @param _passiveManager address of PassiveManager contract.
    /// @param _rentRecipient If true, this contract needs to register with a RentManager.
    /// @param _rentManager address of RentManager contract. Not needed if _rentRecipient is false.
    constructor(
        address _factory,
        string memory _category,
        string memory _symbol,
        string memory _uri,
        address _storageManager,
        bool _storageRequired,
        address _passiveManager,
        bool _rentRecipient,
        address _rentManager
    ) ERC1155(_uri) {

        _grantRole(FACTORY_ROLE, _factory);

        factory = _factory;
        category = _category;
        symbol = _symbol;
        baseUri = _uri;
        storageManager = IStorageManager(_storageManager);
        storageRequired = _storageRequired;
        passiveManager = IPassiveManager(_passiveManager);
        rentRecipient = _rentRecipient;
        rentManager = IRentManager(_rentManager);
    }


    // ~ Modifiers ~

    /// @notice Modifier for verifying msg.sender to be the Factory admin.
    modifier onlyFactoryAdmin() {
        require(IFactory(factory).isFactoryAdmin(msg.sender), "NFA");
        _;
    }

    struct HelperStruct {
        uint256 totalShareSum;
        uint256 totalClaimedSum;
        uint256 revenueShare_;
        uint256 rentShare_;
    }


    // ~ External Functions ~

    /// @dev Transfers `amount` tokens of token type `id` from `from` to `to`.
    ///
    /// Emits a {TransferSingle} event.
    ///
    /// Requirements:
    ///
    /// - `to` cannot be the zero address.
    /// - `from` must have a balance of tokens of type `id` of at least `amount`.
    /// - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155Received} and return the
    /// acceptance magic value.
    function _safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes memory data) internal virtual override {
        if (balanceOf(to, id) == 0 && amount > 0) {
            owners[id].push(to);
        }
        _autoClaim(id);

        super._safeTransferFrom(from, to, id, amount, data);
        if (balanceOf(from, id) == 0) {
            _removeFromOwners(id, from);
        }
    }

    /// @dev xref:ROOT:erc1155.adoc#batch-operations[Batched] version of {_safeTransferFrom}.
    ///
    /// Emits a {TransferBatch} event.
    ///
    /// Requirements:
    ///
    /// - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155BatchReceived} and return the
    /// acceptance magic value.
    function _safeBatchTransferFrom(address from, address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data) internal virtual override {
        for (uint256 i; i < ids.length;) {
            if (balanceOf(to, ids[i]) == 0 && amounts[i] > 0) {
                owners[ids[i]].push(to);
            }
            _autoClaim(ids[i]);
            unchecked {
                ++i;
            }
        }
        super._safeBatchTransferFrom(from, to, ids, amounts, data);
        for (uint256 i; i < ids.length;) {
            if (balanceOf(from, ids[i]) == 0) {
                _removeFromOwners(ids[i], from);
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @dev Handles the receipt of a single ERC1155 token type. This function is called at the end of a `safeTransferFrom` after the balance has been updated.
    /// To accept the transfer, this must return `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))`
    /// (i.e. 0xf23a6e61, or its own function selector).
    /// @param operator The address which initiated the transfer (i.e. msg.sender)
    /// @param from The address which previously owned the token
    /// @param id The ID of the token being transferred
    /// @param value The amount of tokens being transferred
    /// @param data Additional data with no specified format
    /// @return `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))` if transfer is allowed
    function onERC1155Received(address operator, address from, uint256 id, uint256 value, bytes calldata data) external pure returns (bytes4) {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    /// @dev Handles the receipt of a multiple ERC1155 token types. This function
    /// is called at the end of a `safeBatchTransferFrom` after the balances have
    /// been updated. To accept the transfer(s), this must return
    /// `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))`
    /// (i.e. 0xbc197c81, or its own function selector).
    /// @param operator The address which initiated the batch transfer (i.e. msg.sender)
    /// @param from The address which previously owned the token
    /// @param ids An array containing ids of each token being transferred (order and length must match values array)
    /// @param values An array containing amounts of each token being transferred (order and length must match ids array)
    /// @param data Additional data with no specified format
    /// @return `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))` if transfer is allowed
    function onERC1155BatchReceived(address operator, address from, uint256[] calldata ids, uint256[] calldata values, bytes calldata data) external returns (bytes4) {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    /// @notice External function for setting custody status of a tokenId.
    /// @param tokenIds array of tokenIds to change status.
    /// @param inOurCustody array of corresponding status of each tokenId.
    function setCustodyStatuses(uint256[] calldata tokenIds, bool[] calldata inOurCustody) external override onlyFactory {
        uint256 length = tokenIds.length;
        for (uint256 i; i < length;) {
            _setCustodyStatus(tokenIds[i], inOurCustody[i]);
            unchecked {
                ++i;
            }
        }
    }


    // ~ Permissioned Functions ~

    /// @notice mints multiple TNFTs to stock.
    /// @dev only callable by Factory.
    /// @param count amount of TNFTs to mint.
    /// @param fingerprint product identifier to mint.
    /// @param toStock destination of where to mint the new tokens to.
    /// @return array of tokenIds minted.
    function produceMultipleTNFTtoStock(uint256 count, uint256 fingerprint, address toStock) external override onlyFactory returns (uint256[] memory) {
        require(bytes(fingerprintToProductId[fingerprint]).length > 0, "FNA");
        uint256[] memory mintedTnfts = new uint256[](count);

        for (uint256 i; i < count;) {
            mintedTnfts[i] = _produceTNFTtoStock(toStock, fingerprint);
            unchecked {
                ++i;
            }
        }

        return mintedTnfts;
    }

    /// @notice This function is used to update the baseUri state variable.
    /// @dev Only callable by factory admin.
    /// @param _uri New base URI.
    function setBaseUri(string memory _uri) external override onlyFactoryAdmin {
        _setURI(_uri);
    }

    /// @notice This function is used to update the factory state variable.
    /// @dev Only callable by Factory admin.
    /// @param _factory New address of factory.
    function setFactory(address _factory) external override onlyFactoryAdmin {
        factory = _factory;
    }

    /// @notice This function will push a new set of fingerprints and ids to the global productIds and fingerprints arrays.
    /// @dev Only callable by Factory admin.
    /// @param fingerprints array of fingerprints to add.
    /// @param ids array of new productIds to add.
    function addFingerprintsIds(uint256[] calldata fingerprints, string[] calldata ids) external override onlyFactoryAdmin {
        uint256 lengthArray = fingerprints.length;

        require(lengthArray == ids.length, "no match");
        require(lengthArray > 0, "arr cannot be empty");

        for (uint i; i < lengthArray;) {
            require(bytes(fingerprintToProductId[fingerprints[i]]).length == 0, "FAA");
            fingerprintToProductId[fingerprints[i]] = ids[i];

            productIds.push(ids[i]);
            fingeprintsInTnft.push(fingerprints[i]);

            unchecked {
                ++i;
            }
        }
    }

    /// @notice This function sets a tokenId to bool value in isBlacklisted mapping.
    /// @dev If value is set to true, tokenId will not be able to be transfered unless to/from an admin.
    ///      Function only callable by Factory admin.
    /// @param tokenId to be blacklisted.
    /// @param blacklisted if true, tokenId will be blacklisted.
    function blacklistToken(uint256 tokenId, bool blacklisted) external override onlyFactoryAdmin {
        isBlacklisted[tokenId] = blacklisted;
    }

    /// @notice Allows the factory admin to burn 1 or more tokens
    /// @dev msg.sender must be factory admin AND holding entire ownership balance
    /// @param tokenId tokenId to burn.
    function burn(uint256 tokenId) external override onlyFactoryAdmin {
        address msgSender = msg.sender;
        require(balanceOf(msgSender, tokenId) == MAX_BALANCE);
        _removeFromOwners(tokenId, msgSender);
        _setCustodyStatus(tokenId, false);
        _burn(msgSender, tokenId, MAX_BALANCE);
    }


    // ~ Internal Functions ~

    /// @notice Internal function which mints and produces a single TNFT.
    /// @param toStock address location of token.
    /// @param fingerprint identifier of product to mint a token for.
    /// @return tokenId that is minted
    function _produceTNFTtoStock(address toStock, uint256 fingerprint) internal returns (uint256) {
        uint256 tokenToMint = ++lastTokenId;

        _mint(toStock, tokenToMint, MAX_BALANCE, abi.encodePacked(fingerprint));

        if (rentRecipient) {
            // TODO: Uncomment during integration testing
            /// @dev Will result in revert due to incomplete independancy implementation with rentRevShare contracts.
            ///      -> https://polygonscan.com/address/0x527a819db1eb0e34426297b03bae11f2f8b3a19e#code
            // rentManager.createRentRevShareToken(tokenToMint);
        }

        tokensFingerprint[tokenToMint] = fingerprint;
        tnftCustody[tokenToMint] = true;
        owners[tokenToMint].push(toStock);

        emit ProducedTNFT(tokenToMint);
        return tokenToMint;
    }

    /// @notice This internal function claims rewards for rent recipients or passive income recipients.
    /// @dev Is mainly called during a transfer of tokens or shares from one owner to another.
    /// @param tokenId token identifier.
    function _autoClaim(uint256 tokenId) internal {
        if (passiveManager.tnftToPassiveNft(address(this), tokenId) > 0) {
            passiveManager.claimForTokenExternal(address(this), tokenId);
        }
        if (rentRecipient) {
            // TODO: Uncomment during integration
            /// @dev Will result in revert -> rentManager calls rentShare contract which currently doesnt exist.
            //rentManager.claimForTokenExternal(address(this), tokenId);
        }
    }

    /// @notice Internal function for updating the baseUri global variable.
    /// @param newUri new base Uri.
    function _setURI(string memory newUri) internal virtual override(ERC1155) {
        baseUri = newUri;
    }

    /// @notice Internal fucntion to check conditions prior to initiating a transfer of token(s).
    /// @param operator transaction initiator.
    /// @param from the current holder of the token. Token will be leaving the balance of this address.
    /// @param to the destination of the token.
    /// @param ids tokenId(s) to transfer.
    /// @param amounts balance of each tokenId to transfer. Cannot exceed balanceOf(id, from).
    /// @param data salt for event filtering.
    function _beforeTokenTransfer(address operator, address from, address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data) internal override(ERC1155) {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
        // Allow operations if admin, factory or 0 address
        if (
            IFactory(factory).isFactoryAdmin(from) ||
            IFactory(factory).isFactoryAdmin(to) ||
            (factory == from) ||
            from == address(0) ||
            to == address(0)
        ) {
            return;
        }

        // TODO: If there is a transfer of any amount LESS than 100, execute an auto claim and storage check -> handle batch here

        for (uint256 i; i < ids.length;) {
            require(!isBlacklisted[ids[i]] && !tnftCustody[ids[i]], "RevisedTNFT.sol::_beforeTokenTransfer() token is in contract custody or blacklisted");
            if (storageRequired) {
                require(IStorageManager(storageManager).isStorageFeePaid(address(this), ids[i]), "RevisedTNFT.sol::_beforeTokenTransfer() storage fee has not been paid for this token");
            }
            unchecked {
                ++i;
            }
        }
    }

    /// @notice Internal function for updating status of token custody.
    /// @param tokenId token to update custody of.
    /// @param inOurCustody if true, in Tangible custody, otherwise false.
    function _setCustodyStatus(uint256 tokenId, bool inOurCustody) internal {
        tnftCustody[tokenId] = inOurCustody;

        //this should execute only once
        // TODO: Test during integration
        if (passiveManager.tnftToPassiveNft(address(this), tokenId) != 0 && !inOurCustody) {
           passiveManager.movePassiveNftToOwner(tokenId, owners[tokenId][0]);
        }
    }

    /// @notice Internal function for removing an owner from the owners array for a specified tokenId.
    /// @param tokenId token identifier we want to update owners for.
    /// @param owner address of owner we are removing from the tokenId's owners mapped array.
    function _removeFromOwners(uint256 tokenId, address owner) internal {
        (uint256 i, bool exists) = _findOwner(tokenId, owner);
        if (exists) {
            owners[tokenId][i] = owners[tokenId][owners[tokenId].length-1];
            owners[tokenId].pop();
        }
    }

    /// @notice Internal function for locating a specified owner's address in a specified tokenId's mapped owners array.
    /// @param tokenId token identifier we are querying.
    /// @param owner address of owner we want to query if owns tokenId.
    /// @return index in owners[tokenId] array where owner resides.
    /// @return if true, owner exists, otherwise false.
    function _findOwner(uint256 tokenId, address owner) internal view returns (uint256, bool) {
        for (uint256 i; i < owners[tokenId].length;) {
            if (owners[tokenId][i] == owner) {
                return (i, true);
            }
            unchecked {
                ++i;
            }
        }
        return (0, false);
    }


    // ~ View Functions ~

    /// @notice This view function is used to return the baseUri string.
    /// @return baseUri as a string.
    function baseURI() external view returns (string memory) {
        return baseUri;
    }

    /// @notice This view function is used to return the baseUri string with appended tokenId.
    /// @param tokenId unique token identifier for which metadata we want to fetch.
    /// @return token metadata uri.
    function uri(uint256 tokenId) public view override returns (string memory) {
        return string(abi.encodePacked(baseUri, "/", tokenId.toString(), ".json"));
    }

    /// @notice View function for querying whether a specified interface is supported.
    /// @param interfaceId specified interface.
    /// @return If true, interface is supported, otherwise false.
    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControl, ERC1155, IERC165) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /// @notice View function for fetching the owners of a specified tokenId.
    /// @param tokenId token identifier we want owners of.
    /// @return An array of owner addresses for specified tokenId.
    function getOwners(uint256 tokenId) external view returns (address[] memory) {
        return owners[tokenId];
    }

    /// @notice View function for fetching the MAX_BALANCE var.
    /// @dev Usually you'd just include this public var in the interface, but constants cannot be declared in an interface.
    ///      So, we create a view function which CAN be declared on the interface
    /// @return The MAX_BALANCE constant returned as uint256.
    function getMaxBal() external view override returns (uint256) {
        return MAX_BALANCE;
    }

}