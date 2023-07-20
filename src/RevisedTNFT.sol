// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import { IRevisedTNFT } from "./IRevisedTNFT.sol";
import { IFactory } from "./interfaces/IFactory.sol";
import { IOwnable } from "./interfaces/IOwnable.sol";
import { AdminAccess, AccessControl } from  "./abstract/AdminAccess.sol";
import { IStorageManager } from "./IStorageManager.sol";
import { IPassiveManager } from "./IPassiveManager.sol";

import { ERC1155 } from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import { IERC1155Receiver, IERC165 } from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

contract RevisedTangibleNFT is AdminAccess, ERC1155, IRevisedTNFT {
    using Strings for uint256;

    // ~ State Variabls ~
    // TODO: Pack

    address public factory;
    string public category;
    string public symbol;
    string private baseUri;
    uint256 public lastTokenId = 0;

    mapping(uint256 => bool) public override isBlacklisted;
    mapping(uint256 => string) public override fingerprintToProductId;
    mapping(uint256 => uint256) public override tokensFingerprint;
    mapping(uint256 => bool) public tnftCustody;
    bool public storageRequired;

    IStorageManager public storageManager;
    address public passiveManager;
    mapping(uint256 => address[]) public owners;

    string[] public productIds;
    uint256[] public fingeprintsInTnft;

    uint256 constant public MAX_BALANCE = 100;


    // ~ Constructor ~

    /// @notice Initialize contract
    constructor(
        address _factory,
        string memory _category,
        string memory _symbol,
        string memory _uri,
        address _storageManager,
        bool _storageRequired,
        address _passiveManager
    ) ERC1155(_uri) {

        _grantRole(FACTORY_ROLE, _factory);

        factory = _factory;
        category = _category;
        symbol = _symbol;
        baseUri = _uri;
        storageManager = IStorageManager(_storageManager);
        storageRequired = _storageRequired;
        passiveManager = IPassiveManager(_passiveManager);
    }


    // ~ Modifiers ~

    modifier onlyFactoryAdmin() {
        require(IFactory(factory).isFactoryAdmin(msg.sender), "NFA");
        _;
    }


    // ~ External Functions ~

    /**
     * @dev Transfers `amount` tokens of token type `id` from `from` to `to`.
     *
     * Emits a {TransferSingle} event.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - `from` must have a balance of tokens of type `id` of at least `amount`.
     * - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155Received} and return the
     * acceptance magic value.
     */
    function _safeTransferFrom(address from, address to, uint256 id, uint256 amount, bytes memory data) internal virtual override {
        if (balanceOf(to, id) == 0 && amount > 0) {
            owners[id].push(to);
        }
        super._safeTransferFrom(from, to, id, amount, data);
        if (balanceOf(from, id) == 0) {
            _removeFromOwners(id, from);
        }
    }

    /**
     * @dev xref:ROOT:erc1155.adoc#batch-operations[Batched] version of {_safeTransferFrom}.
     *
     * Emits a {TransferBatch} event.
     *
     * Requirements:
     *
     * - If `to` refers to a smart contract, it must implement {IERC1155Receiver-onERC1155BatchReceived} and return the
     * acceptance magic value.
     */
    function _safeBatchTransferFrom(address from, address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data) internal virtual override {
        for (uint256 i; i < ids.length;) {
            if (balanceOf(to, ids[i]) == 0 && amounts[i] > 0) {
                owners[ids[i]].push(to);
            }
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

    /**
        @dev Handles the receipt of a single ERC1155 token type. This function is called at the end of a `safeTransferFrom` after the balance has been updated.
        To accept the transfer, this must return `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))`
        (i.e. 0xf23a6e61, or its own function selector).
        @param operator The address which initiated the transfer (i.e. msg.sender)
        @param from The address which previously owned the token
        @param id The ID of the token being transferred
        @param value The amount of tokens being transferred
        @param data Additional data with no specified format
        @return `bytes4(keccak256("onERC1155Received(address,address,uint256,uint256,bytes)"))` if transfer is allowed
    */
    function onERC1155Received(address operator, address from, uint256 id, uint256 value, bytes calldata data) external pure returns (bytes4) {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    /**
        @dev Handles the receipt of a multiple ERC1155 token types. This function
        is called at the end of a `safeBatchTransferFrom` after the balances have
        been updated. To accept the transfer(s), this must return
        `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))`
        (i.e. 0xbc197c81, or its own function selector).
        @param operator The address which initiated the batch transfer (i.e. msg.sender)
        @param from The address which previously owned the token
        @param ids An array containing ids of each token being transferred (order and length must match values array)
        @param values An array containing amounts of each token being transferred (order and length must match ids array)
        @param data Additional data with no specified format
        @return `bytes4(keccak256("onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"))` if transfer is allowed
     */
    function onERC1155BatchReceived(address operator, address from, uint256[] calldata ids, uint256[] calldata values, bytes calldata data) external returns (bytes4) {
        return IERC1155Receiver.onERC1155Received.selector;
    }

    /// @notice External function for setting custody status of a tokenid
    function setCustodyStatuses(uint256[] calldata tokenIds, bool[] calldata inOurCustody) external onlyFactory {
        uint256 length = tokenIds.length;
        for (uint256 i; i < length;) {
            _setCustodyStatus(tokenIds[i], inOurCustody[i]);
            unchecked {
                ++i;
            }
        }
    }


    // ~ Permissioned Functions ~

    /// @notice mints multiple TNFTs.
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
    function setBaseURI(string memory _uri) external onlyFactoryAdmin {
        _setURI(_uri);
    }

    /// @notice This function is used to update the factory state variable.
    /// @dev Only callable by factory admin.
    function setFactory(address _factory) external onlyFactoryAdmin {
        factory = _factory;
    }

    /// @notice This function will push a new set of fingerprints and ids to the global productIds and fingerprints arrays.
    function addFingerprintsIds(uint256[] calldata fingerprints, string[] calldata ids) external onlyFactoryAdmin {
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
    /// @dev If value is set to true, tokenId will not be able to be transfered unless to an admin.
    function blacklistToken(uint256 tokenId, bool blacklisted) external onlyFactoryAdmin {
        isBlacklisted[tokenId] = blacklisted;
    }

    /// @notice Allows the factory admin to burn 1 or more tokens
    /// @dev msg.sender must be factory admin AND holding entire ownership balance
    function burn(uint256 tokenId) external onlyFactoryAdmin {
        address msgSender = msg.sender;
        require(balanceOf(msgSender, tokenId) == MAX_BALANCE);
        _removeFromOwners(tokenId, msgSender);
        _setCustodyStatus(tokenId, false);
        _burn(msgSender, tokenId, MAX_BALANCE);
    }


    // ~ Internal Functions ~

    /// @notice Internal function which mints and produces a single TNFT.
    function _produceTNFTtoStock(address toStock, uint256 fingerprint) internal returns (uint256) {
        uint256 tokenToMint = ++lastTokenId;

        _mint(toStock, tokenToMint, MAX_BALANCE, abi.encodePacked(fingerprint));
        // if (paysRent) {
        //     RevenueShare rentRevenueShare_ = IFactory(factory)
        //         .rentShare()
        //         .forToken(address(this), tokenToMint);
        //     rentRevenueShare[tokenToMint] = address(rentRevenueShare_);

        //     _roleGranter(
        //         address(rentRevenueShare_),
        //         address(this),
        //         SHARE_MANAGER_ROLE
        //     );

        //     _roleGranter(
        //         address(rentRevenueShare_),
        //         address(this),
        //         CLAIMER_ROLE
        //     );

        //     rentRevenueShare_.updateShare(address(this), tokenToMint, 1e18);
        // }

        tokensFingerprint[tokenToMint] = fingerprint;
        tnftCustody[tokenToMint] = true;
        owners[tokenToMint].push(toStock);

        emit ProducedTNFT(tokenToMint);
        return tokenToMint;
    }

    /// @notice Internal function for updating the baseUri global variable.
    function _setURI(string memory newUri) internal virtual override(ERC1155) {
        baseUri = newUri;
    }

    /// @notice Internal fucntion to check conditions prior to initiating a transfer of token(s).
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

    function _setCustodyStatus(uint256 tokenId, bool inOurCustody) internal {
        tnftCustody[tokenId] = inOurCustody;

        //this should execute only once
        if (passiveManager.tnftToPassiveNft(tokenId) != 0 && !inOurCustody) {
           passiveManager.deletePassiveNft(tokenId, owners[tokenId][0]);
        }
    }

    function _removeFromOwners(uint256 tokenId, address owner) internal {
        (uint256 i, bool exists) = _findOwner(tokenId, owner);
        if (exists) {
            owners[tokenId][i] = owners[tokenId][owners[tokenId].length-1];
            owners[tokenId].pop();
        }
    }

    function _findOwner(uint256 tokenId, address owner) internal returns (uint256, bool) {
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

    /// @notice This function is used to return the baseUri string.
    function baseURI() external view returns (string memory) {
        return baseUri;
    }

    /// @notice This function is used to return the baseUri string with appended tokenId.
    function uri(uint256 tokenId) public view override returns (string memory) {
        return string(abi.encodePacked(baseUri, "/", tokenId.toString(), ".json"));
    }

    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControl, ERC1155, IERC165) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function getOwners(uint256 tokenId) external view returns (address[] memory) {
        return owners[tokenId];
    }

}