// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

/// @title IRentManager
/// @notice interface defines the interface of the RentManager
interface IRentManager {

    function registered(address _contract) external returns (bool);

    function rentRevenueShare(address _contract, uint256 tokenId) external returns (address revShareContract);

    function createRentRevShareToken(uint256 tokenId) external;

    function registerWithRentManager(address _contract, bool eligible) external;
}
