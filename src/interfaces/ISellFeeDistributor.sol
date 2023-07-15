// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ISellFeeDistributor {
    event FeeDistributed(address indexed to, uint256 usdcAmount);
    event TangibleBurned(uint256 burnedTngbl);

    function distributeFee(IERC20 paymentToken, uint256 feeAmount) external;
}
