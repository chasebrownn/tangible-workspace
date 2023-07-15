// SPDX-License-Identifier: AGPL-3.0-or-later
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "@openzeppelin/contracts/access/AccessControl.sol";

interface CurveExchanges {
    function underlying_coins(uint256 i) external returns (address);

    // like getAmountsOut
    function get_exchange_amount(
        address pool,
        address inputToken,
        address outputToken,
        uint256 amountIn
    ) external view returns (uint256 amountOut);

    // like getAmountsIn
    function get_input_amount(
        address pool,
        address inputToken,
        address outputToken,
        uint256 amountOut
    ) external view returns (uint256 amountIn);

    function exchange(
        address pool,
        address inputToken,
        address outputToken,
        uint256 amountIn,
        uint256 expectedOut
    ) external returns (uint256 amountReceived);
}

interface CurveAddressProvider {
    function get_address(uint256 id) external view returns (address addr);
}

interface CurveRegistry {
    function find_pool_for_coins(address fromToken, address toToken)
        external
        view
        returns (address pool);

    function get_coin_indices(
        address pool,
        address fromToken,
        address toToken
    )
        external
        view
        returns (
            int128 fromIndex,
            int128 toIndex,
            bool metaPool
        );
}

interface ICurveInputWrapper {
    // like getAmountsIn
    function get_input_amount(
        address pool,
        address inputToken,
        address outputToken,
        uint256 amountOut
    ) external view returns (uint256 amountIn);
}

interface ICurvePool {
    function get_dy_underlying(
        int128 i,
        int128 j,
        uint256 dx
    ) external view returns (uint256 amountOut);
}

interface ICurveZapper {
    function exchange_underlying(
        address pool,
        int128 i,
        int128 j,
        uint256 dx,
        uint256 min_dy
    ) external returns (uint256);
}

contract CurveWrapper is AccessControl {
    using SafeERC20 for IERC20;
    bytes32 constant ROUTER_POLICY_ROLE = bytes32(keccak256("ROUTER_POLICY"));
    struct Indices {
        int128 inIndice;
        int128 outIndice;
    }

    struct PoolData {
        address pool;
        bool isMeta;
    }

    mapping(bytes => PoolData) public pools;
    mapping(bytes => Indices) public indices;

    CurveAddressProvider public immutable curveAddressProvider =
        CurveAddressProvider(0x0000000022D53366457F9d5E68Ec105046FC4383);

    CurveRegistry public immutable curveRegistry =
        CurveRegistry(0x094d12e5b541784701FD8d65F11fc0598FBC6332);
    ICurveInputWrapper public immutable curveInputWrapper;
    ICurveZapper public immutable curveZaper =
        ICurveZapper(0x5ab5C56B9db92Ba45a0B46a207286cD83C15C939);

    constructor(address _curveInputWrapper) {
        curveInputWrapper = ICurveInputWrapper(_curveInputWrapper);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ROUTER_POLICY_ROLE, msg.sender);
    }

    function addPoolForTokens(
        address pool,
        address tokenInAddress,
        address tokenOutAddress,
        int128 indiceIn,
        int128 indiceOut,
        bool isMeta
    ) external onlyRole(ROUTER_POLICY_ROLE) {
        bytes memory tokenized = abi.encodePacked(
            tokenInAddress,
            tokenOutAddress
        );
        bytes memory tokenizedReverse = abi.encodePacked(
            tokenOutAddress,
            tokenInAddress
        );
        pools[tokenized].pool = pool;
        pools[tokenized].isMeta = isMeta;
        pools[tokenizedReverse].pool = pool;
        pools[tokenizedReverse].isMeta = isMeta;

        indices[tokenized].inIndice = indiceIn;
        indices[tokenized].outIndice = indiceOut;
        indices[tokenizedReverse].inIndice = indiceOut;
        indices[tokenizedReverse].outIndice = indiceIn;
    }

    function getAmountsIn(uint256 amountOut, address[] calldata path)
        external
        view
        returns (uint256[] memory amountsIn)
    {
        require(path.length == 2, "invalid path length");
        bytes memory tokenized = abi.encodePacked(path[0], path[1]);
        address pool = pools[tokenized].pool; // curveRegistry.find_pool_for_coins(path[0], path[1]);
        require(pool != address(0), "pool missing");

        amountsIn = new uint256[](2);
        if (!pools[tokenized].isMeta) {
            amountsIn[0] = curveInputWrapper.get_input_amount(
                pool,
                path[0],
                path[1],
                amountOut
            );
        } else {
            revert("doesn't work for non meta");
        }
        amountsIn[1] = amountOut;
    }

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amountsOut)
    {
        require(path.length == 2, "invalid path length");
        bytes memory tokenized = abi.encodePacked(path[0], path[1]);
        address pool = pools[tokenized].pool; // curveRegistry.find_pool_for_coins(path[0], path[1]);
        require(pool != address(0), "pool missing");

        amountsOut = new uint256[](2);
        amountsOut[0] = amountIn;
        CurveExchanges curveExchange = CurveExchanges(
            curveAddressProvider.get_address(2)
        );
        if (!pools[tokenized].isMeta) {
            amountsOut[1] = curveExchange.get_exchange_amount(
                pool,
                path[0],
                path[1],
                amountIn
            );
        } else {
            int128 i = indices[tokenized].inIndice;
            int128 j = indices[tokenized].outIndice;
            amountsOut[1] = ICurvePool(pool).get_dy_underlying(i, j, amountIn);
        }
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address, //to,
        uint256 //deadline
    ) external returns (uint256[] memory amountsOut) {
        require(path.length == 2, "invalid path length");
        bytes memory tokenized = abi.encodePacked(path[0], path[1]);
        //address pool = pools[tokenized].pool; // curveRegistry.find_pool_for_coins(path[0], path[1]);
        require(pools[tokenized].pool != address(0), "pool missing");
        // take the input token
        IERC20(path[0]).safeTransferFrom(msg.sender, address(this), amountIn);

        amountsOut = new uint256[](2);
        amountsOut[0] = amountIn;
        CurveExchanges curveExchange = CurveExchanges(
            curveAddressProvider.get_address(2)
        );
        if (!pools[tokenized].isMeta) {
            //approve the exchange
            IERC20(path[0]).approve(address(curveExchange), amountIn);
            amountsOut[1] = curveExchange.exchange(
                pools[tokenized].pool,
                path[0],
                path[1],
                amountIn,
                amountOutMin
            );
        } else {
            //approve the exchange
            IERC20(path[0]).approve(address(curveZaper), amountIn);
            int128 i = indices[tokenized].inIndice;
            int128 j = indices[tokenized].outIndice;
            amountsOut[1] = curveZaper.exchange_underlying(
                pools[tokenized].pool,
                i,
                j,
                amountIn,
                1
            );
        }
        IERC20(path[1]).safeTransfer(msg.sender, amountsOut[1]);
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountIn,
        address[] calldata path,
        address, //to,
        uint256 //deadline
    ) external returns (uint256[] memory amountsOut) {
        require(path.length == 2, "invalid path length");
        bytes memory tokenized = abi.encodePacked(path[0], path[1]);
        require(pools[tokenized].pool != address(0), "pool missing");
        // take the input token
        IERC20(path[0]).safeTransferFrom(msg.sender, address(this), amountIn);

        amountsOut = new uint256[](2);
        amountsOut[0] = amountIn;
        if (!pools[tokenized].isMeta) {
            //approve the exchange
            CurveExchanges curveExchange = CurveExchanges(
                curveAddressProvider.get_address(2)
            );
            IERC20(path[0]).approve(address(curveExchange), amountIn);
            amountsOut[1] = curveExchange.exchange(
                pools[tokenized].pool,
                path[0],
                path[1],
                amountIn,
                amountOut
            );
        } else {
            //approve the exchange
            IERC20(path[0]).approve(address(curveZaper), amountIn);
            int128 i = indices[tokenized].inIndice;
            int128 j = indices[tokenized].outIndice;
            amountsOut[1] = curveZaper.exchange_underlying(
                pools[tokenized].pool,
                i,
                j,
                amountIn,
                amountOut
            );
        }
        IERC20(path[1]).safeTransfer(msg.sender, amountsOut[1]);
    }
}
