# WaifuToken Smart Contract Audit

## Introduction

### Project overview
WaifuToken (WUSD) is an decentralized algorithmic stablecoin. The project allows various types of crypto assets to be used as collateral to create WaifuTokens. A similar project is the Dai stablecoin. The WaifuToken is pegged to the value of Dai. The users can provide collateral tokens that are listed on lending protocols Aave V2, Iron Bank, Unit Protocol. The contract sets the LTV of an asset as the best LTV from these protocols.

### Scope of the Audit
The scope of the audit includes the following smart contracts at:
- https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol
- https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Oracle.sol
- https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/interfaces/UniswapV2Router02.sol
- https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/interfaces/aave.sol
- https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/interfaces/cMarket.sol
- https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/interfaces/compound.sol
- https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/interfaces/controller.sol
- https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/interfaces/vault.sol

The audited commit identifier is `2334407900952c69c8fed7ac4c910820637a6f0c`

## Security Assessment Methodology

A group of auditors independently verified the code.

Stages of the audit were as follows:

* Project architecture review
* Checking the code against the checklist of known vulnerabilities
* Checking the code for compliance with the desired security model
* Consolidation of interim auditor reports into general one
* Bug fixing & re-check
* Preparation of the final audit report

## Findings Severity breakdown

### Classification of Issues

* CRITICAL: Bugs leading to Ether or token theft, fund access locking or any other loss of Ether/tokens to be transferred to any party (for example, dividends). 
* MAJOR: Bugs that can trigger a contract failure. Further recovery is possible only by manual modification of the contract state or replacement. 
* WARNINGS: Bugs that can break the intended contract logic or expose it to DoS attacks. 
* COMMENTS: Other issues and recommendations reported to/ acknowledged by the team.

Based on the feedback received from the Customer's team regarding the list of findings discovered by the Contractor, they are assigned the following statuses:

### Findings' breakdown status

* FIXED: Recommended fixes have been made to the project code and no longer affect its security.
* ACKNOWLEDGED: The project team is aware of this finding. Recommendations for this finding are planned to be resolved in the future. This finding does not affect the overall safety of the project.
* NO ISSUE: Finding does not affect the overall safety of the project and does not violate the logic of its work
* NEW: Waiting for project team's feedback on the finding discovered

## Report

### CRITICAL

#### 1. Incorrect logic when burning and minting tokens
##### Description
The `_mintDai()` function defined at line https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L274 is for minting WaifuTokens to address `recipient`. But the logic in the function transfers `DAI` from `recipient` and mints to `msg.sender`. If the contract has approval to transfer `DAI` from `recipient`, the attacker can front run and mint WaifuTokens to themselves.

The `_burnDai()` function defined at line https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L281 The function burns WaifuTokens from `recipient` and transfers `DAI` to `msg.sender`, instead of the other way around. An attacker can burn WaifuTokens of any user and get `DAI`.

##### Recommendation
We recommend to swap `msg.sender` and `recipient` in these functions to fix the logic.

##### Status
**NEW**

#### 2. Integer underflow leading to loss of funds
##### Description
- In the function `_burn()`, collateral value can underflow at line https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L310 An attacker can call `burn()` without burning any WaifuTokens and `amount` equal to contract's balance to withdraw all the funds of the contract in the asset. The `require` on line https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L313 will pass since `collateral[msg.sender][asset]` will underflow.

- In the function `getSoftRepayment()` https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L58 if `_debt` is smaller than `value`, there will be underflow and the function returns `_debt`. An attacker can liquidate any position even if it's safe and earn profit.

##### Recommendation
We recommend to use a `SafeMath` library.

##### Status
**NEW**

#### 3. Incorrect price oracle
##### Description
The function `getPrice()` at the line https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Oracle.sol#L16 returns price multiplied by `2**96`. The function `TickMath.getSqrtRatioAtTick()` at the line https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Oracle.sol#L25 calculates `sqrt(1.0001**tick) * 2**96` ([Uniswap V3 docs](https://docs.uniswap.org/protocol/reference/core/libraries/TickMath)). 
Thus, at line https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Oracle.sol#L27 the function returns `1.0001**tick * 2**96`.
This is not handled in `getPrice()` or `lookup()` functions.

The actual price is equal to `1.0001**tick` ([Uniswap V3 docs](https://docs.uniswap.org/protocol/concepts/V3-overview/oracle#deriving-price-from-a-tick)).

The attack vector:
1. The attacker mints WaifuTokens using `mint()` depositing the collateral
2. The attacker withdraws the collateral using `burn()` but without burning WaifuTokens and leaving just enough collateral such that `require` passes at line https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L313

Also it can mislead users about asset prices if they use `lookup()` functions.

##### Recommendation
We suggest to fix the implementation of the price oracle and `lookup` functions that use it. For example, Uniswap V3 Oracle library function `getQuoteAtTick()`: https://github.com/Uniswap/v3-periphery/blob/22a7ead071fff53f00d9ddc13434f285f4ed5c7d/contracts/libraries/OracleLibrary.sol#L49 
`USDT` has 6 decimals, so it is not precise for small amounts of tokens with higher decimals. The difference in decimals also has to be considered when calculating the price.

##### Status
**NEW**

#### 4. Unsafe transfer of ERC20 tokens
##### Description
There are no checks for return values of `transfer`/`transferFrom` at the lines 
- https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L275
- https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L283
- https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L171
- https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L290
- https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L316

The users also provide address of a token for `mint()`/`burn()`. It is unsafe since some tokens do not revert on failure, but instead return `false` (e.g. `ZRX`). An attacker can mint WaifuTokens without actually transferring collateral.

1. The attacker adds liquidity to `ZRX`/`USDT` pool on Uniswap V3.
2. The attacker calls `mint()`, `transferFrom()` fails but the execution continues, so attacker can send any `amount`.
3. Since there is a pool with liquidity, the `require` passes on line https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L299
4. Since `ZRX` is listed on Aave V2 with LTV `65`, the `require` passes on line https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L300
5. The attacker gets minted WaifuTokens.

Some tokens do not return a bool (e.g. `BNB`).

##### Recommendation
We recommend to use safe transfer options. For example, `SafeERC20`, or Compound's [`doTransferIn()`](https://github.com/compound-finance/compound-protocol/blob/6548ec3e8c733d18cd4bdb2c21197f666f828f35/contracts/CErc20.sol#L156), [`doTransferOut()`](https://github.com/compound-finance/compound-protocol/blob/6548ec3e8c733d18cd4bdb2c21197f666f828f35/contracts/CErc20.sol#L192). Consider also creating a whitelist of allowed tokens to be used as collateral.

##### Status
**NEW**

### MAJOR

#### 1. Incorrect logic for `_liquidity()` function (DoS)
##### Description
The function `_liquidity()` at the line https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L330 returns a cached liquidity of token. A malicious user can deny mint of WaifuTokens. 

First scenario: 
1. The token is new to the contract, so `_liquidityCache[token] = 0` and `liquidities[token] = 0`. 
2. The attacker uses `mint()` function to send 1 wei of token as collateral without minting WaifuTokens. 
3. `_liquidity()` function calls `_liquidityV()`.
4. Since `_liquidityCache[token] = 0`, the function `_liquidityV()` returns `_updated = true`.
5. Then `liquidities[token]` is overwritten with a small value `_val`.
6. Other users who want to mint WaifuTokens will only be able to mint up to that cached value `liquidities[token]`, since `require` will fail at line https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L299

Second scenario:
1. The token is new to the contract, so `_liquidityCache[token] = 0` and `liquidities[token] = 0`.
2. The user wants to provide collateral of asset that is significantly bigger than `_minLiquidity`.
3. The code will enter this condition https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L210-L214
4. The `_liq` variable will be set to `472500e18`.
5. They will not be able to mint more than this amount.

##### Recommendation
We suggest to fix this logic by changing how liquidity of an asset is calculated.

##### Status
**NEW**

#### 2. Incorrect minting for tokens with fees
##### Description
Some tokens have fees on transfer. When using `transferFrom()`, amount received might be smaller than the argument `amount`. At the lines https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L293-L294 the collateral variables add `amount` sent which will misrepresent the actual balance of the contract. The user might mint more than they are supposed to.

##### Recommendation
We recommend to use balance difference to count amount of `asset` received.

##### Status
**NEW**

#### 3. Using tokens with a blocklist
##### Description
At the lines: https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L290 https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L316 Some tokens have a blocklist (e.g. `USDC`). If they are used as collateral and WaifuToken is blocked off-chain, the users will not be able to receive their assets from the contract. 

##### Recommendation
Consider creating a whitelist of allowed tokens to be used as collateral.

##### Status
**NEW**

### WARNINGS

#### 1. Integer underflow for `dai`
##### Description
In the function `burnDai()` an attacker can underflow the `dai` variable at line https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L284 Let's say the value of `dai` is 0 after contract deployment.

The attacker can follow these steps:
1. mint WaifuTokens using `mint()` function using an ERC20 token
2. transfer `DAI` to WaifuToken contract's address, the `dai` variable will not be updated 
3. burn 1 WaifuToken using `burnDai()` function

Then, the `dai` variable will overflow and be max `uint256`. 

The variable is only used to keep track of balance of `DAI` of the contract, so theft of funds should not be possible with this method. But since the variable is public it can mislead users about the contract's balance. For example, when they try to use the `burnDai()` function, if the `amount` is bigger than the contract's actual balance, the transaction will fail.

##### Recommendation
Consider removing the variable and/or add a method that would get the contract's balance using `balanceOf()` from `DAI`.

##### Status
**NEW**

#### 2. No check for zero address of function input arguments
##### Description
In the following functions there are no checks for zero address. Not doing so can lead to unintended behaviour and possible loss of funds.
- https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Oracle.sol#L16
- https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L250
- https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L199
- https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L95
- https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L107
- https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L288
- https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L305
- https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L152

##### Recommendation
We recommend to add checks for addresses to not equal address zero.

##### Status
**NEW**

#### 3. Possible manipulation of contract parameters by the miner
##### Description
The `block.timestamp` is used at the following lines
- https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L200
- https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L251
- https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L324
- https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L336

The value of `block.timestamp` is set by the miner. They can manipulate it to set the liquidity of a token or to liquidate unsafe positions after updating LTV of a token.

##### Recommendation
We recommend that you avoid using `block.timestamp`.

##### Status
**NEW**

#### 4. No require of success in search of pool
##### Description
In the function `_getPool()` https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Oracle.sol#L30 if a pool for `token` and `refCurrency` is not found, then the function returns `pool` with address zero.

##### Recommendation
We recommend to add a check if a pool was found.

##### Status
**NEW**

#### 5. Possible price manipulation
##### Description
At the lines https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L208 https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L226 the contract uses the instant price of a pair on Sushiswap to get the amount of liquidity. The attacker can change that price to make it seem like the contract has more liquidity in an asset than it actually does.

##### Recommendation
We recommend to not use instant price oracles, but instead use TWAP and/or off-chain oracles.

##### Status
**NEW**

#### 6. Possible miscalculation of `arithmeticMeanTick`
##### Description
After calculating `arithmeticMeanTick` at the line https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Oracle.sol#L24 the value is not rounded down to negative infinity like it is done in Uniswap's implementation: https://github.com/Uniswap/v3-periphery/blob/22a7ead071fff53f00d9ddc13434f285f4ed5c7d/contracts/libraries/OracleLibrary.sol#L36. In some cases, this might result in a slightly wrong `arithmeticMeanTick` value.

##### Recommendation
We suggest to use audited and well tested code.

##### Status
**NEW**

#### 7. Possible loss of precision
##### Description
There is a possible loss of precision when calculating `lookup()` functions due to division before multiplication at the lines:
https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L76
https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L80
https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L271

For example, if `amount = 1`, then the return value would be `0`.

##### Recommendation
We suggest to multiply by `_rate` before division.

##### Status
**NEW**

#### 8. Reentry causing events misordering
##### Description
Due to reentrancy, the events will be shown in an incorrect order at the lines:
https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L172
https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L278
https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L285
https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L302
https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L318

This might lead to issues for third parties listening to events.

##### Recommendation
Apply the [Checks-Effects-Interactions pattern](https://docs.soliditylang.org/en/v0.4.21/security-considerations.html#re-entrancy) or use `nonReentrant` modifier.

##### Status
**NEW**

### COMMENTS

#### 1. Lack of docs and function name clarity
##### Description
Files: https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol
https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Oracle.sol.

Some of the functions and their logic are not fully clear from the code.
For example: https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L58
https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L74
https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L79

##### Recommendation
Add comprehensive docstrings and change some function names to better describe their purpose.

##### Status
**NEW**

#### 2. Constant and interface names do not follow convention
##### Description
Constant names do not follow Solidity naming conventions when they are declared at the following lines https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L24-L40 https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Oracle.sol#L11

The interface names should be in `CapWords`:
- https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/interfaces/aave.sol#L5
- https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/interfaces/cMarket.sol#L4
- https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/interfaces/compound.sol#L4
- https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/interfaces/controller.sol#L4
- https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/interfaces/vault.sol#L4

##### Recommendation
The variable and contract names should follow the [Solidity Style Guide naming convention](https://docs.soliditylang.org/en/v0.8.13/style-guide.html#naming-conventions).

##### Status
**NEW**

#### 3. Unclear addresses
##### Description
At the line https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L190, the addresses are unclear.

##### Recommendation
We recommend to declare the addresses as constant variables with descriptive names.

##### Status
**NEW**

#### 4. Missing error messages
##### Description
There are missing error messages at the lines: 
- https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L159
- https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L169
- https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L299
- https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L300
- https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L313

The user will not be able to know why a transaction failed.

##### Recommendation
We recommend to add error messages.

##### Status
**NEW**

#### 5. Argument shadows a function 
##### Description
At the line https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L152 argument `max` shadows a function named `max()` https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L183

##### Recommendation
We recommend to remove the ambiguities. Always check for compiler warnings as they can flag the issue within a single contract.

##### Status
**NEW**

#### 6. Gas optimization to find maximum
##### Description
At the lines https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L252-L258 it is possible to optimize gas usage to find `_max`.

##### Recommendation
We suggest to reduce the number of operations to optimize gas usage. For example, a better solution (but not necessarily the best):
```solidity
uint _max = _totalValueIB(token);
uint a = _getTotalValueAaveV2(token);
uint b = _getTotalValueUnit(token);
if (a > _max) {
    _max = a > b ? a : b;
} else if (b > _max) {
    _max = b;
}
```

##### Status
**NEW**

#### 7. No checks for zero input arguments
##### Description
For the functions `_mint()` https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L288 and `_burn()` https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L305 the input arguments `amount`, `minted`, `burned` can be zero. For example, user might want to deposit collateral without minting, mint without depositing additional collateral, burn without removing collateral, or withdraw collateral without burning.

Adding checks for these arguments can reduce gas usage by decreasing the number of changes to state variables and function calls.

##### Recommendation
We suggest to add these checks.

##### Status
**NEW**

#### 8. Unnecessary variable
##### Description
The variable `_rate` is unnecessary at the lines https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L75 https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L270

##### Recommendation
Consider removing it and changing to 
```solidity
return asset.getPrice(_currency) * (amount * _totalValue(asset) / _BPS);
```

##### Status
**NEW**

#### 9. `compound` interface unnecessary
##### Description
The `compound` interface is only used at the line https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L188 to get all markets from the Iron Bank protocol https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L237 But `controller` interface also has the  `getAllMarkets()` function with the same signature.

##### Recommendation
Consider replacing `compound` with `controller` interface.

##### Status
**NEW**

#### 10. The visibility is not set
##### Description
The visibility is not set for variables `_totalValueCache` and `_liquidityCache`: https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L49 https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L52

##### Recommendation
We recommend to set the visibility.

##### Status
**NEW**

#### 11. No events for changes in cached storage variables
##### Description
At the lines: https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L323-L326 https://github.com/ViacheslavKhovrov/project/blob/2334407900952c69c8fed7ac4c910820637a6f0c/contracts/Waifu.sol#L335-L338
There are no events when storage variables `totalValues` and `liquidities` are changed. The users cannot know when these values change.

##### Recommendation
We recommend to add such events and emit them when the variables are changed.

##### Status
**NEW**

## Results

### Findings list

Level | Amount
--- | ---
CRITICAL | 4
MAJOR | 3
WARNING | 8
COMMENT | 11

### Conclusion
During the audit four critical issues were found that could lead to the theft of assets. Three major issues were identified as they could lead to undesired behavior. Also, several issues were marked as warnings and comments.
