// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import "./ITangibleFractionsNFT.sol";
import "./ITangibleNFT.sol";

interface IOnSaleTracker {
    function tnftSalePlaced(
        ITangibleNFT tnft,
        uint256 tokenId,
        bool placed
    ) external;

    function ftnftSalePlaced(
        ITangibleFractionsNFT ftnft,
        uint256 tokenId,
        bool placed
    ) external;
}
