// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import { AdminAccess } from "./abstract/AdminAccess.sol";
import { IFactory } from "./interfaces/IFactory.sol";

//import { IERC1155 } from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

/// @notice RevShareManager is in charge of facilitating the revenue share allocation to Real Estate TNFT holders.
contract RentManager is AdminAccess {

    // ~ State Variabls ~

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

    //


    // ~ Internal Functions ~

    //


    // ~ View Functions ~

    //
}