// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

interface ICurrencyFeedV1_1 {
    function currencyPriceFeeds(string calldata currency)
        external
        view
        returns (AggregatorV3Interface priceFeed);

    function conversionPremiums(string calldata currency)
        external
        view
        returns (uint256 conversionPremium);
    
    function currencyPriceFeedsISONum(uint16 currencyISONum)
        external
        view
        returns (AggregatorV3Interface priceFeed);

    function conversionPremiumsISONum(uint16 currencyISONum)
        external
        view
        returns (uint256 conversionPremium);

     // iso currency data
    function ISOcurrencyCodeToNum(string calldata currencyCode )
        external
        view
        returns (uint16 currencyISONum);

    function ISOcurrencyNumToCode(uint16 currencyISONum )
        external
        view
        returns (string memory currencyCode);
    // iso country data
    function ISOcountryCodeToNum(string calldata countryCode )
        external
        view
        returns (uint16 countryISONum);

    function ISOcountryNumToCode(uint16 countryISONum )
        external
        view
        returns (string memory countryCode);
}
