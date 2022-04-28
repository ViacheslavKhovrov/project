// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

interface compound {
    function getAllMarkets() external view returns (address[] memory);
    function markets(address _market) external view returns (bool isListed, uint256 collateralFactorMantissa, bool isComped);
}