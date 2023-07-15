// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import "./IFractionStorageManager.sol";

interface IFractionStorageManagerDeployer {
    function deployStorageManagerTnft(
        address _tnft,
        address _factory,
        uint256 _tnftTokenId
    ) external returns (IFractionStorageManager);
}
