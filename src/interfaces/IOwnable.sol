// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

interface IOwnable {
    event OwnershipPushed(
        address indexed previousOwner,
        address indexed newOwner
    );
    event OwnershipPulled(
        address indexed previousOwner,
        address indexed newOwner
    );

    function contractOwner() external view returns (address);

    function renounceOwnership() external;

    function pushOwnership(address newOwner_) external;

    function pullOwnership() external;
}
