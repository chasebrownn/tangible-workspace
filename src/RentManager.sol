// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import { AdminAccess } from "./abstract/AdminAccess.sol";
import { IFactory, RevenueShare, RentShare } from "./interfaces/IFactory.sol";
import { AccessControl } from  "./abstract/AdminAccess.sol";
import { IRentManager } from "./IRentManager.sol";

/// @notice RevShareManager is in charge of facilitating the revenue share allocation to Real Estate TNFT holders.
contract RentManager is IRentManager, AdminAccess {

    // ~ State Variabls ~

    /// @notice Bytes hash for the Share Manager role.
    bytes32 public constant SHARE_MANAGER_ROLE = keccak256("SHARE_MANAGER");

    /// @notice Bytes hash for the Claimer role.
    bytes32 public constant CLAIMER_ROLE = keccak256("CLAIMER");

    /// @notice A mapping from TNFT contract address to bool. If true, contract may reference the RentManager.
    mapping(address => bool) public override registered;

    /// @notice A mapping from TNFT contract to tokenId to contract address of the RevShare contract.
    mapping(address => mapping(uint256 => address)) public override rentRevenueShare;

    /// @notice Used to store the contract address of Factory.sol.
    address public immutable factory;

    /// @notice Used to store the address of rentShareContract.
    RevenueShare public immutable rentShareContract;


    // ~ Constructor ~

    /// @notice Initialize contract
    /// @param _factory address of Factory contract.
    constructor(
        address _factory,
        address _rentShare
    ) {
        _grantRole(FACTORY_ROLE, _factory);
        factory = _factory;

        rentShareContract = RevenueShare(_rentShare);
    }


    // ~ Modifiers ~

    /// @notice Modifier for verifying msg.sender to be the Factory admin.
    modifier onlyFactoryAdmin() {
        require(IFactory(factory).isFactoryAdmin(msg.sender), "NFA");
        _;
    }


    // ~ External Functions ~

    /// @notice This function sets a contract to bool value in registered mapping.
    /// @dev Should be called after TNFT contract is deployed if rent income is required. Callable by Factory.
    /// @param _contract TNFT contract address that should be registered.
    /// @param _eligible If true, needs to be registered and eligible for rent rev share.
    function registerWithRentManager(address _contract, bool _eligible) external override onlyFactory {
        registered[_contract] = _eligible;
    }

    /// @notice This function is called when a new TNFT rent rev share receiver is created.
    /// @param tokenId token identifier.
    function createRentRevShareToken(uint256 tokenId) override external {
        require(registered[msg.sender], "RentManager.sol::something() contract provided is not registered");

        // Fetch RevShare instance for this contract.
        RevenueShare rentRevenueShare_ = IFactory(factory).rentShare().forToken(msg.sender, tokenId);

        // Assign the RevShare contract address to rentRevenueShare mapping.
        rentRevenueShare[msg.sender][tokenId] = address(rentRevenueShare_);

        // NOTE: It may not be necessary to grant these roles EVERY time a new token is minted.
        //       The role can probably be granted when the contract is registered with the rentManager.

        // Grant the SHARE_MANAGER_ROLE to msg.sender. Granted by RevShare contract.
        _roleGranter(address(rentRevenueShare_), msg.sender, SHARE_MANAGER_ROLE);

        // Grant the CLAIMER_ROLE to msg.sender. Granted by RevShare contract.
        _roleGranter(address(rentRevenueShare_), msg.sender, CLAIMER_ROLE);

        // Update share state on RevShare contract.
        rentRevenueShare_.updateShare(address(this), tokenId, 1e18);
    }

    /// @notice This function is called to claim rent rewards.
    /// @param _contract TNFT contract address.
    /// @param tokenId token identifier.
    function claimForTokenExternal(address _contract, uint256 tokenId) external {
        require(registered[_contract], "RentManager.sol::claimForTokenExternal() contract provided is not registered");
        rentShareContract.claimForToken(_contract, tokenId);
    }


    // ~ Internal Functions ~

    /// @notice Is used to grant special roles via the AccessControl contract.
    /// @param granter contract that is granting this role.
    /// @param to recipient of the role.
    /// @param roleToGrant bytes hash of new role being assigned.
    function _roleGranter(address granter, address to, bytes32 roleToGrant) internal {
        AccessControl(granter).grantRole(roleToGrant, to);
    }


    // ~ View Functions ~

    //
}