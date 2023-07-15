// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

abstract contract PriceConverter {
    function convertPriceToUSDCustom(
        IERC20Metadata paymentToken,
        uint256 price,
        uint8 decimals
    ) internal view returns (uint256) {
        require(
            decimals > uint8(0) && decimals <= uint8(18),
            "Invalid _decimals"
        );
        if (uint256(decimals) > paymentToken.decimals()) {
            return price / (10**(uint256(decimals) - paymentToken.decimals()));
        } else if (uint256(decimals) < paymentToken.decimals()) {
            return price * (10**(paymentToken.decimals() - uint256(decimals)));
        }
        return price;
    }
}
