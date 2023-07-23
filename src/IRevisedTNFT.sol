// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

/// TODO: Needs major overhaul
/// @title IRevisedTNFT interface defines the interface of the TangibleNFT
interface IRevisedTNFT is IERC1155{

    event ProducedTNFT(uint256 indexed tokenId);

    function getMaxBal() external returns (uint256);

    function produceMultipleTNFTtoStock(uint256 count, uint256 fingerprint, address toStock) external returns (uint256[] memory);

    function isBlacklisted(uint256 tokenId) external view returns (bool);

    function tokensFingerprint(uint256 tokenId) external view returns (uint256);

    function fingerprintToProductId(uint256 fingerprint) external view returns (string memory);

    function tnftCustody(uint256) external returns (bool);

    function lastTokenId() external returns (uint256);

    function factory() external returns (address);

    function storageRequired() external returns (bool);

    function rentRecipient() external returns (bool);

    function category() external returns (string memory);

    function symbol() external returns (string memory);

    function setCustodyStatuses(uint256[] calldata, bool[] calldata) external;

    function setBaseUri(string memory) external;

    function setFactory(address) external;

    function addFingerprintsIds(uint256[] calldata, string[] calldata) external;

    function blacklistToken(uint256, bool) external;

    function burn(uint256) external;
}
