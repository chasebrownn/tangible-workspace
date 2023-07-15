// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

interface IILCalculator {
    function calculateILPrice(uint256 weSellAt, uint256 weBuyAt)
        external
        view
        returns (uint256 result);

    function isItVolatile(uint256 tngblOraclePrice, uint256 tngblSushiPrice)
        external
        view
        returns (bool result);
}
