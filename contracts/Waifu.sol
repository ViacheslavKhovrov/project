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

    address constant _dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address constant _router = 0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address constant _currency = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // we assume USDT is stable to USD
    
    uint256 constant _BPS = 100;
    uint256 constant _LIQUIDATION_VALUE = 90;
    uint256 constant _CACHE_LIFESPAN = 86400;
    uint256 constant _minLiquidity = 450000e18;
    uint256 constant _liquidity_threshold = 5;

    // Lending protocols
    address constant _aavev2 = address(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9);
    address constant _ib = address(0xAB1c342C7bf5Ec5F02ADEA1c2270670bCa144CbB);
    address constant _unit = address(0x203153522B9EAef4aE17c6e99851EE7b2F7D312E);
    address constant _weth = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    
    uint256 constant _totalValue_MASK = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF0000;
    
    mapping(address => mapping(address => uint)) public debt;
    mapping(address => mapping(address => uint)) public collateral;
    
    mapping(address => uint) public debts;
    mapping(address => uint) public collaterals;
    
    mapping(address => uint) public totalValues;
    mapping(address => uint) _totalValueCache;
    
    mapping(address => uint) public liquidities;
    mapping(address => uint) _liquidityCache;
        
    uint public dai;
    
    constructor() ERC20("Waifu USD", "WUSD") { }

    function getSoftRepayment(uint __totalValue, uint _debt, uint value) public pure returns (uint repayment) {
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
        } else if (__totalValue >= 90) {
            return _debt;
        }
    }
    
    function lookup(address asset, uint amount) public view returns (uint) {
        uint _rate = asset.getPrice(_currency);
        return _rate * (amount * totalValues[asset] / _BPS);
    }

    function loockupL(address asset, uint amount) public view returns (uint) {
        return asset.getPrice(_currency) * (amount * _LIQUIDATION_VALUE / _BPS);
    }

    function lookup(address asset) external view returns (uint) {
        return asset.getPrice(_currency);
    }
    
    function totalValue(address token) external view returns (uint val) {
        (val,) = _totalValueV(token);
    }

    function liquidity(address token, uint amount) external view returns (uint val) {
        (val,) = _liquidityV(token, amount);
    }

    function getRepayment(address owner, address asset) external view returns (uint) {
        uint _nominal = collateral[owner][asset];
        
        uint _backed = lookup(asset, _nominal);
        uint _debt = debt[owner][asset];
        if (_backed < _debt) {
            return getSoftRepayment(totalValues[asset], _debt, _backed);
        } else {
            return 0;
        }
    }
    
    function getPayment(address owner, address asset) external view returns (uint) {
        uint _nominal = collateral[owner][asset];
        
        uint _backed = lookup(asset, _nominal);
        uint _debt = debt[owner][asset];
        if (_backed < _debt) {
            uint _repayment = getSoftRepayment(totalValues[asset], _debt, _backed);
            return min(_nominal * _repayment / loockupL(asset, _nominal), _nominal);
        } else {
            return 0;
        }
    }

    function mintDai(uint amount) external {
        _mintDai(amount, msg.sender);
    }
    
    function mintDai(uint amount, address recipient) external {
        _mintDai(amount, recipient);
    }
    
    function burnDai(uint amount) external {
        _burnDai(amount, msg.sender);
    }
    
    function burnDai(uint amount, address recipient) external {
        _burnDai(amount, recipient);
    }
    
    function mint(address asset, uint amount, uint minted) external {
        _mint(asset, amount, minted, msg.sender);
    }
    
    function mint(address asset, uint amount, uint minted, address recipient) external {
        _mint(asset, amount, minted, recipient);
    }
    
    function burn(address asset, uint amount, uint burned) external {
        _burn(asset, amount, burned, msg.sender);
    }
    
    function burn(address asset, uint amount, uint burned, address recipient) external {
        _burn(asset, amount, burned, recipient);
    }
    
    function liquidate(address owner, address asset, uint max) external {
        uint _nominal = collateral[owner][asset];
        
        uint _backed = _lookup(asset, _nominal);
        uint _debt = debt[owner][asset];
        
        uint _repayment = getSoftRepayment(_totalValue(asset), _debt, _backed);
        require(_repayment <= max);
        uint _payment = min(_nominal * _repayment / loockupL(asset, _nominal), _nominal);
        
        _burn(msg.sender, _repayment);
        
        debt[owner][asset] -= _repayment;
        debts[asset] -= _repayment;
        collateral[owner][asset] -= _payment;
        collaterals[asset] -= _payment;
        
        require(_lookup(asset, collateral[owner][asset]) >= debt[owner][asset]);
        
        IERC20(asset).transfer(msg.sender, _payment);
        emit Liquidate(msg.sender, asset, owner, _repayment);
    }

    function _getParamsMemory(aave.ReserveConfigurationMap memory self) internal pure returns (uint256) { 
        return (self.data & ~_totalValue_MASK);
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    function _findMarket(address _core, address _token) internal view returns (address) {
        address[] memory _list = compound(_core).getAllMarkets();
        for (uint i = 0; i < _list.length; i++) {
            if (_list[i] != address(0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5) && _list[i] != address(0xD06527D5e56A3495252A528C4987003b712860eE)) {
                if (cMarket(_list[i]).underlying() == _token) {
                    return _list[i];
                }
            }
        }
        return address(0x0);
    }
    
    function _liquidityV(address token, uint amount) internal view returns (uint, bool) {
        if (block.timestamp > _liquidityCache[token]) {
            if (token == _weth) {
                return (_liqVWETH(amount), true);
            } else {
                address[] memory _path = new address[](3);
                _path[0] = token;
                _path[1] = _weth;
                _path[2] = _dai;
                uint _liq = UniswapV2Router02(_router).getAmountsOut(amount, _path)[2];
                uint _liquid = liquidities[token];
                if (_liq > _liquid) {
                    _liquid += _liquid * _liquidity_threshold / _BPS;
                    _liq = min(_liq, _liquid);
                    _liq = max(_liq, _minLiquidity);
                }
                return (_liq, true);
            }
        } else {
            return (liquidities[token], false);
        }
    }
    
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
    
    function _totalValueIB(address token) internal view returns (uint ib) {
        (,ib) = controller(_ib).markets(_findMarket(_ib, token));
        ib = ib / 1e16;
    }
    
    function _getTotalValueUnit(address _token) internal view returns (uint unit) {
        unit = vault(_unit).initialCollateralRatio(_token);
    }
    
    function _getTotalValueAaveV2(address token) internal view returns (uint aavev2) {
        (aavev2) = _getParamsMemory(aave(_aavev2).getConfiguration(token));
        aavev2 = aavev2 / 1e2;
    }
    
    function _totalValueV(address token) internal view returns (uint, bool) {
        if (block.timestamp > _totalValueCache[token]) {
            uint _max = 0;
            uint _tmp =  _totalValueIB(token);
            _max = max(_tmp, _max);
            _tmp = _getTotalValueAaveV2(token);
            _max = max(_tmp, _max);
            _tmp = _getTotalValueUnit(token);
            _max = max(_tmp, _max);
            _max = _max / 5 * 5;
            if (_max < 60) {
                _max = 0;
            }
            return (_max, true);
        } else {
            return (totalValues[token], false);
        }
    }

    function _lookup(address asset, uint amount) internal returns (uint) {
        uint _rate = asset.getPrice(_currency);
        return  _rate * (amount * _totalValue(asset) / _BPS);
    }

    function _mintDai(uint amount, address recipient) internal {
        IERC20(_dai).transferFrom(recipient, address(this), amount);
        _mint(msg.sender, amount);
        dai += amount;
        emit Mint(msg.sender, _dai, recipient, amount);
    }

    function _burnDai(uint amount, address recipient) internal {
        _burn(recipient, amount);
        IERC20(_dai).transfer(msg.sender, amount);
        dai -= amount;
        emit Burn(msg.sender, _dai, recipient, amount);
    }

    function _mint(address asset, uint amount, uint minted, address recipient) internal {
        if (amount > 0) {
            IERC20(asset).transferFrom(msg.sender, address(this), amount);
        }
        
        collateral[msg.sender][asset] += amount;
        collaterals[asset] += amount;
        
        debt[msg.sender][asset] += minted;
        debts[asset] += minted;
        
        require(_liquidity(asset, collaterals[asset]) >= debts[asset]);
        require(_lookup(asset, collateral[msg.sender][asset]) >= debt[msg.sender][asset]);
        _mint(recipient, minted);
        emit Mint(msg.sender, asset, recipient, amount);
    }

    function _burn(address asset, uint amount, uint burned, address recipient) internal {
        _burn(msg.sender, burned);
        
        debt[msg.sender][asset] -= burned;
        debts[asset] -= burned;
        collateral[msg.sender][asset] -= amount;
        collaterals[asset] -= amount;
        
        require(lookup(asset, collateral[msg.sender][asset]) >= debt[msg.sender][asset]);
        
        if (amount > 0) {
            IERC20(asset).transfer(recipient, amount);
        }
        emit Burn(msg.sender, asset, recipient, amount);
    }

    function _totalValue(address token) internal returns (uint) {
        (uint _val, bool _updated) = _totalValueV(token);
        if (_updated) {
            _totalValueCache[token] = block.timestamp + _CACHE_LIFESPAN;
            totalValues[token] = _val;
        }
        return _val;
    }

    function _liquidity(address token, uint amount) internal returns (uint) {
        if (_liquidityCache[token] == 0) {
            liquidities[token] = _minLiquidity;
        }
        (uint _val, bool _updated) = _liquidityV(token, amount);
        if (_updated) {
            _liquidityCache[token] = block.timestamp + _CACHE_LIFESPAN;
            liquidities[token] = _val;
        }
        return _val;
    }
}