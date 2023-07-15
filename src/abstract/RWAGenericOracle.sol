// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import "./AdminAccess.sol";
import "../interfaces/IPriceOracle.sol";

abstract contract RWAGenericOracle is AdminAccess, IPriceOracle {
    struct OraclePrices {
        uint256 weSellAt;
        uint256 weSellAtStock;
        uint256 weBuyAt;
        uint256 weBuyAtStock;
    }

    struct OracleData {
        uint256 fingerprint;
        uint256 weSellAt;
        uint256 weSellAtStock;
        uint256 weBuyAt;
        uint256 weBuyAtStock;
    }

    event DecimalsUpdated(
        uint256 indexed oldDecimals,
        uint256 indexed newDecimals
    );
    event TimestampUpdated(
        uint256 indexed fingerprintId,
        uint256 oldTimestamp,
        uint256 newTimestamp
    );
    event PriceUpdated(
        uint256 indexed fingerprint,
        uint256 sellAtOld,
        uint256 buyAtOld,
        uint256 sellAtNew,
        uint256 buyAtNew
    );

    mapping(uint256 => OraclePrices) internal oraclePrices;
    mapping(uint256 => uint256) internal additionals;
    mapping(uint256 => uint256) internal fingerprintTimestamps;
    uint256[] public fingerprintsInOracle; //list of fingerprints that have prices
    mapping(uint256 => bool) public fingerprintHasPrice;
    string public oracleCurrency;
    uint256 public latestPrices;

    function latestTimeStamp(uint256 fingerprint)
        external
        view
        override
        returns (uint256)
    {
        return fingerprintTimestamps[fingerprint];
    }

    function oracleDataAll()
        public
        view
        returns (
            OracleData[] memory currentData,
            uint256[] memory currentAdditionals
        )
    {
        uint256 length = fingerprintsInOracle.length;
        currentData = new OracleData[](length);
        currentAdditionals = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            currentData[i].weSellAt = oraclePrices[fingerprintsInOracle[i]]
                .weSellAt;
            currentData[i].weSellAtStock = oraclePrices[fingerprintsInOracle[i]]
                .weSellAtStock;
            currentData[i].weBuyAt = oraclePrices[fingerprintsInOracle[i]]
                .weBuyAt;
            currentData[i].weBuyAtStock = oraclePrices[fingerprintsInOracle[i]]
                .weBuyAtStock;
            currentData[i].fingerprint = fingerprintsInOracle[i];
            currentAdditionals[i] = additionals[fingerprintsInOracle[i]];
        }
    }

    function oracleDataBatch(uint256[] calldata fingerprints)
        public
        view
        returns (
            OracleData[] memory currentData,
            uint256[] memory currentAdditionals
        )
    {
        uint256 length = fingerprints.length;
        currentData = new OracleData[](length);
        currentAdditionals = new uint256[](length);

        for (uint256 i = 0; i < length; i++) {
            currentData[i].weSellAt = oraclePrices[fingerprints[i]].weSellAt;
            currentData[i].weSellAtStock = oraclePrices[fingerprints[i]]
                .weSellAtStock;
            currentData[i].weBuyAt = oraclePrices[fingerprints[i]].weBuyAt;
            currentData[i].weBuyAtStock = oraclePrices[fingerprints[i]]
                .weBuyAtStock;
            currentData[i].fingerprint = fingerprints[i];
            currentAdditionals[i] = additionals[fingerprints[i]];
        }
    }

    function decrementSellStock(uint256 fingerprint)
        external
        override
        onlyFactory
    {
        require(
            oraclePrices[fingerprint].weSellAtStock > 0,
            "Already zero sell"
        );
        oraclePrices[fingerprint].weSellAtStock--;
    }

    //to be called by Instant liquidity engine
    function decrementBuyStock(uint256 fingerprint)
        external
        override
        onlyFactory
    {
        require(oraclePrices[fingerprint].weBuyAtStock > 0, "Already zero buy");
        oraclePrices[fingerprint].weBuyAtStock--;
    }

    function availableInStock(uint256 fingerprint)
        external
        view
        override
        returns (uint256 weSellAtStock, uint256 weBuyAtStock)
    {
        return (
            oraclePrices[fingerprint].weSellAtStock,
            oraclePrices[fingerprint].weBuyAtStock
        );
    }

    function addOraclePrices(
        uint256[] calldata _fingerprint,
        uint256[] calldata _weSellAt,
        uint256[] calldata _weBuyAt
    ) external virtual onlyAdmin {
        require(
            ((_fingerprint.length == _weSellAt.length) &&
                (_fingerprint.length == _weBuyAt.length) &&
                (_fingerprint.length > 0)),
            "Array must have the same length"
        );
        uint256 length = _fingerprint.length;

        for (uint256 i = 0; i < length; i++) {
            emit PriceUpdated(
                _fingerprint[i],
                oraclePrices[_fingerprint[i]].weSellAt,
                oraclePrices[_fingerprint[i]].weBuyAt,
                _weSellAt[i],
                _weBuyAt[i]
            );
            //update the prices
            oraclePrices[_fingerprint[i]].weSellAt = _weSellAt[i];
            oraclePrices[_fingerprint[i]].weBuyAt = _weBuyAt[i];
            //check if we had fingerprint before
            if (!fingerprintHasPrice[_fingerprint[i]]) {
                fingerprintsInOracle.push(_fingerprint[i]);
                //update mapping
                fingerprintHasPrice[_fingerprint[i]] = true;
            }
            emit TimestampUpdated(
                _fingerprint[i],
                fingerprintTimestamps[_fingerprint[i]],
                block.timestamp
            );
            //update the timestamp of updated price
            fingerprintTimestamps[_fingerprint[i]] = block.timestamp;
        }
        latestPrices++;
    }

    function addOracleStock(
        uint256[] calldata _fingerprint,
        uint256[] calldata _weSellAtStock,
        uint256[] calldata _weBuyAtStock
    ) external onlyAdmin {
        require(
            ((_fingerprint.length == _weSellAtStock.length) &&
                (_fingerprint.length == _weBuyAtStock.length)),
            "Array must have the same length"
        );
        uint256 length = _fingerprint.length;

        for (uint256 i = 0; i < length; i++) {
            oraclePrices[_fingerprint[i]].weSellAtStock = _weSellAtStock[i];
            oraclePrices[_fingerprint[i]].weBuyAtStock = _weBuyAtStock[i];
        }
    }

    function addOracleAdditionals(
        uint256[] calldata _fingerprint,
        uint256[] calldata _additionals //fees that acompany the RE, additional costs that form marketprice
    ) external onlyAdmin {
        require(
            (_fingerprint.length == _additionals.length) &&
                (_fingerprint.length > 0),
            "Array must have the same length"
        );
        uint256 length = _fingerprint.length;
        for (uint256 i = 0; i < length; i++) {
            additionals[_fingerprint[i]] = _additionals[i];
        }
        latestPrices++;
    }

    function getFingerprints() external view returns (uint256[] memory) {
        return fingerprintsInOracle;
    }
}
