// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import "../interfaces/ISellFeeDistributor.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "../helpers/Ownable.sol";
import "../interfaces/IExchange.sol";

contract SellFeeDistributor is ISellFeeDistributor, Ownable {
    using SafeERC20 for IERC20;

    IERC20 public immutable USDC;
    IERC20 public immutable TNGBL;
    address public revenueShare;

    uint256 public burnPercent;
    uint256 public revenuePercent;
    uint256 private immutable fullPercent = 100000000000;
    IExchange public exchange;
    bool public isMainnet;

    constructor(
        address _revenueShare,
        address _usdc,
        address _tngbl,
        bool _isMainnet
    ) {
        USDC = IERC20(_usdc);
        TNGBL = IERC20(_tngbl);
        revenueShare = _revenueShare;
        burnPercent = 33333333333;
        revenuePercent = 66666666666;
        isMainnet = _isMainnet;
    }

    function setRevenueShare(address _revenueShare) external onlyOwner {
        require(
            (_revenueShare != address(0)) && (_revenueShare != revenueShare),
            "Wrong revenue"
        );
        revenueShare = _revenueShare;
    }

    function setExchange(address _exchange) external onlyOwner {
        require(_exchange != address(0), "za");
        exchange = IExchange(_exchange);
    }

    function setPercentages(uint256 _revenuePercent, uint256 _burnPercent)
        external
        onlyOwner
    {
        require(
            (_revenuePercent + _burnPercent) == 99999999999,
            "Wrong percentages"
        );
        require((_revenuePercent > _burnPercent), "Burn higher");
        revenuePercent = _revenuePercent;
        burnPercent = _burnPercent;
    }

    function withdraw() external onlyOwner {
        USDC.safeTransfer(msg.sender, USDC.balanceOf(address(this)));
    }

    function withdrawToken(IERC20 token) external onlyOwner {
        token.safeTransfer(msg.sender, token.balanceOf(address(this)));
    }

    function distributeFee(IERC20 paymentToken, uint256 feeAmount)
        external
        override
    {
        _distributeFee(paymentToken, feeAmount);
    }

    function _distributeFee(IERC20 paymentToken, uint256 feeAmount) internal {
        //take 33.333% and send to revenueShare
        uint256 amountForRevenue = (feeAmount * revenuePercent) / fullPercent;
        if (address(paymentToken) != address(USDC)) {
            //we need to convert the payment token to usdc
            paymentToken.approve(address(exchange), amountForRevenue);
            amountForRevenue = exchange.exchange(
                address(paymentToken),
                address(USDC),
                amountForRevenue,
                exchange.quoteOut(
                    address(paymentToken),
                    address(USDC),
                    amountForRevenue
                )
            );
        }
        USDC.safeTransfer(revenueShare, amountForRevenue);

        //convert 66.6666% to tngbl and burn it
        uint256 amountForBurn = (feeAmount * burnPercent) / fullPercent;
        // exchange usdc for tngbl
        paymentToken.approve(address(exchange), amountForBurn);
        uint256 tngblToBurn = exchange.exchange(
            address(paymentToken),
            address(TNGBL),
            amountForBurn,
            exchange.quoteOut(
                address(paymentToken),
                address(TNGBL),
                amountForBurn
            )
        );
        //burn the tngbl
        TNGBL.approve(address(this), tngblToBurn);
        if (isMainnet) {
            ERC20Burnable(address(TNGBL)).burn(tngblToBurn);
        }
    }
}
