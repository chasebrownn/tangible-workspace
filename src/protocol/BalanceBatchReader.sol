// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";



contract BalanceBatchReader {

    function balancesOfAddresses(
        IERC20 tokenAddress,
        address[] calldata wallets
    ) external view returns (uint256[] memory balances){
        uint256 length = wallets.length;
        balances = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            balances[i] = tokenAddress.balanceOf(wallets[i]);
        }
    }
}
