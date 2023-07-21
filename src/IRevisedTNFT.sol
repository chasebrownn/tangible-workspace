// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

/// TODO: Needs major overhaul
/// @title IRevisedTNFT interface defines the interface of the TangibleNFT
interface IRevisedTNFT is IERC1155{
    // event StoragePricePerYearSet(uint256 oldPrice, uint256 newPrice);
    // event StoragePercentagePricePerYearSet(uint256 oldPercentage, uint256 newPercentage);
    // event StorageFeeToPay(uint256 indexed tokenId, uint256 _years, uint256 amount);
    event ProducedTNFT(uint256 indexed tokenId);

    // function baseURI() external view returns (string memory);

    // /// @dev Function allows a Factory to mint multiple tokenIds for provided vendorId to the given address(stock storage, usualy marketplace)
    // /// with provided count.
    function produceMultipleTNFTtoStock(uint256 count, uint256 fingerprint, address toStock) external returns (uint256[] memory);

    // /// @dev Function that allows the Factory change redeem/statuses.
    // function setTNFTStatuses(uint256[] calldata tokenIds, bool[] calldata inOurCustody) external;

    // /// @dev The function returns whether storage fee is paid for the current time.
    // function isStorageFeePaid(uint256 tokenId) external view returns (bool);

    // /// @dev The function returns whether tnft is eligible for rent.
    // function paysRent() external view returns (bool);

    // function storageEndTime(uint256 tokenId) external view returns (uint256 storageEnd);

    function isBlacklisted(uint256 tokenId) external view returns (bool);

    // /// @dev The function returns the price per year for storage.
    // function storagePricePerYear() external view returns (uint256);

    // /// @dev The function returns the percentage of item price that is used for calculating storage.
    // function storagePercentagePricePerYear() external view returns (uint256);

    // /// @dev The function returns whether storage for the TNFT is paid in fixed amount or in percentage from price
    // function storagePriceFixed() external view returns (bool);

    // /// @dev The function returns whether storage for the TNFT is required. For example houses don't have storage
    // function storageRequired() external view returns (bool);

    // function setRolesForFraction(address ftnft, uint256 tnftTokenId) external;

    // /// @dev The function returns the token fingerprint - used in oracle
    function tokensFingerprint(uint256 tokenId) external view returns (uint256);

    // function tnftToPassiveNft(uint256 tokenId) external view returns (uint256);

    // function claim(uint256 tokenId, uint256 amount) external;

    // /// @dev The function returns the token string id which is tied to fingerprint
    function fingerprintToProductId(uint256 fingerprint) external view returns (string memory);

    // /// @dev The function returns lockable percentage of tngbl token e.g. 5000 - 5% 500 - 0.5% 50 - 0.05%.
    // function lockPercent() external view returns (uint256);

    // function lockTNGBL(uint256 tokenId, uint256 _years, uint256 lockedAmount, bool onlyLock) external;

    // /// @dev The function accepts takes tokenId, its price and years sets storage and returns amount to pay for.
    // function adjustStorageAndGetAmount(uint256 tokenId, uint256 _years, uint256 tokenPrice) external returns (uint256);
}
