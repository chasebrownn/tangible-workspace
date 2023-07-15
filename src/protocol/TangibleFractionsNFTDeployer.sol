// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import "./TangibleFractionsNFT.sol";
import "../interfaces/ITangibleFractionsNFTDeployer.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "../helpers/Ownable.sol";

contract TangibleFractionsNFTDeployer is
    ITangibleFractionsNFTDeployer,
    Ownable
{
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant FACTORY_ROLE = keccak256("FACTORY");
    address public factory;

    function setFactory(address _factory) external onlyOwner {
        //we as owners are the only ones who can set this
        //so will be careful what weset here
        factory = _factory;
    }

    function deployFractionTnft(
        address admin,
        address _tnft,
        address _storageManager,
        address rentShare,
        uint256 _tnftTokenId,
        string memory name,
        string memory symbol
    ) external override returns (ITangibleFractionsNFT) {
        require(msg.sender == factory, "NF");
        TangibleFractionsNFT tangibleFractionsNFT = new TangibleFractionsNFT(
            msg.sender,
            _tnft,
            _storageManager,
            name,
            symbol,
            _tnftTokenId,
            rentShare
        );
        _roleGranter(
            address(tangibleFractionsNFT),
            admin,
            DEFAULT_ADMIN_ROLE,
            true
        );
        _roleGranter(
            address(tangibleFractionsNFT),
            factory,
            FACTORY_ROLE,
            true
        );
        _roleGranter(
            address(tangibleFractionsNFT),
            factory,
            DEFAULT_ADMIN_ROLE,
            false
        );

        return tangibleFractionsNFT;
    }

    function _roleGranter(
        address granter,
        address to,
        bytes32 roleToGrant,
        bool grant
    ) internal {
        grant
            ? AccessControl(granter).grantRole(roleToGrant, to)
            : AccessControl(granter).revokeRole(roleToGrant, to);
    }
}
