// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import "../abstract/RWAGenericOracle.sol";
import "../abstract/PriceConverter.sol";
import "../interfaces/ICurrencyFeed.sol";

contract WatchOracleTangible is RWAGenericOracle, PriceConverter {
    ICurrencyFeed public currencyFeed;

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        oracleCurrency = "GBP";
    }

    /// @dev The function latest price from oracle.
    uint8 public override decimals = 3;

    /// @dev The function latest price from oracle.
    string public override description = "Watch Oracle";

    /// @dev The function latest price from oracle.
    uint256 public override version = 3;

    uint256 public conversionPremium;

    function convertGBPToUSD(uint256 priceInGBP)
        internal
        view
        returns (uint256)
    {
        AggregatorV3Interface priceFeedGBP = currencyFeed.currencyPriceFeeds(
            oracleCurrency
        );
        (, int256 price, , , ) = priceFeedGBP.latestRoundData();
        if (price < 0) {
            price = 0;
        }
        //add conversion premium
        uint256 GBPToUSD = uint256(price) +
            currencyFeed.conversionPremiums(oracleCurrency);
        return (priceInGBP * GBPToUSD) / 10**uint256(priceFeedGBP.decimals());
    }

    function usdcPrice(
        ITangibleNFT nft,
        IERC20Metadata paymentUSDToken,
        uint256 fingerprint,
        uint256 tokenId
    )
        external
        view
        override
        returns (
            uint256 weSellAt,
            uint256 weSellAtStock,
            uint256 weBuyAt,
            uint256 weBuyAtStock,
            uint256 lockedAmount
        )
    {
        require(
            (address(nft) != address(0) && tokenId != 0) || (fingerprint != 0),
            "Must provide fingerprint or tokenId"
        );
        uint256 localFingerprint = fingerprint;

        if (localFingerprint == 0) {
            localFingerprint = nft.tokensFingerprint(tokenId);
        }

        require(localFingerprint != 0, "fingerprint must exist");

        uint256 _lockedAmount = (nft.lockPercent() *
            oraclePrices[localFingerprint].weSellAt) / 10000;

        weSellAt = convertPriceToUSDCustom(
            paymentUSDToken,
            convertGBPToUSD(oraclePrices[localFingerprint].weSellAt),
            decimals
        );
        weBuyAt = convertPriceToUSDCustom(
            paymentUSDToken,
            convertGBPToUSD(oraclePrices[localFingerprint].weBuyAt),
            decimals
        );
        lockedAmount = convertPriceToUSDCustom(
            paymentUSDToken,
            convertGBPToUSD(_lockedAmount),
            decimals
        );

        weSellAtStock = oraclePrices[localFingerprint].weSellAtStock;
        weBuyAtStock = oraclePrices[localFingerprint].weBuyAtStock;

        return (weSellAt, weSellAtStock, weBuyAt, weBuyAtStock, lockedAmount);
    }

    //set decimals
    function setDecimals(uint8 _decimals) external onlyAdmin {
        emit DecimalsUpdated(decimals, _decimals);
        decimals = _decimals;
    }

    function setCurrencyFeed(address _currencyFeed) external onlyAdmin {
        currencyFeed = ICurrencyFeed(_currencyFeed);
    }
}
