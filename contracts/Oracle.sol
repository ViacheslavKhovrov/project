// SPDX-License-Identifier: MIT
pragma solidity 0.7.6;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import "@uniswap/v3-periphery/contracts/libraries/OracleLibrary.sol";
import "@uniswap/v3-core/contracts/libraries/FixedPoint96.sol";

library UniWaifuV3Oracle {

    IUniswapV3Factory constant uniswapV3Factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    uint24 constant FEE_MIN = 500;
    uint24 constant FEE_MEDIUM = 3000;
    uint24 constant FEE_MAX = 10000;

    function getPrice(address token, address refCurrency) internal view returns(uint256) {
        IUniswapV3Pool pool = _getPool(token, refCurrency);
        
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = 1800;
        secondsAgos[1] = 0;
        (int56[] memory tickCumulatives, ) = pool.observe(secondsAgos);
        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];
        int24 arithmeticMeanTick = int24(tickCumulativesDelta / 1800);
        uint160 sqrtPriceX96 = TickMath.getSqrtRatioAtTick(arithmeticMeanTick);

        return FullMath.mulDiv(sqrtPriceX96, sqrtPriceX96, FixedPoint96.Q96);
    }

    function _getPool(address token, address refCurrency) internal view returns (IUniswapV3Pool) {
        uint128 maxLiquidity;
        uint24 fee = FEE_MIN;
        address pool;
        for(uint256 i = 0; i < 3; i++) {
            uint24 tmpFee = i == 0 ? FEE_MIN : i == 1 ? FEE_MEDIUM : FEE_MAX;

            pool = uniswapV3Factory.getPool(token, refCurrency, tmpFee);

            if(pool == address(0)) {
                continue;
            }

            uint32 maxTWAPInterval = OracleLibrary.getOldestObservationSecondsAgo(pool);
            (, uint128 harmonicMeanLiquidity) = OracleLibrary.consult(pool, maxTWAPInterval);
            if(harmonicMeanLiquidity > maxLiquidity) {
                maxLiquidity = harmonicMeanLiquidity;
                fee = tmpFee;
            }
        }

        pool = uniswapV3Factory.getPool(token, refCurrency, fee);

        return IUniswapV3Pool(pool);
    }
}