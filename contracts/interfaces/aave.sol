// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

interface aave {
    struct ReserveConfigurationMap {
        uint256 data;
    }
    function getReserveConfiguration(address _market) external view returns (uint, uint, uint, bool);
    function getConfiguration(address _market) external view returns (ReserveConfigurationMap memory);
}