// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import { AdminAccess } from "./abstract/AdminAccess.sol";
import { IFactory } from "./interfaces/IFactory.sol";
import { IStorageManager } from "./IStorageManager.sol";

/// @notice StorageManager is in charge of facilitating the rent / storage logic of certain TNFT assets.
contract StorageManager is AdminAccess, IStorageManager {

    // ~ State Variabls ~

    /// @notice A mapping from TNFT contract address to bool. If true, contract may reference the StorageManager.
    mapping(address => bool) public override registered;

    /// @notice A mapping from TNFT contract address to price per year for storage.
    mapping(address => uint256) public override storagePricePerYear;

    /// @notice A mapping from TNFT contract address to percentage of value price per year for storage.
    /// @dev Max percent precision is 2 decimals. 100% is 10000. 0.01% is 1.
    mapping(address => uint256) public override storagePercentagePricePerYear;

    /// @notice A mapping from TNFT contract address to tokenId to storage expiration timestamp.
    mapping(address => mapping (uint256 => uint256)) public override storageEndTime;

    /// @notice A mapping from TNFT contract address to bool. If true, storage price is a fixed price for specified contract address.
    mapping(address => bool) public override storagePriceFixed;

    /// @notice Used to store the contract address of Factory.sol.
    address public immutable factory;


    // ~ Constructor ~

    /// @notice Initialize contract.
    /// @param _factory address of Factory contract.
    constructor(
        address _factory
    ) {
        _grantRole(FACTORY_ROLE, _factory);
        factory = _factory;
    }


    // ~ Modifiers ~

    /// @notice Modifier for verifying msg.sender to be the Factory admin.
    modifier onlyFactoryAdmin() {
        require(IFactory(factory).isFactoryAdmin(msg.sender), "NFA");
        _;
    }


    // ~ External Functions ~

    /// @notice This function sets a contract to bool value in registered mapping.
    /// @dev Should be called after TNFT contract is deployed if storage is required. Callable by Factory.
    /// @param _contract TNFT contract address to register.
    /// @param _paysForStorage If yes, contract is registered with StorageManager, otherwise false.
    function registerWithStorageManager(address _contract, bool _paysForStorage) external override onlyFactory {
        registered[_contract] = _paysForStorage;
    }

    /// @notice This function is used to update the storage expiration timestamp for a token and returns an amount to pay.
    /// @param _contract TNFT contract where the token derives.
    /// @param tokenId token identifier. Token that is being stored.
    /// @param _years amuont of years the token is being stored for.
    /// @param tokenPrice value of the token. Not necessary if storage price is fixed.
    /// @return quoted amount to pay for updated storage.
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

    /// @notice This function is used to update the storage price per year.
    /// @param _contract TNFT contract address.
    /// @param _storagePricePerYear amount to pay for storage per year.
    function setStoragePricePerYear(address _contract, uint256 _storagePricePerYear) external override onlyFactoryAdmin {
        require(registered[_contract], "StorageManager.sol::setStoragePricePerYear() contract provided is not registered");
        require(_storagePricePerYear >= 1000000, "StorageManager.sol::setStoragePricePerYear() storagePricePerYear must be gt 1000000 ($1)");
        if (storagePricePerYear[_contract] != _storagePricePerYear) {
            emit StoragePricePerYearSet(storagePricePerYear[_contract], _storagePricePerYear);
            storagePricePerYear[_contract] = _storagePricePerYear;
        }
    }

    /// @notice This method is used to update the storage percentage price per year.
    /// @dev Not necessary for TNFT contracts that have a fixed storage pricing model.
    /// @param _contract TNFT contract address.
    /// @param _storagePercentagePricePerYear percentage of token value to pay per year for storage.
    function setStoragePercentPricePerYear(address _contract, uint256 _storagePercentagePricePerYear) external override onlyFactoryAdmin {
        require(registered[_contract], "StorageManager.sol::setStoragePercentPricePerYear() contract provided is not registered");
        require(_storagePercentagePricePerYear >= 50, "StorageManager.sol::setStoragePercentPricePerYear() storagePercentagePerYear must be gt 50 (0.5%)");
        if (storagePercentagePricePerYear[_contract] != _storagePercentagePricePerYear) {
            emit StoragePercentagePricePerYearSet(storagePercentagePricePerYear[_contract], _storagePercentagePricePerYear);
            storagePercentagePricePerYear[_contract] = _storagePercentagePricePerYear;
        }
    }

    /// @notice This function is used to update the storage fee for a specified fixed price TNFT contract.
    /// @param _contract TNFT contract address.
    /// @param value new storage price.
    function toggleStorageFee(address _contract, bool value) external onlyFactoryAdmin {
        require(registered[_contract], "StorageManager.sol::toggleStorageFee() contract provided is not registered");
        storagePriceFixed[_contract] = value;
    }


    // ~ Internal Functions ~

    //


    // ~ View Functions ~

    /// @notice Method used to fetch whether a tokenId storage has been paid.
    /// @param _contract TNFT contract address.
    /// @param tokenId token identifier that needs storage.
    /// @return If returns true, storage is up to date, otherwise if false storage has been expired.
    function isStorageFeePaid(address _contract, uint256 tokenId) public view returns (bool) {
        return storageEndTime[_contract][tokenId] > block.timestamp;
    }
}