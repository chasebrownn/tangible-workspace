// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import "./IRevisedTNFT.sol";
import "./interfaces/IFactory.sol";
import "./interfaces/IOwnable.sol";
import "./abstract/AdminAccess.sol";

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract RevisedTangibleNFT is AdminAccess, ERC1155, IRevisedTNFT {
    using Strings for uint256;

    // ~ State Variabls ~

    address public factory;
    string public category;
    string public symbol;
    string private baseUri;
    uint256 public lastTokenId = 0;

    mapping(uint256 => bool) public override blackListedTokens;
    mapping(uint256 => string) public override fingerprintToProductId;
    mapping(uint256 => uint256) public override tokensFingerprint;
    mapping(uint256 => bool) public tnftCustody;

    uint256 constant public MAX_BALANCE = 100;


    /// @notice Initialize contract
    constructor(
        address _factory,
        string memory _category,
        string memory _symbol,
        string memory _uri
    ) ERC1155(_uri) {

        factory = _factory;
        category = _category;
        symbol = _symbol;
        baseUri = _uri;
        
    }


    // ~ Modifiers ~

    modifier onlyFactoryAdmin() {
        require(IFactory(factory).isFactoryAdmin(msg.sender), "NFA");
        _;
    }


    // ~ External Functions ~

    // TODO


    // ~ External Functions ERC1155 ~

    /// @notice Queries the approval status of an operator for a given owner.
    function isApprovedForAll(address account, address operator) public view override(ERC1155, IERC1155) returns (bool) {
        return operator == factory || ERC1155.isApprovedForAll(account, operator);
    }


    // ~ Factory Functions ~

    /// @notice mints multiple TNFTs.
    function produceMultipleTNFTtoStock( uint256 count, uint256 fingerprint, address toStock) external override onlyFactory returns (uint256[] memory) {
        require(bytes(fingerprintToProductId[fingerprint]).length > 0, "FNA");
        uint256[] memory mintedTnfts = new uint256[](count);

        for (uint256 i; i < count;) {
            mintedTnfts[i] = _produceTNFTtoStock(toStock, fingerprint);
            unchecked {
                ++i;
            }
        }

        emit ProducedTNFTs(mintedTnfts);
        return mintedTnfts;
    }


    // ~ Factory Admin Functions ~

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


    // ~ Internal Functions ~

    /// @notice Internal function which mints and produces a single TNFT.
    function _produceTNFTtoStock(address toStock, uint256 fingerprint) internal returns (uint256) {
        uint256 tokenToMint = ++lastTokenId;

        _mint(toStock, tokenToMint, MAX_BALANCE, abi.encodePacked(fingerprint));

        tokensFingerprint[tokenToMint] = fingerprint;
        return tokenToMint;
    }


    // ~ Internal Functions ERC1155 ~

    function _setURI(string memory newUri) internal virtual override(ERC1155) {
        baseUri = newUri;
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