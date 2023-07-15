// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import "../abstract/AdminAndTangibleAccess.sol";
import "../interfaces/ITangiblePriceManager.sol";

contract TangiblePriceManager is ITangiblePriceManager, AdminAndTangibleAccess {
    mapping(ITangibleNFT => IPriceOracle) public oracleForCategory;

    struct PricesOracle {
        uint256 _weSellAt;
        uint256 _weSellAtStock;
        uint256 _weBuyAt;
        uint256 _weBuyAtStock;
        uint256 _lockedAmount;
    }

    struct PricesOracleArrays {
        uint256[] weSellAt;
        uint256[] weSellAtStock;
        uint256[] weBuyAt;
        uint256[] weBuyAtStock;
        uint256[] lockedAmount;
    }

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// @dev The function returns contract oracle for category.
    function getPriceOracleForCategory(ITangibleNFT category)
        external
        view
        override
        returns (IPriceOracle)
    {
        return oracleForCategory[category];
    }

    /// @dev The function returns current price from oracle for provided category.
    function setOracleForCategory(ITangibleNFT category, IPriceOracle oracle)
        external
        override
        onlyFactoryOrAdmin
    {
        require(address(category) != address(0), "Zero category");
        require(address(oracle) != address(0), "Zero oracle");
        oracleForCategory[category] = oracle;
        emit CategoryPriceOracleAdded(address(category), address(oracle));
    }

    function itemPriceBatchFingerprints(
        ITangibleNFT nft,
        IERC20Metadata paymentUSDToken,
        uint256[] calldata fingerprints
    )
        external
        view
        returns (
            uint256[] memory weSellAt,
            uint256[] memory weSellAtStock,
            uint256[] memory weBuyAt,
            uint256[] memory weBuyAtStock,
            uint256[] memory lockedAmount
        )
    {
        PricesOracleArrays memory pricesOracleArrays = _itemBatchPrices(
            nft,
            paymentUSDToken,
            fingerprints,
            true
        );

        return (
            pricesOracleArrays.weSellAt,
            pricesOracleArrays.weSellAtStock,
            pricesOracleArrays.weBuyAt,
            pricesOracleArrays.weBuyAtStock,
            pricesOracleArrays.lockedAmount
        );
    }

    function itemPriceBatchTokenIds(
        ITangibleNFT nft,
        IERC20Metadata paymentUSDToken,
        uint256[] calldata tokenIds
    )
        external
        view
        returns (
            uint256[] memory weSellAt,
            uint256[] memory weSellAtStock,
            uint256[] memory weBuyAt,
            uint256[] memory weBuyAtStock,
            uint256[] memory lockedAmount
        )
    {
        PricesOracleArrays memory pricesOracleArrays = _itemBatchPrices(
            nft,
            paymentUSDToken,
            tokenIds,
            false
        );

        return (
            pricesOracleArrays.weSellAt,
            pricesOracleArrays.weSellAtStock,
            pricesOracleArrays.weBuyAt,
            pricesOracleArrays.weBuyAtStock,
            pricesOracleArrays.lockedAmount
        );
    }

    function _itemBatchPrices(
        ITangibleNFT nft,
        IERC20Metadata paymentUSDToken,
        uint256[] calldata data,
        bool fromFingerprints
    ) internal view returns (PricesOracleArrays memory pricesOracleArrays) {
        uint256 length = data.length;
        pricesOracleArrays.weSellAt = new uint256[](length);
        pricesOracleArrays.weSellAtStock = new uint256[](length);
        pricesOracleArrays.weBuyAt = new uint256[](length);
        pricesOracleArrays.weBuyAtStock = new uint256[](length);
        pricesOracleArrays.lockedAmount = new uint256[](length);
        PricesOracle memory pricesOracle;

        for (uint256 i = 0; i < length; i++) {
            (
                pricesOracle._weSellAt,
                pricesOracle._weSellAtStock,
                pricesOracle._weBuyAt,
                pricesOracle._weBuyAtStock,
                pricesOracle._lockedAmount
            ) = fromFingerprints
                ? oracleForCategory[nft].usdcPrice(
                    nft,
                    paymentUSDToken,
                    data[i],
                    0
                )
                : oracleForCategory[nft].usdcPrice(
                    nft,
                    paymentUSDToken,
                    0,
                    data[i]
                );
            pricesOracleArrays.weSellAt[i] = pricesOracle._weSellAt;
            pricesOracleArrays.weSellAtStock[i] = pricesOracle._weSellAtStock;
            pricesOracleArrays.weBuyAt[i] = pricesOracle._weBuyAt;
            pricesOracleArrays.weBuyAtStock[i] = pricesOracle._weBuyAtStock;
            pricesOracleArrays.lockedAmount[i] = pricesOracle._lockedAmount;
        }
        return pricesOracleArrays;
    }
}
