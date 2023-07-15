// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import "./ITangibleFractionsNFT.sol";

interface ITangibleFractionsNFTDeployer {
    function deployFractionTnft(
        address admin,
        address _tnft,
        address _storageManager,
        address _rentShare,
        uint256 _tnftTokenId,
        string calldata name,
        string calldata symbol
    ) external returns (ITangibleFractionsNFT);
}
