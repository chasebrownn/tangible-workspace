// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import "../abstract/AdminAccess.sol";
import "../interfaces/IPriceOracle.sol";
import "../abstract/PriceConverter.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract GoldOracleTangible is AdminAccess, IPriceOracle, PriceConverter {
    AggregatorV3Interface internal priceFeed;
    struct GoldBar {
        ITangibleNFT gbNft;
        uint256 grams;
        uint256 premiumPercentage; //in percentage: 1234 -> 1.234 %;  50 -> 0.005 USD
        uint256 premiumFixed; // in usdc 60$ -> 60000000
        uint256 weSellAtStock;
        uint256 weBuyAtStock;
    }

    event GoldBarAdded(
        address nft,
        string barName,
        uint256 fingerprint,
        uint256 grams,
        uint256 premiumPrice
    );

    mapping(uint256 => GoldBar) public goldBars;

    uint256 public unz = 311034768; // 7 decimals 31.1034768gr

    uint256 public belowPercent;

    constructor(address goldOracle) {
        require(goldOracle != address(0), "Empty address");
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        priceFeed = AggregatorV3Interface(goldOracle);
        belowPercent = 500;
    }

    function _latestAnswer(uint256 fingerprint)
        internal
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        require(goldBars[fingerprint].grams > 0, "No data for tnft");
        (, int256 price, , , ) = priceFeed.latestRoundData();
        if (price < 0) {
            price = 0;
        }

        uint256 priceForGrams = ((convertToOracleDecimals(
            goldBars[fingerprint].grams,
            0
        ) * uint256(price)) / convertToOracleDecimals(unz, uint8(7)));

        uint256 premium = attachPremium(priceForGrams, fingerprint);

        uint256 lockAmount = ((priceForGrams + premium) *
            goldBars[fingerprint].gbNft.lockPercent()) / 10000;

        return (priceForGrams, premium, lockAmount);
    }

    /// @inheritdoc IPriceOracle
    function latestTimeStamp(uint256 fingerprint)
        external
        view
        override
        returns (uint256)
    {
        require(goldBars[fingerprint].grams > 0, "No data for tnft");
        (, , , uint256 timeStamp, ) = priceFeed.latestRoundData();
        return timeStamp;
    }

    /// @inheritdoc IPriceOracle
    function decimals() external view override returns (uint8) {
        return _decimals();
    }

    function _decimals() internal view returns (uint8) {
        return priceFeed.decimals();
    }

    /// @inheritdoc IPriceOracle
    function description() external view override returns (string memory desc) {
        return priceFeed.description();
    }

    function version() external view override returns (uint256) {
        return priceFeed.version();
    }

    function attachPremium(uint256 priceForGrams, uint256 fingerprint)
        internal
        view
        returns (uint256)
    {
        uint256 premium;
        if (goldBars[fingerprint].premiumFixed > 0) {
            premium += goldBars[fingerprint].premiumFixed;
        }
        if (goldBars[fingerprint].premiumPercentage > 0) {
            premium += calculatePremium(
                priceForGrams,
                goldBars[fingerprint].premiumPercentage
            );
        }
        return premium;
    }

    function calculatePremium(uint256 price, uint256 percentage)
        internal
        pure
        returns (uint256)
    {
        //percentage can have 3 decimal places
        //for example 1234 is 1.234%
        return (price * percentage) / 100000;
    }

    function convertToOracleDecimals(uint256 price, uint8 priceDecimals)
        internal
        view
        returns (uint256)
    {
        uint8 localDecimals = _decimals();
        if (uint256(priceDecimals) > localDecimals) {
            return price / (10**(uint256(priceDecimals) - localDecimals));
        } else if (uint256(priceDecimals) < localDecimals) {
            return price * (10**(localDecimals - uint256(priceDecimals)));
        }
        return price;
    }

    // function pricePerGram(uint256 price) internal view returns (uint256) {
    //     uint256 alignedUnz = convertToOracleDecimals(unz, uint8(7));
    //     return price / 31;
    // }

    function decrementSellStock(uint256 fingerprint)
        external
        override
        onlyFactory
    {
        require(goldBars[fingerprint].weSellAtStock > 0, "Already zero sell");
        goldBars[fingerprint].weSellAtStock--;
    }

    function decrementBuyStock(uint256 fingerprint)
        external
        override
        onlyFactory
    {
        require(goldBars[fingerprint].weBuyAtStock > 0, "Already zero buy");
        goldBars[fingerprint].weBuyAtStock--;
    }

    function availableInStock(uint256 fingerprint)
        external
        view
        override
        returns (uint256, uint256)
    {
        return (
            goldBars[fingerprint].weSellAtStock,
            goldBars[fingerprint].weBuyAtStock
        );
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
        (
            uint256 _priceOracle,
            uint256 _premium,
            uint256 _lockedAmount
        ) = _latestAnswer(localFingerprint);
        uint8 decimalsLocal = _decimals();
        weSellAt = convertPriceToUSDCustom(
            paymentUSDToken,
            _priceOracle + _premium,
            decimalsLocal
        ); //plus premium to add
        weBuyAt = convertPriceToUSDCustom(
            paymentUSDToken,
            (_priceOracle - calculatePremium(_priceOracle, belowPercent)),
            decimalsLocal
        );
        lockedAmount = convertPriceToUSDCustom(
            paymentUSDToken,
            _lockedAmount,
            decimalsLocal
        );
        weSellAtStock = goldBars[localFingerprint].weSellAtStock;
        weBuyAtStock = goldBars[localFingerprint].weBuyAtStock;

        return (weSellAt, weSellAtStock, weBuyAt, weBuyAtStock, lockedAmount);
    }

    function addGoldBar(
        ITangibleNFT nft,
        uint256 fingerprint,
        uint256 grams,
        uint256 premiumPercentage,
        uint256 premiumFixed
    ) external onlyAdmin {
        require(address(nft) != address(0), "Zero nft");
        require(grams > 0, "Zero grams");
        require(
            (premiumPercentage > 0) || (premiumFixed > 0),
            "premium not set"
        );

        if (goldBars[fingerprint].grams > 0) {
            //we update
            goldBars[fingerprint].gbNft = nft;
            goldBars[fingerprint].grams = grams;
            goldBars[fingerprint].premiumPercentage = premiumPercentage;
            goldBars[fingerprint].premiumFixed = premiumFixed;
        } else {
            //we add new
            GoldBar memory gb = GoldBar({
                gbNft: nft,
                grams: grams,
                premiumPercentage: premiumPercentage,
                premiumFixed: premiumFixed,
                weSellAtStock: 0,
                weBuyAtStock: 0
            });
            goldBars[fingerprint] = gb;
        }

        emit GoldBarAdded(
            address(nft),
            nft.name(),
            fingerprint,
            grams,
            premiumPercentage
        );
    }

    function addGoldBarStock(
        uint256 fingerprint,
        uint256 weSellAtStock,
        uint256 weBuyAtStock
    ) external onlyAdmin {
        goldBars[fingerprint].weSellAtStock = weSellAtStock;
        goldBars[fingerprint].weBuyAtStock = weBuyAtStock;
    }

    function setBelowSpotPercent(uint256 percent) external onlyAdmin {
        belowPercent = percent;
    }
}
