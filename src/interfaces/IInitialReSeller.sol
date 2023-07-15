// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import "./ITangibleFractionsNFT.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IInitialReSeller {
    struct FractionSaleData {
        IERC20 paymentToken;
        uint256 sellingToken;
        uint256 endTimestamp;
        uint256 startTimestamp;
        uint256 askingPrice;
        uint256 paidSoFar;
        uint256 indexInCurrentlySelling;
        uint256 indexInSold;
        bool sold;
    }

    struct FractionBuyer {
        address owner;
        uint256 fractionId;
        uint256 fractionShare;
        uint256 pricePaid;
        uint256 indexInSoldTokens;
    }

    event StoreBuyer(
        ITangibleFractionsNFT indexed ftnft,
        uint256 indexed fractionId,
        address buyer,
        uint256 indexed amount
    );
    event EndDateExtended(
        ITangibleFractionsNFT indexed ftnft,
        uint256 indexed endDate
    );
    event StartDateExtended(
        ITangibleFractionsNFT indexed ftnft,
        uint256 indexed startDate
    );
    event SaleAmountTaken(
        ITangibleFractionsNFT indexed ftnft,
        IERC20 indexed paymentToken,
        uint256 amount
    );
    event SaleStarted(
        ITangibleFractionsNFT indexed ftnft,
        uint256 indexed startDate,
        uint256 indexed endDate,
        uint256 sellingTokenId,
        uint256 askingPrice
    );

    // function saleData(address ftnft) external view returns(FractionSaleData calldata);
    // function saleBuyersData(address ftnft, uint256 fractionId) external view returns(FractionBuyer calldata);
    function updateBuyer(
        ITangibleFractionsNFT ftnft,
        address buyer,
        uint256 fractionId,
        uint256 amountPaid
    ) external;

    function completeSale(ITangibleFractionsNFT ftnft) external;

    function canSellFractions(ITangibleFractionsNFT ftnft)
        external
        view
        returns (bool);
}
