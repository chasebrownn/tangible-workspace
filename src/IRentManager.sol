// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

/// @title IRentManager
/// @notice interface defines the interface of the RentManager
interface IRentManager {

    event StoragePricePerYearSet(uint256 oldPrice, uint256 newPrice);
    event StoragePercentagePricePerYearSet(uint256 oldPercentage, uint256 newPercentage);
    event StorageFeeToPay(uint256 indexed tokenId, uint256 _years, uint256 amount);

    function registerWithRentManager(address _contract, bool _paysForStorage) external;

    function registered(address _contract) external view returns (bool);

    function isStorageFeePaid(address _contract, uint256 tokenId) external view returns (bool);

    function paysRent(address _contract) external view returns (bool);

    function storageEndTime(address _contract, uint256 tokenId) external view returns (uint256 storageEnd);

    function setStoragePricePerYear(address _contract, uint256 _setStoragePricePerYear) external;

    function storagePricePerYear(address _contract) external view returns (uint256);

    function setStoragePercentPricePerYear(address _contract, uint256 _setStoragePercentagePricePerYear) external;

    function storagePercentagePricePerYear(address _contract) external view returns (uint256);

    function storagePriceFixed(address _contract) external view returns (bool);

    function adjustStorageAndGetAmount(address _contract, uint256 tokenId, uint256 _years, uint256 tokenPrice) external returns (uint256);
}
