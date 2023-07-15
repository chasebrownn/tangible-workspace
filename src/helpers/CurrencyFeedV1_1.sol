// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import "../interfaces/ICurrencyFeedV1_1.sol";
import "../abstract/AdminAccess.sol";

contract CurrencyFeedV1_1 is ICurrencyFeedV1_1, AdminAccess {
    // code
    mapping(string => AggregatorV3Interface) public override currencyPriceFeeds;
    mapping(string => uint256) public override conversionPremiums;
    // number
    mapping(uint16 => AggregatorV3Interface) public override currencyPriceFeedsISONum;
    mapping(uint16 => uint256) public override conversionPremiumsISONum;

    // iso currency data
    mapping(string => uint16) public override ISOcurrencyCodeToNum;
    mapping(uint16 => string) public override ISOcurrencyNumToCode;
    // iso country data
    mapping(string => uint16) public override ISOcountryCodeToNum;
    mapping(uint16 => string) public override ISOcountryNumToCode;
    
    function setISOCurrencyData(
        string memory currency,
        uint16 currencyISONum
    ) external onlyAdmin{
        ISOcurrencyCodeToNum[currency] = currencyISONum;
        ISOcurrencyNumToCode[currencyISONum] = currency;
    }
    function setISOCountryData(
        string memory country,
        uint16 countryISONum
    ) external onlyAdmin{
        ISOcountryCodeToNum[country] = countryISONum;
        ISOcountryNumToCode[countryISONum] = country;
    }

    function setCurrencyFeed(
        string calldata currency,
        AggregatorV3Interface priceFeed
    ) external onlyAdmin {
        currencyPriceFeeds[currency] = priceFeed;
        // set for iso
        currencyPriceFeedsISONum[ISOcurrencyCodeToNum[currency]] = priceFeed;
    }

    function setCurrencyConversionPremium(
        string calldata currency,
        uint256 conversionPremium
    ) external onlyAdmin {
        conversionPremiums[currency] = conversionPremium;
        // set for iso
        conversionPremiumsISONum[ISOcurrencyCodeToNum[currency]] = conversionPremium;
    }
}
