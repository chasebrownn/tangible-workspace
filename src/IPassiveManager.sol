// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

/// @title IPassiveManager
/// @notice interface defines the interface of the StorageManager
interface IPassiveManager {

    function tnftToPassiveNft(address _contract, uint256 tokenId) external returns (uint256 passiveTokenId);

    function deletePassiveNft(uint256 tokenId) external;
}
