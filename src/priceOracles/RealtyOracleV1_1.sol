// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import "../abstract/PriceConverter.sol";
import "../abstract/AdminAccess.sol";
import "../interfaces/IPriceOracle.sol";
import "../interfaces/ICurrencyFeedV1_1.sol";
import "../interfaces/IChainlinkRWAOracle.sol";

contract RealtyOracleTangibleV1_1 is AdminAccess, IPriceOracle, PriceConverter {
    ICurrencyFeedV1_1 public currencyFeed;
    IChainlinkRWAOracle public chainlinkRWAOracle;

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        oracleCurrency = "GBP";
    }

    /// @dev Fetches decimals that this oracle holds.
    function decimals() public view override returns (uint8) {
        // return from chainlink oracle
        return chainlinkRWAOracle.getDecimals();
    }

    /// @dev The function latest price from oracle.
    string public override description = "Real estate Oracle";

    /// @dev The function latest price from oracle.
    uint256 public override version = 4;

    function convertNativePriceToUSD(
        uint256 nativePrice,
        uint16 currencyISONum
    ) internal view returns (uint256) {
        // take it differently from currency feed
        AggregatorV3Interface priceFeedNativeToUSD = currencyFeed
            .currencyPriceFeedsISONum(currencyISONum);
        (, int256 price, , , ) = priceFeedNativeToUSD.latestRoundData();
        if (price < 0) {
            price = 0;
        }
        //add conversion premium
        uint256 nativeToUSD = uint256(price) +
            currencyFeed.conversionPremiumsISONum(currencyISONum);
        return
            (nativePrice * nativeToUSD) /
            10 ** uint256(priceFeedNativeToUSD.decimals());
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
            "Must provide fingerpeint or tokenId"
        );
        uint256 localFingerprint = fingerprint;

        if (localFingerprint == 0) {
            localFingerprint = nft.tokensFingerprint(tokenId);
        }
        uint8 localDecimals = chainlinkRWAOracle.getDecimals();

        require(localFingerprint != 0, "fingerprint must exist");
        IChainlinkRWAOracle.Data memory fingData = chainlinkRWAOracle
            .fingerprintData(localFingerprint);

        lockedAmount = convertPriceToUSDCustom(
            paymentUSDToken,
            convertNativePriceToUSD(fingData.lockedAmount, fingData.currency),
            localDecimals
        );

        weSellAt = convertPriceToUSDCustom(
            paymentUSDToken,
            convertNativePriceToUSD(fingData.weSellAt, fingData.currency),
            localDecimals
        );
        weBuyAt = 0;

        weSellAtStock = fingData.weSellAtStock;
        weBuyAtStock = 0;

        return (weSellAt, weSellAtStock, weBuyAt, weBuyAtStock, lockedAmount);
    }

    //not needed anymode
    //set decimals

    // this function will change interface when we redeploy
    function marketPriceNativeCurrency(
        uint256 fingerprint
    ) public view returns (uint256 nativePrice, string memory currency) {
        IChainlinkRWAOracle.Data memory data = chainlinkRWAOracle.fingerprintData(fingerprint);
        currency = currencyFeed.ISOcurrencyNumToCode(data.currency);

        nativePrice = data.weSellAt + data.lockedAmount;
    }

    function setCurrencyFeed(address _currencyFeed) external onlyAdmin {
        currencyFeed = ICurrencyFeedV1_1(_currencyFeed);
    }

    function setChainlinkOracle(address _chainlinkRWAOracle) external onlyAdmin {
        chainlinkRWAOracle = IChainlinkRWAOracle(_chainlinkRWAOracle);
    }

    function fingerprintsInOracle(
        uint256 index
    ) public view returns (uint256 fingerprint) {
        // return value from chainlink oracle
        return chainlinkRWAOracle.fingerprints(index);
    }

    function fingerprintHasPrice(
        uint256 fingerprint
    ) public view returns (bool hasPrice) {
        // return value from chainlink oracle
        return chainlinkRWAOracle.fingerprintExists(fingerprint);
    }

    string public oracleCurrency;

    function latestTimeStamp(
        uint256 fingerprint
    ) external view override returns (uint256) {
        // return from chainlink oracle
        return chainlinkRWAOracle.fingerprintData(fingerprint).timestamp;
    }

    function lastUpdateOracle() external view returns (uint256){
        return chainlinkRWAOracle.lastUpdateTime();
    }

    function latestPrices() public view returns (uint256) {
        return chainlinkRWAOracle.latestPrices();
    }

    function oracleDataAll()
        public
        view
        returns (IChainlinkRWAOracle.Data[] memory currentData)
    {
        // return from chainlink oracle
        return chainlinkRWAOracle.oracleDataAll();
    }

    function oracleDataBatch(
        uint256[] calldata fingerprints
    )
        public
        view
        returns (IChainlinkRWAOracle.Data[] memory currentData)
    {
        // return from chainlink oracle
        return chainlinkRWAOracle.oracleDataBatch(fingerprints);
    }

    function decrementSellStock(
        uint256 fingerprint
    ) external override onlyFactory {
        // do it from chainlink oracle
        chainlinkRWAOracle.decrementStock(fingerprint);
    }

    function availableInStock(
        uint256 fingerprint
    )
        external
        view
        override
        returns (uint256 weSellAtStock, uint256 weBuyAtStock)
    {
        // return from chainlink oracle
        weSellAtStock = chainlinkRWAOracle
            .fingerprintData(fingerprint)
            .weSellAtStock;
        weBuyAtStock = 0;
    }

    function getFingerprints() external view returns (uint256[] memory) {
        // return from chainlink oracle
        return chainlinkRWAOracle.getFingerprintsAll();
    }

    function getFingerprintsLength() external view returns (uint256) {
        // return from chainlink oracle
        return chainlinkRWAOracle.getFingerprintsLength();
    }
    function decrementBuyStock(uint256 fingerprint) external override {}
}
