// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Oracle.sol";

import "./interfaces/cMarket.sol";
import "./interfaces/compound.sol";
import "./interfaces/controller.sol";
import "./interfaces/aave.sol";
import "./interfaces/vault.sol";
import "./interfaces/UniswapV2Router02.sol";


contract WaifuToken is ERC20 {
    using UniWaifuV3Oracle for address;

    event Mint(address indexed from, address indexed asset, address indexed to, uint amount);
    event Burn(address indexed from, address indexed asset, address indexed to, uint amount);
    event Liquidate(address indexed from, address indexed asset, address indexed to, uint amount);

    // @note COMMENT: change constant variable names to uppercase
    address constant _dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F; // dai stablecoin
    address constant _router = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F; // sushiswap router uniswapv2
    address constant _currency = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // we assume USDT is stable to USD
    
    uint256 constant _BPS = 100; // base percent scale?
    uint256 constant _LIQUIDATION_VALUE = 90; // 90 percent
    uint256 constant _CACHE_LIFESPAN = 86400; // 24 hours cache
    uint256 constant _minLiquidity = 450000e18; // minimum liquidity of token = 450k USD
    uint256 constant _liquidity_threshold = 5; // 5 percent

    // Lending protocols
    address constant _aavev2 = address(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9); // aave
    address constant _ib = address(0xAB1c342C7bf5Ec5F02ADEA1c2270670bCa144CbB); // iron bank unitroller
    address constant _unit = address(0x203153522B9EAef4aE17c6e99851EE7b2F7D312E); // unit protocol: vault manager parameters
    address constant _weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // wrapped ether
    
    uint256 constant _totalValue_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000;
    
    mapping(address => mapping(address => uint)) public debt; // debt of user => asset => amount in dai
    mapping(address => mapping(address => uint)) public collateral; // collateral of user => asset => amount in asset unit
    
    mapping(address => uint) public debts; // debts of asset => amount in dai
    mapping(address => uint) public collaterals; // collaterals of asset => amount in asset unit
    
    mapping(address => uint) public totalValues; // total values of token => amount
    mapping(address => uint) _totalValueCache; // cache of total value token => timestamp
    
    mapping(address => uint) public liquidities; // liquidities of token => amount
    mapping(address => uint) _liquidityCache; // liquidity cache of token => timestamp
        
    uint public dai; // counter for dai in this contract
    
    constructor() ERC20("Waifu USD", "WUSD") { }

    // @note consider changing to internal?
    function getSoftRepayment(uint __totalValue, uint _debt, uint value) public pure returns (uint repayment) {
        // @note unclear calculations, returns 0 if total value < 60
        // value might be more than debt leading to underflow
        if (__totalValue == 60) {
            return min((_debt - value) * 310 / _BPS, _debt);
        } else if (__totalValue == 65) {
            return min((_debt - value) * 370 / _BPS, _debt);
        } else if (__totalValue == 70) {
            return min((_debt - value) * 460 / _BPS, _debt);
        } else if (__totalValue == 75) {
            return min((_debt - value) * 610 / _BPS, _debt);
        } else if (__totalValue == 85) {
            return min((_debt - value) * 1810 / _BPS, _debt);
        } else if (__totalValue >= 90) { // if collateral ratio is bigger than 90, the repayment is the whole debt
            return _debt;
        }
    }
    
    // lookup borrowable value in USD if amount of asset was used as collateral
    function lookup(address asset, uint amount) public view returns (uint) {
        uint _rate = asset.getPrice(_currency); // get price of asset in USD
        return _rate * (amount * totalValues[asset] / _BPS); // @note gas optimization
    }
    // @note COMMENT: change function names to be more informative
    // lookup liquidation value in USD for amount of asset
    function loockupL(address asset, uint amount) public view returns (uint) {
        return asset.getPrice(_currency) * (amount * _LIQUIDATION_VALUE / _BPS);
    }

    // lookup price of asset in USD
    function lookup(address asset) external view returns (uint) {
        return asset.getPrice(_currency);
    }
    
    // returns total value of token
    function totalValue(address token) external view returns (uint val) {
        (val,) = _totalValueV(token);
    }
    // gets liquidity value of amount of token
    function liquidity(address token, uint amount) external view returns (uint val) {
        (val,) = _liquidityV(token, amount);
    }

    function getRepayment(address owner, address asset) external view returns (uint) {
        uint _nominal = collateral[owner][asset]; // get collateral of owner in asset
        // @note using public lookup instead of internal
        uint _backed = lookup(asset, _nominal); // lookup value of asset in dai
        uint _debt = debt[owner][asset]; // get debt of owner in asset
        if (_backed < _debt) { // if debt is bigger than collateral get soft repayment
            return getSoftRepayment(totalValues[asset], _debt, _backed);
        } else {
            return 0;
        }
    }
    
    // get payment of asset in nominal for liquidation
    function getPayment(address owner, address asset) external view returns (uint) {
        uint _nominal = collateral[owner][asset]; // get collateral of owner in asset
        // @note using public lookup instead of internal
        uint _backed = lookup(asset, _nominal); // lookup borrowable amount in USD using nominal amount of asset as collateral
        uint _debt = debt[owner][asset]; // get debt of owner in asset
        if (_backed < _debt) { // if debt is bigger than collateral
            uint _repayment = getSoftRepayment(totalValues[asset], _debt, _backed);
            return min(_nominal * _repayment / loockupL(asset, _nominal), _nominal);
        } else {
            return 0;
        }
    }

    // mints to msg.sender amount of WaifuTokens in exchange for dai from msg.sender
    function mintDai(uint amount) external {
        _mintDai(amount, msg.sender);
    }
    
    // mints to msg.sender amount of WaifuTokens in exchange for dai from recipient
    function mintDai(uint amount, address recipient) external {
        _mintDai(amount, recipient);
    }
    
    // burns amount of WaifuTokens from msg.sender
    // transfers amount of dai to msg.sender
    function burnDai(uint amount) external {
        _burnDai(amount, msg.sender);
    }

    // burns amount of WaifuTokens from recipient
    // transfers amount of dai to msg.sender    
    function burnDai(uint amount, address recipient) external {
        _burnDai(amount, recipient);
    }
    
    // mints to msg.sender minted amount of WaifuTokens
    // transfers from msg.sender amount of asset
    function mint(address asset, uint amount, uint minted) external {
        _mint(asset, amount, minted, msg.sender);
    }
    
    // mints to recipient minted amount of WaifuTokens
    // transfers from msg.sender amount of asset
    function mint(address asset, uint amount, uint minted, address recipient) external {
        _mint(asset, amount, minted, recipient);
    }
    
    // burns burned amount of WaifuTokens from msg.sender
    // transfers amount of asset to msg.sender
    function burn(address asset, uint amount, uint burned) external {
        _burn(asset, amount, burned, msg.sender);
    }
    
    // burns burned amount of WaifuTokens from msg.sender
    // transfers amount of asset to recipient
    function burn(address asset, uint amount, uint burned, address recipient) external {
        _burn(asset, amount, burned, recipient);
    }
    
    /** 
    * @param max max amount willing to repay in WUSD
    **/ 
    function liquidate(address owner, address asset, uint max) external {
        uint _nominal = collateral[owner][asset]; // get nominal value of collateral of owner in asset
        
        uint _backed = _lookup(asset, _nominal); // lookup backed value of asset in dai
        uint _debt = debt[owner][asset]; // get debt of owner in asset
        
        uint _repayment = getSoftRepayment(_totalValue(asset), _debt, _backed); // get repayment in Dai
        require(_repayment <= max); // @note COMMENT: add error message
        uint _payment = min(_nominal * _repayment / loockupL(asset, _nominal), _nominal); // get payment in nominal asset
        
        _burn(msg.sender, _repayment); // burn repayment amount of WaifuTokens from msg.sender
        
        debt[owner][asset] -= _repayment; // decrease debt of owner in asset by repayment
        debts[asset] -= _repayment; // decrease total debts of assets by repayment
        collateral[owner][asset] -= _payment; // decrease collateral of owner in asset by payment
        collaterals[asset] -= _payment; // decrease total collaterals of asset by payment
        
        // collateral position should be bigger than debt after liquidation
        require(_lookup(asset, collateral[owner][asset]) >= debt[owner][asset]); // @note COMMENT: add error message
        // @note no check for success, recommend using SafeERC20
        IERC20(asset).transfer(msg.sender, _payment); // transfer payment amount of asset to msg.sender
        emit Liquidate(msg.sender, asset, owner, _repayment); // emit Liquidate from msg.sender to owner of repayment amount of asset
    }

    /**
   * @dev Gets the Loan to Value of the reserve
   * @param self The reserve configuration
   * @return The loan to value
   **/
    function _getParamsMemory(aave.ReserveConfigurationMap memory self) internal pure returns (uint256) { 
        return (self.data & ~_totalValue_MASK); // gets last 2 bytes of aave.ResereConfigurationMap.data
    }

    // returns min of a and b
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    // returns max of a and b
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    // finds market on core with underlying asset == token
    function _findMarket(address _core, address _token) internal view returns (address) {
        address[] memory _list = compound(_core).getAllMarkets(); // get all markets on core CToken[]
        for (uint i = 0; i < _list.length; i++) {
            // @note COMMENT: change addresses to constant
            // if not cETH and not crETH
            if (_list[i] != address(0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5) && _list[i] != address(0xD06527D5e56A3495252A528C4987003b712860eE)) {
                if (cMarket(_list[i]).underlying() == _token) { // if token is the underlying asset of market return market
                    return _list[i];
                }
            }
        }
        return address(0x0);
    }
    
    // get liquidity value in dai
    function _liquidityV(address token, uint amount) internal view returns (uint, bool) {
        // @note block.timestamp can be manipulated by the miner
        if (block.timestamp > _liquidityCache[token]) {
            if (token == _weth) {
                return (_liqVWETH(amount), true);
            } else {
                address[] memory _path = new address[](3);
                _path[0] = token;
                _path[1] = _weth;
                _path[2] = _dai;
                uint _liq = UniswapV2Router02(_router).getAmountsOut(amount, _path)[2]; // get amount of dai if token was swapped to dai 
                uint _liquid = liquidities[token]; // get liquidity of token
                if (_liq > _liquid) {
                    _liquid += _liquid * _liquidity_threshold / _BPS; // add 5 percent
                    _liq = min(_liq, _liquid);
                    _liq = max(_liq, _minLiquidity);
                }
                return (_liq, true);
            }
        } else {
            return (liquidities[token], false);
        }
    }
    
    // get liquidity value for WETH in dai
    function _liqVWETH(uint amount) internal view returns (uint) {
        address[] memory _path = new address[](2);
        _path[0] = _weth;
        _path[1] = _dai;
        uint _liq = UniswapV2Router02(_router).getAmountsOut(amount, _path)[1];
        uint _liquid = liquidities[_weth];
        if (_liq > _liquid) {
            _liquid += _liquid * _liquidity_threshold / _BPS;
            _liq = min(_liq, _liquid);
            _liq = max(_liq, _minLiquidity);
        }
        return _liq;
    }
    
    /**
         * @notice Multiplier representing the most one can borrow against their collateral in this market.
         *  For instance, 0.9 to allow borrowing 90% of collateral value.
         *  Must be between 0 and 1, and stored as a mantissa.
    */
    // get total value from iron bank
    // gets collateral ratio for token on iron bank
    function _totalValueIB(address token) internal view returns (uint ib) {
        (,ib) = controller(_ib).markets(_findMarket(_ib, token)); // get collateral factor mantissa for token
        ib = ib / 1e16; // convert to 0 decimals
    }
    
    // gets total value from unit protocol
    // gets collateral ratio for token on unit vault
    function _getTotalValueUnit(address _token) internal view returns (uint unit) {
        unit = vault(_unit).initialCollateralRatio(_token);
    }
    
    // gets total value from aave
    // gets collateral ratio for token on aave
    function _getTotalValueAaveV2(address token) internal view returns (uint aavev2) {
        (aavev2) = _getParamsMemory(aave(_aavev2).getConfiguration(token));
        aavev2 = aavev2 / 1e2; // convert to 0 decimals
    }
    
    // gets max collateral ratio for token on different lending protocols 
    function _totalValueV(address token) internal view returns (uint, bool) {
        // @note block.timestamp can be manipulated by the miner
        if (block.timestamp > _totalValueCache[token]) {
            uint _max = 0; // @note initilization to 0 unnecessary, possible gas optimization?
            // find max total value for token on different protocols
            uint _tmp =  _totalValueIB(token);
            _max = max(_tmp, _max);
            _tmp = _getTotalValueAaveV2(token);
            _max = max(_tmp, _max);
            _tmp = _getTotalValueUnit(token);
            _max = max(_tmp, _max);
            _max = _max / 5 * 5; // round down to a multiple of 5
            if (_max < 60) { // if max value is lower than 60 set to 0
                _max = 0;
            }
            return (_max, true);
        } else {
            return (totalValues[token], false);
        }
    }

    // gets borrowable value in USD for amount of asset
    function _lookup(address asset, uint amount) internal returns (uint) {
        uint _rate = asset.getPrice(_currency); // get price of asset in USD // @audit overflow
        return  _rate * (amount * _totalValue(asset) / _BPS); // @note gas optimization? 
    }

    // @audit front run possibility with approve from recipient?
    // mints to msg.sender amount of WaifuTokens in exchange for dai from recipient
    function _mintDai(uint amount, address recipient) internal {
        // @note no check for success
        // @audit recipient and msg.sender swapped?
        IERC20(_dai).transferFrom(recipient, address(this), amount); // transfer from recipient to this contract amount of dai
        _mint(msg.sender, amount); // mint to msg.sender amount of WaifuToken
        dai += amount; // add amount to dai amount // @audit overflow
        emit Mint(msg.sender, _dai, recipient, amount); // emit Mint from msg.sender to recipient amount of dai
    }

    // burns amount of WaifuTokens from recipient
    // transfers amount of dai to msg.sender
    function _burnDai(uint amount, address recipient) internal {
        // @audit recipient and msg.sender swapped?
        _burn(recipient, amount); // burn amount of WaifuTokens from recipient
        // @note no check for success
        IERC20(_dai).transfer(msg.sender, amount); // transfer to msg.sender amount of dai
        dai -= amount; // reduce amount of dai // @audit overflow
        
        emit Burn(msg.sender, _dai, recipient, amount); // emit Burn from msg.sender to recipient amount of dai
    }

    function _mint(address asset, uint amount, uint minted, address recipient) internal {
        if (amount > 0) {
            // @note no check for success
            IERC20(asset).transferFrom(msg.sender, address(this), amount); // transfer from msg.sender to this contract amount of asset
        }
        // add amount of asset as collateral of msg.sender
        collateral[msg.sender][asset] += amount; // @audit overflow
        collaterals[asset] += amount;
        // add minted amount of asset as debt of msg.sender
        debt[msg.sender][asset] += minted; // @audit overflow
        debts[asset] += minted;
        // liquidity in USD for collaterals should be bigger than debt in USD
        // @note might not be able to mint if total debts > total collaterals for asset
        require(_liquidity(asset, collaterals[asset]) >= debts[asset]); // @note COMMENT: add error message
        require(_lookup(asset, collateral[msg.sender][asset]) >= debt[msg.sender][asset]); // @note COMMENT: add error message
        _mint(recipient, minted); // mint to recipient minted amount of WaifuTokens
    
        emit Mint(msg.sender, asset, recipient, amount); // emit Mint from msg.sender to recipient amount of asset
    }

    function _burn(address asset, uint amount, uint burned, address recipient) internal {
        _burn(msg.sender, burned); // burn burned amount of WaifuTokens from msg.sender
        
        debt[msg.sender][asset] -= burned; // decrease debt of msg.sender in asset by burned  // @audit overflow
        debts[asset] -= burned; // decrease total debts of asset by burned 
        collateral[msg.sender][asset] -= amount; // decrease collateral of msg.sender in asset by amount // @audit overflow
        collaterals[asset] -= amount; // decrease total collaterals of asset by amount
        
        // @note using public lookup instead of internal
        require(lookup(asset, collateral[msg.sender][asset]) >= debt[msg.sender][asset]); // @note COMMENT: add error message
        
        if (amount > 0) {
            // @note no check for success
            IERC20(asset).transfer(recipient, amount); // transfer amount of asset to recipient
        }
        emit Burn(msg.sender, asset, recipient, amount); // emit Burn from msg.sender to recipient amount of asset
    }

    // gets total value for token
    function _totalValue(address token) internal returns (uint) {
        (uint _val, bool _updated) = _totalValueV(token);
        if (_updated) { // update total value and cache timestamp
            _totalValueCache[token] = block.timestamp + _CACHE_LIFESPAN;
            totalValues[token] = _val;
        }
        return _val;
    }

    // gets liquidity of amount of token in dai
    function _liquidity(address token, uint amount) internal returns (uint) {
        if (_liquidityCache[token] == 0) { // if token is not initialized set its liquidity as minimum liquidity
            liquidities[token] = _minLiquidity;
        }
        (uint _val, bool _updated) = _liquidityV(token, amount); // get liquidity value for amount of token in dai
        if (_updated) { // update liquidity of token and cache timestamp
            _liquidityCache[token] = block.timestamp + _CACHE_LIFESPAN;
            liquidities[token] = _val;
        }
        return _val;
    }
}