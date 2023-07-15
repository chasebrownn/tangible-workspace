// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.4;

import "../interfaces/ITangibleProfile.sol";

contract TangibleProfile is ITangibleProfile {
    mapping(address => Profile) public userProfiles;

    function update(Profile memory profile) external override {
        address owner = msg.sender;
        userProfiles[owner] = profile;
    }

    function remove() external override {
        delete userProfiles[msg.sender];
    }

    function namesOf(address[] calldata owners)
        external
        view
        override
        returns (string[] memory names)
    {
        uint256 length = owners.length;
        names = new string[](length);
        for (uint256 i = 0; i < length; i++) {
            names[i] = userProfiles[owners[i]].userName;
        }
        return names;
    }
}
