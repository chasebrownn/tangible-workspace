// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import "@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol";
import "../interfaces/ITNGBLV3Oracle.sol";

contract UniV3Wrapper is AccessControl {
    using SafeERC20 for IERC20;
    bytes32 constant ROUTER_POLICY_ROLE = bytes32(keccak256("ROUTER_POLICY"));

    ISwapRouter public immutable router =
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    ITNGBLV3Oracle public immutable oracle;
    //=    ITNGBLV3Oracle(0x92719c52841f84a39a9a863315Af8F187a42d6bc); // polygon
    //=    ITNGBLV3Oracle(0x575f82472842d025Ae639351fd4Fa1Ef737D907d); // mumbai

    mapping(bytes => uint24) public fees;
    uint24 public defaultFee = 3000;
    uint24 public hundredPercentFee = 1000000;

    constructor(address _oracle) {
        oracle = ITNGBLV3Oracle(_oracle);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ROUTER_POLICY_ROLE, msg.sender);
    }

    function addFeeForTokens(
        address tokenInAddress,
        address tokenOutAddress,
        uint24 fee
    ) external onlyRole(ROUTER_POLICY_ROLE) {
        bytes memory tokenized = abi.encodePacked(
            tokenInAddress,
            tokenOutAddress
        );
        bytes memory tokenizedReverse = abi.encodePacked(
            tokenOutAddress,
            tokenInAddress
        );
        fees[tokenized] = fee;
        fees[tokenizedReverse] = fee;
    }

    function getAmountsIn(uint256 amountOut, address[] calldata path)
        external
        view
        returns (uint256[] memory amountsIn)
    {
        require(path.length == 2, "invalid path length");
        bytes memory tokenized = abi.encodePacked(path[0], path[1]);

        uint256 oraclePrice = oracle.consult(
            path[0],
            uint128(amountOut),
            path[1],
            1
        );
        uint24 fee = fees[tokenized] != 0 ? fees[tokenized] : defaultFee;

        oraclePrice =
            (oraclePrice * uint256(hundredPercentFee + fee)) /
            uint256(hundredPercentFee);

        amountsIn = new uint256[](2);
        amountsIn[0] = oraclePrice;
        amountsIn[1] = amountOut;
    }

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amountsOut)
    {
        require(path.length == 2, "invalid path length");
        bytes memory tokenized = abi.encodePacked(path[0], path[1]);

        uint256 oraclePrice = oracle.consult(
            path[0],
            uint128(amountIn),
            path[1],
            1
        );
        uint24 fee = fees[tokenized] != 0 ? fees[tokenized] : defaultFee;

        oraclePrice =
            (oraclePrice * uint256(hundredPercentFee - fee)) /
            uint256(hundredPercentFee);

        amountsOut = new uint256[](2);
        amountsOut[0] = amountIn;
        amountsOut[1] = oraclePrice;
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256, //amountOutMin,
        address[] calldata path,
        address, //to,
        uint256 //deadline
    ) external returns (uint256[] memory amountsOut) {
        require(path.length == 2, "invalid path length");
        bytes memory tokenized = abi.encodePacked(path[0], path[1]);

        // take the input token
        IERC20(path[0]).safeTransferFrom(msg.sender, address(this), amountIn);
        //approve the exchange
        IERC20(path[0]).approve(address(router), amountIn);

        uint24 fee = fees[tokenized] != 0 ? fees[tokenized] : defaultFee;

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams(
                path[0],
                path[1],
                fee,
                address(this),
                block.timestamp + 15,
                amountIn,
                0,
                0
            );

        amountsOut = new uint256[](2);
        amountsOut[0] = amountIn;
        amountsOut[1] = router.exactInputSingle(params);
        IERC20(path[1]).safeTransfer(msg.sender, amountsOut[1]);
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address, //to,
        uint256 //deadline
    ) external returns (uint256[] memory amountsOut) {
        require(path.length == 2, "invalid path length");
        bytes memory tokenized = abi.encodePacked(path[0], path[1]);
        // take the input token
        IERC20(path[0]).safeTransferFrom(
            msg.sender,
            address(this),
            amountInMax
        );
        //approve the exchange
        IERC20(path[0]).approve(address(router), amountInMax);

        uint24 fee = fees[tokenized] != 0 ? fees[tokenized] : defaultFee;

        ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter
            .ExactOutputSingleParams(
                path[0],
                path[1],
                fee,
                address(this),
                block.timestamp + 15,
                amountOut,
                amountInMax,
                0
            );

        amountsOut = new uint256[](2);
        amountsOut[0] = amountInMax;
        amountsOut[1] = ISwapRouter(router).exactOutputSingle(params);
        IERC20(path[1]).safeTransfer(msg.sender, amountsOut[1]);
    }
}
