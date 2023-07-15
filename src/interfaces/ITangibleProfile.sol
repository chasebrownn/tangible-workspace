// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.4;

interface ITangibleProfile {
    struct Profile {
        string userName;
        string imageURL;
    }

    event ProfileUpdated(Profile oldProfile, Profile newProfile);

    /// @dev The function updates the user profile.
    function update(Profile memory profile) external;

    /// @dev The function removes the user profile.
    function remove() external;

    /// @dev The function returns name(s) of user(s).
    function namesOf(address[] calldata owners)
        external
        view
        returns (string[] memory);
}
