// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

// TODO: Specify imports
import "./IRevisedTNFT.sol";
import "./interfaces/IFactory.sol";
import "./interfaces/IOwnable.sol";
import "./abstract/AdminAccess.sol";
import { IStorageManager } from "./IStorageManager.sol";

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract RevisedTangibleNFT is AdminAccess, ERC1155, IRevisedTNFT {
    using Strings for uint256;

    // ~ State Variabls ~

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

    address public storageManager;

    mapping(uint256 => address) public ownerOf; // TODO: May be useful. Come back

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
        bool _storageRequired
    ) ERC1155(_uri) {

        _grantRole(FACTORY_ROLE, _factory);

        factory = _factory;
        category = _category;
        symbol = _symbol;
        baseUri = _uri;
        storageManager = _storageManager;
        storageRequired = _storageRequired;

        // TODO: Initialize contract on RentManager, PassiveManager, and RevShareManager
    }


    // ~ Modifiers ~

    modifier onlyFactoryAdmin() {
        require(IFactory(factory).isFactoryAdmin(msg.sender), "NFA");
        _;
    }


    // ~ External Functions ~

    /// @notice Queries the approval status of an operator for a given owner.
    function isApprovedForAll(address account, address operator) public view override(ERC1155, IERC1155) returns (bool) {
        return operator == factory || ERC1155.isApprovedForAll(account, operator);
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
        //_setTNFTStatus(tokenId, false);
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

        emit ProducedTNFT(tokenToMint);
        return tokenToMint;
    }

    /// @notice Internal function for updating the baseUri global variable.
    function _setURI(string memory newUri) internal virtual override(ERC1155) {
        baseUri = newUri;
    }

    // function _isTokenMinter(address from, uint256 tokenId) internal view returns (bool) {
    //     if (_originalTokenOwners[tokenId] == from) {
    //         return true;
    //     }
    //     return false;
    // }

    /// @notice Internal fucntion to check conditions prior to initiating a transfer of token(s).
    function _beforeTokenTransfer(address operator, address from, address to, uint256[] memory ids, uint256[] memory amounts, bytes memory data) internal override(ERC1155) {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
        // Allow operations if admin, factory or 0 address
        if (
            IFactory(factory).isFactoryAdmin(from) ||
            (factory == from) ||
            from == address(0) ||
            to == address(0)
        ) {
            return;
        }

        // TODO: Rebuild section
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

        // for houses there is no storage so just allow transfer
        // if (!storageRequired) {
        //     return;
        // }
        // if (!_isStorageFeePaid(tokenId) && !_isTokenMinter(from, tokenId)) {
        //     revert("CT");
        // }
    }

    function _setCustodyStatus(uint256 tokenId, bool inOurCustody) internal {
        tnftCustody[tokenId] = inOurCustody;
        //this should execute only once
        // if (tnftToPassiveNft[tokenId] != 0 && !inOurCustody) {
        //     PassiveIncomeNFT piNft = IFactory(factory).passiveNft();
        //     IERC721(address(piNft)).safeTransferFrom(
        //         address(this),
        //         ownerOf(tokenId), //send it to the owner of TNFT
        //         tnftToPassiveNft[tokenId]
        //     );
        //     PassiveIncomeNFT.Lock memory lock = piNft.locks(
        //         tnftToPassiveNft[tokenId]
        //     );
        //     _updateRevenueShare(
        //         address(this),
        //         tokenId,
        //         -int256(lock.lockedAmount + lock.maxPayout)
        //     );
        //     _updateRevenueShare(
        //         address(piNft),
        //         tnftToPassiveNft[tokenId],
        //         int256(lock.lockedAmount + lock.maxPayout)
        //     );

        //     piNft.setGenerateRevenue(tnftToPassiveNft[tokenId], true);
        //     delete tnftToPassiveNft[tokenId];
        // }
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

}