// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import "../interfaces/ICurrencyFeed.sol";
import "../abstract/AdminAccess.sol";

contract CurrencyFeed is ICurrencyFeed, AdminAccess {
    mapping(string => AggregatorV3Interface) public override currencyPriceFeeds;
    mapping(string => uint256) public override conversionPremiums;

    function setCurrencyFeed(
        string memory currency,
        AggregatorV3Interface priceFeed
    ) external onlyAdmin {
        currencyPriceFeeds[currency] = priceFeed;
    }

    function setCurrencyConversionPremium(
        string memory currency,
        uint256 conversionPremium
    ) external onlyAdmin {
        conversionPremiums[currency] = conversionPremium;
    }
}
