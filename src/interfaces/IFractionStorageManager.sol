// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import "./ITangibleFractionsNFT.sol";

interface IFractionStorageManager {
    function adjustFTNFT() external;

    function canTransfer(uint256 fractionTokenId) external view returns (bool);

    function moveSPaymentToAnother(uint256 origin, uint256 destination)
        external;

    function payShareStorage(uint256) external;

    function fracTnft() external view returns (ITangibleFractionsNFT);
}
