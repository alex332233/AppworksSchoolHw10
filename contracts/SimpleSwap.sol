// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { ISimpleSwap } from "./interface/ISimpleSwap.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";

contract SimpleSwap is ISimpleSwap, ERC20 {
    // Implement core logic here
    ERC20 public tokenA;
    ERC20 public tokenB;

    constructor(address _tokenA, address _tokenB) ERC20("SimpleSwap", "SSW") {
        tokenA = ERC20(_tokenA);
        tokenB = ERC20(_tokenB);
        // Check if _tokenA, _tokenB is a contract
        uint256 sizeA;
        uint256 sizeB;
        assembly {
            sizeA := extcodesize(_tokenA)
            sizeB := extcodesize(_tokenB)
        }
        require(sizeA > 0, "SimpleSwap: TOKENA_IS_NOT_CONTRACT");
        require(sizeB > 0, "SimpleSwap: TOKENB_IS_NOT_CONTRACT");
        require(_tokenA != _tokenB, "SimpleSwap: TOKENA_TOKENB_IDENTICAL_ADDRESS");
        // 比較tokenA and tokenB大小，小的為tokenA，大的為tokenB
        address smallerAddress = _tokenA < _tokenB ? _tokenA : _tokenB;
        address largerAddress = _tokenA < _tokenB ? _tokenB : _tokenA;

        tokenA = ERC20(smallerAddress);
        tokenB = ERC20(largerAddress);
    }

    function swap(address tokenIn, address tokenOut, uint256 amountIn) external returns (uint256 amountOut) {
        // test_revert_when_tokenIn_is_not_tokenA_or_tokenB
        require(tokenIn == getTokenA() || tokenIn == getTokenB(), "SimpleSwap: INVALID_TOKEN_IN");
        require(tokenIn == address(tokenA) || tokenIn == address(tokenB), "SimpleSwap: INVALID_TOKEN_IN");
        // test_revert_when_tokenOut_is_not_tokenA_or_tokenB
        require(tokenOut == getTokenA() || tokenOut == getTokenB(), "SimpleSwap: INVALID_TOKEN_OUT");
        require(tokenOut == address(tokenA) || tokenOut == address(tokenB), "SimpleSwap: INVALID_TOKEN_OUT");
        // test_revert_when_tokenIn_is_the_same_as_tokenOut
        require(tokenIn != tokenOut, "SimpleSwap: IDENTICAL_ADDRESS");
        // test_revert_when_amountIn_is_zero
        require(amountIn > 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");

        // test_swap_from_tokenA_to_tokenB
        uint256 reserveA;
        uint256 reserveB;
        (reserveA, reserveB) = getReserves();
        // K = reserveIn * reserveOut = (reserveIn + amountIn) * (reserveOut - amountOut)
        // amountOut = amountIn * reserveOut / (reserveIn + amountIn)

        // add token to this contract
        // test_swap_from_tokenA_to_tokenB
        if (tokenIn == address(tokenA)) {
            tokenA.transferFrom(msg.sender, address(this), amountIn);
            amountOut = (amountIn * reserveB) / (reserveA + amountIn);
            tokenB.transfer(msg.sender, amountOut);
        }
        // test_swap_from_tokenB_to_tokenA
        else if (tokenIn == address(tokenB)) {
            tokenB.transferFrom(msg.sender, address(this), amountIn);
            amountOut = (amountIn * reserveA) / (reserveB + amountIn);
            tokenA.transfer(msg.sender, amountOut);
        }

        // Emitting the Swap event
        emit Swap(msg.sender, tokenIn, tokenOut, amountIn, amountOut);

        return amountOut;
    }

    function addLiquidity(
        uint256 amountAIn,
        uint256 amountBIn
    ) external returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        require(amountAIn > 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");
        require(amountBIn > 0, "SimpleSwap: INSUFFICIENT_INPUT_AMOUNT");

        amountA = amountAIn;
        amountB = amountBIn;

        uint256 reserveA;
        uint256 reserveB;
        (reserveA, reserveB) = getReserves();

        // 如果為第一次添加流動性
        if (reserveA == 0 || reserveB == 0) {
            tokenA.transferFrom(msg.sender, address(this), amountA);
            tokenB.transferFrom(msg.sender, address(this), amountB);
            liquidity = Math.sqrt(amountA * amountB);
        } else {
            // uint256 proportionReserve = reserveA / reserveB;
            // uint256 proportionAmount = amountA / amountB;
            // 先除會造成小數點被捨去，所以移項改成乘
            uint256 rAaB = reserveA * amountB;
            uint256 aRbB = amountA * reserveB;

            // test_addLiquidity_when_tokenA_proportion_is_the_same_as_tokenB_proportion
            if (rAaB == aRbB) {
                tokenA.transferFrom(msg.sender, address(this), amountA);
                tokenB.transferFrom(msg.sender, address(this), amountB);
            }
            // test_addLiquidity_when_tokenA_proportion_is_greaterThan_tokenB_proportion
            else if (rAaB > aRbB) {
                amountB = (amountA * reserveB) / reserveA;
                tokenA.transferFrom(msg.sender, address(this), amountA);
                tokenB.transferFrom(msg.sender, address(this), amountB);
            }
            // test_addLiquidity_when_tokenA_proportion_is_lessThan_tokenB_proportion
            else if (rAaB < aRbB) {
                amountA = (amountB * reserveA) / reserveB;
                tokenA.transferFrom(msg.sender, address(this), amountA);
                tokenB.transferFrom(msg.sender, address(this), amountB);
            }

            uint256 liquidityA = (amountA * totalSupply()) / reserveA;
            uint256 liquidityB = (amountB * totalSupply()) / reserveB;
            liquidity = liquidityA < liquidityB ? liquidityA : liquidityB;
        }

        _mint(msg.sender, liquidity);
        // 發送AddLiquidity事件
        emit AddLiquidity(msg.sender, amountA, amountB, liquidity);

        return (amountA, amountB, liquidity);
    }

    function removeLiquidity(uint256 liquidity) external returns (uint256 amountA, uint256 amountB) {
        require(liquidity > 0, "SimpleSwap: INSUFFICIENT_LIQUIDITY_BURNED");
        uint256 reserveA;
        uint256 reserveB;
        (reserveA, reserveB) = getReserves();
        amountA = (reserveA * liquidity) / totalSupply();
        amountB = (reserveB * liquidity) / totalSupply();
        _burn(msg.sender, liquidity);
        tokenA.transfer(msg.sender, amountA);
        tokenB.transfer(msg.sender, amountB);
        emit RemoveLiquidity(msg.sender, amountA, amountB, liquidity);
        emit Transfer(address(this), address(0), liquidity);
        return (amountA, amountB);
    }

    function getReserves() public view returns (uint256 reserveA, uint256 reserveB) {
        reserveA = tokenA.balanceOf(address(this));
        reserveB = tokenB.balanceOf(address(this));
        return (reserveA, reserveB);
    }

    function getTokenA() public view returns (address) {
        return address(tokenA);
    }

    function getTokenB() public view returns (address) {
        return address(tokenB);
    }
}
