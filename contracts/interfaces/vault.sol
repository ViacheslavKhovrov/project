// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

interface vault {
    function initialCollateralRatio(address _token) external view returns (uint);
}