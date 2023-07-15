// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import "./ITangibleNFT.sol";

interface ITangibleNFTDeployer {
    event SetFactoryDeployer(
        address indexed oldFactory,
        address indexed newFactory
    );

    function deployTnft(
        address admin,
        string calldata name,
        string calldata symbol,
        string calldata uri,
        bool isStoragePriceFixedAmount,
        bool storageRequired,
        uint256 _lockPercentage,
        bool _paysRent
    ) external returns (ITangibleNFT);
}
