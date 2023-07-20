// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import { AdminAccess } from "./abstract/AdminAccess.sol";
import { IFactory } from "./interfaces/IFactory.sol";
import { IStorageManager } from "./IStorageManager.sol";

//import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

/// @notice StorageManager is in charge of facilitating the rent / storage logic of certain TNFT assets.
contract StorageManager is AdminAccess, IStorageManager {

    // ~ State Variabls ~

    mapping(address => bool) public override registered;

    mapping(address => uint256) public override storagePricePerYear;
    mapping(address => uint256) public override storagePercentagePricePerYear; //max percent precision is 2 decimals 100% is 10000 0.01% is 1

    mapping(address => mapping (uint256 => uint256)) public override storageEndTime; // contract to tokenId to endTime

    mapping(address => bool) public override storagePriceFixed;

    address public immutable factory;


    // ~ Constructor ~

    /// @notice Initialize contract
    constructor(
        address _factory
    ) {
        _grantRole(FACTORY_ROLE, _factory);

        factory = _factory;
    }


    // ~ Modifiers ~

    modifier onlyFactoryAdmin() {
        require(IFactory(factory).isFactoryAdmin(msg.sender), "NFA");
        _;
    }


    // ~ External Functions ~

    /// @notice This function sets a contract to bool value in registered mapping.
    /// @dev If true, the provided contract will be known to require a storage payment
    // TODO: Consider using this function to also set other variables like initial storage prices, fixed, etc.
    function registerWithStorageManager(address _contract, bool _paysForStorage) external override onlyFactoryAdmin {
        registered[_contract] = _paysForStorage;
    }

    function adjustStorageAndGetAmount(address _contract, uint256 tokenId, uint256 _years, uint256 tokenPrice) external override onlyFactory returns (uint256) {
        require(registered[_contract], "StorageManager.sol::adjustStorageAndGetAmount() contract provided is not registered");

        uint256 lastPaidDate = storageEndTime[_contract][tokenId];
        if (lastPaidDate == 0) {
            lastPaidDate = block.timestamp;
        }
        
        // new storage expiration date
        lastPaidDate += _years * 365 days;
        storageEndTime[_contract][tokenId] = lastPaidDate;

        // amount in usdc to pay
        uint256 amount;
        if (storagePriceFixed[_contract]) {
            amount = storagePricePerYear[_contract] * _years;
        } else {
            require(tokenPrice > 0, "StorageManager.sol::adjustStorageAndGetAmount() tokenPrice == 0");
            amount = (tokenPrice * storagePercentagePricePerYear[_contract] * _years) / 10000;
        }

        emit StorageFeeToPay(tokenId, _years, amount);

        return amount;
    }

    function setStoragePricePerYear(address _contract, uint256 _storagePricePerYear) external override onlyFactoryAdmin {
        require(registered[_contract], "StorageManager.sol::setStoragePricePerYear() contract provided is not registered");
        require(_storagePricePerYear >= 1000000, "StorageManager.sol::setStoragePricePerYear() storagePricePerYear must be gt 1000000 ($1)");
        if (storagePricePerYear[_contract] != _storagePricePerYear) {
            emit StoragePricePerYearSet(storagePricePerYear[_contract], _storagePricePerYear);
            storagePricePerYear[_contract] = _storagePricePerYear;
        }
    }

    function setStoragePercentPricePerYear(address _contract, uint256 _storagePercentagePricePerYear) external override onlyFactoryAdmin {
        require(registered[_contract], "StorageManager.sol::setStoragePercentPricePerYear() contract provided is not registered");
        require(_storagePercentagePricePerYear >= 50, "StorageManager.sol::setStoragePercentPricePerYear() storagePercentagePerYear must be gt 50 (0.5%)");
        if (storagePercentagePricePerYear[_contract] != _storagePercentagePricePerYear) {
            emit StoragePercentagePricePerYearSet(storagePercentagePricePerYear[_contract], _storagePercentagePricePerYear);
            storagePercentagePricePerYear[_contract] = _storagePercentagePricePerYear;
        }
    }

    function toggleStorageFee(address _contract, bool value) external onlyFactoryAdmin {
        require(registered[_contract], "StorageManager.sol::toggleStorageFee() contract provided is not registered");
        storagePriceFixed[_contract] = value;
    }


    // ~ Internal Functions ~

    //


    // ~ View Functions ~

    function isStorageFeePaid(address _contract, uint256 tokenId) public view returns (bool) {
        return storageEndTime[_contract][tokenId] > block.timestamp;
    }
}