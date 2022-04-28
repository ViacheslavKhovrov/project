// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

interface UniswapV2Router02 {
    function getAmountsOut(uint amountIn, address[] memory path) external view returns (uint[] memory amounts);
}