// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import "./FractionStorageManager.sol";
import "../interfaces/IFractionStorageManagerDeployer.sol";
import "../helpers/Ownable.sol";

contract FractionStorageManagerDeployer is
    IFractionStorageManagerDeployer,
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

    function deployStorageManagerTnft(
        address _tnft,
        address _factory,
        uint256 _tnftTokenId
    ) external override returns (IFractionStorageManager) {
        address sender = msg.sender;
        require(sender == factory, "NF");
        FractionStorageManager storageManager = new FractionStorageManager(
            ITangibleNFT(_tnft),
            IFactory(_factory),
            _tnftTokenId
        );

        storageManager.adjustFTNFT();
        return storageManager;
    }
}
