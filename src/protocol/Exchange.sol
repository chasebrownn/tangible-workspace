// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IWETH9.sol";
import "../abstract/AdminAccess.sol";
import "../interfaces/IExchange.sol";

contract Exchange is IExchange, AdminAccess {
    using SafeERC20 for IERC20;
    bytes32 constant ROUTER_POLICY_ROLE = bytes32(keccak256("ROUTER_POLICY"));

    address public immutable override router = address(0);
    mapping(bytes => address) public routers;
    mapping(address => bool) public tngblPoolTokens;
    IERC20 public immutable DAI;
    IERC20 public immutable TNGBL;

    constructor(address _dai, address _tngbl) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ROUTER_POLICY_ROLE, msg.sender);
        DAI = IERC20(_dai);
        TNGBL = IERC20(_tngbl);
        tngblPoolTokens[_dai] = true;
    }

    function addRouterForTokens(
        address tokenInAddress,
        address tokenOutAddress,
        address _router
    ) external onlyRole(ROUTER_POLICY_ROLE) {
        bytes memory tokenized = abi.encodePacked(
            tokenInAddress,
            tokenOutAddress
        );
        bytes memory tokenizedReverse = abi.encodePacked(
            tokenOutAddress,
            tokenInAddress
        );
        routers[tokenized] = _router;
        routers[tokenizedReverse] = _router;
    }

    function exchange(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 minAmountOut
    ) external override returns (uint256) {
        address[] memory path = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        //take the token
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);

        if (tokenIn != address(TNGBL) && tokenOut != address(TNGBL)) {
            bytes memory tokenized = abi.encodePacked(tokenIn, tokenOut);
            address _router = routers[tokenized];
            require(address(0) != _router, "router 0 ng");

            //approve the router
            IERC20(tokenIn).approve(_router, amountIn);
            amounts = IUniswapV2Router01(_router).swapExactTokensForTokens(
                amountIn,
                minAmountOut,
                path,
                address(this),
                block.timestamp + 15 // on sushi?
            );
        } else {
            path[1] = address(DAI);
            bytes memory tokenized = abi.encodePacked(tokenIn, address(DAI));
            address _router = routers[tokenized];
            require(address(0) != _router, "router 0 tg");

            //approve the router
            IERC20(tokenIn).approve(_router, amountIn);

            amounts = IUniswapV2Router01(_router).swapExactTokensForTokens(
                amountIn,
                0,
                path,
                address(this),
                block.timestamp + 15 // on sushi?
            );

            path[0] = address(DAI);
            path[1] = tokenOut;
            //set for new
            tokenized = abi.encodePacked(address(DAI), tokenOut);
            _router = routers[tokenized];
            require(address(0) != _router, "router 0 mg");

            // we swapped to dai and now we swap from dai to tngbl
            IERC20(DAI).approve(_router, amounts[1]);

            amounts = IUniswapV2Router01(_router).swapExactTokensForTokens(
                amounts[1],
                0,
                path,
                address(this),
                block.timestamp + 15 // on sushi?
            );
        }

        //send converted to caller
        IERC20(tokenOut).safeTransfer(msg.sender, amounts[1]);
        return amounts[1]; //returns output token amount
    }

    function quoteOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external view override returns (uint256) {
        address[] memory path = new address[](2);
        uint256[] memory amounts = new uint256[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        if (tokenIn != address(TNGBL) && tokenOut != address(TNGBL)) {
            bytes memory tokenized = abi.encodePacked(tokenIn, tokenOut);
            address _router = routers[tokenized];
            require(address(0) != _router, "router 0 qo");

            amounts = IUniswapV2Router01(_router).getAmountsOut(amountIn, path);
        } else {
            path[1] = address(DAI);
            bytes memory tokenized = abi.encodePacked(tokenIn, address(DAI));
            address _router = routers[tokenized];
            require(address(0) != _router, "router 0 lo");

            amounts = IUniswapV2Router01(_router).getAmountsOut(amountIn, path);

            path[0] = address(DAI);
            path[1] = tokenOut;
            //set for new
            tokenized = abi.encodePacked(address(DAI), tokenOut);
            _router = routers[tokenized];
            require(address(0) != _router, "router 0 bo");

            amounts = IUniswapV2Router01(_router).getAmountsOut(
                amounts[1],
                path
            );
        }
        return amounts[1];
    }
}
