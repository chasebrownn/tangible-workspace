// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

/// @title IPassiveManager
/// @notice interface defines the interface of the StorageManager
interface IPassiveManager {

    function registered(address _contract) external returns (bool);

    function tnftToPassiveNft(address _contract, uint256 tokenId) external returns (uint256 passiveTokenId);

    function movePassiveNftToOwner(uint256 tokenId, address owner) external;

    function registerWithPassiveManager(address _contract, bool eligible) external;

    function lockTNGBL(address _contract, uint256 tokenId, uint256 _years, uint256 lockedAmount, bool onlyLock) external;

    function claim(address _contract, uint256 tokenId, uint256 amount) external;
}
