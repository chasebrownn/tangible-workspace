// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import "./TangibleNFT.sol";
import "../interfaces/ITangibleNFTDeployer.sol";
import "../helpers/Ownable.sol";

contract TangibleNFTDeployer is ITangibleNFTDeployer, Ownable {
    address public factory;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant FACTORY_ROLE = keccak256("FACTORY");

    function setFactory(address _factory) external onlyOwner {
        //we as owners are the only ones who can set this
        //so will be careful what weset here
        factory = _factory;
    }

    function deployTnft(
        address admin,
        string calldata name,
        string calldata symbol,
        string calldata uri,
        bool isStoragePriceFixedAmount,
        bool storageRequired,
        uint256 _lockPercentage,
        bool _paysRent
    ) external override returns (ITangibleNFT) {
        require(msg.sender == factory, "NF");
        TangibleNFT tangibleNFT = new TangibleNFT(
            msg.sender,
            name,
            symbol,
            uri,
            isStoragePriceFixedAmount,
            storageRequired,
            _lockPercentage,
            _paysRent
        );
        tangibleNFT.grantRole(DEFAULT_ADMIN_ROLE, admin);
        tangibleNFT.grantRole(FACTORY_ROLE, admin);
        tangibleNFT.revokeRole(DEFAULT_ADMIN_ROLE, address(this));

        return tangibleNFT;
    }
}
