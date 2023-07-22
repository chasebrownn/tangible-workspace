// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

/// TODO: Needs major overhaul
/// @title IRevisedTNFT interface defines the interface of the TangibleNFT
interface IRevisedTNFT is IERC1155{

    event ProducedTNFT(uint256 indexed tokenId);

    // function baseURI() external view returns (string memory);

    // /// @dev Function allows a Factory to mint multiple tokenIds for provided vendorId to the given address(stock storage, usualy marketplace)
    // /// with provided count.
    function produceMultipleTNFTtoStock(uint256 count, uint256 fingerprint, address toStock) external returns (uint256[] memory);

    // /// @dev Function that allows the Factory change redeem/statuses.
    // function setTNFTStatuses(uint256[] calldata tokenIds, bool[] calldata inOurCustody) external;

    // /// @dev The function returns whether tnft is eligible for rent.
    // function paysRent() external view returns (bool);

    function isBlacklisted(uint256 tokenId) external view returns (bool);

    /// @dev The function returns the token fingerprint - used in oracle
    function tokensFingerprint(uint256 tokenId) external view returns (uint256);

    /// @dev The function returns the token string id which is tied to fingerprint
    function fingerprintToProductId(uint256 fingerprint) external view returns (string memory);
}
