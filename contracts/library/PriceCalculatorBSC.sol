// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import '../interfaces/IBEP20.sol';
import "../library/SafeMath.sol";
import "../library/OwnableUpgradeable.sol";

import "../interfaces/IPancakePair.sol";
import "../interfaces/IPancakeFactory.sol";
import "../interfaces/AggregatorV3Interface.sol";
import "../interfaces/IPriceCalculator.sol";
import "../library/HomoraMath.sol";


contract PriceCalculatorBSC is IPriceCalculator, OwnableUpgradeable {
    using SafeMath for uint;
    using HomoraMath for uint;

    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address public constant CAKE = 0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82;
    address public constant AMV = 0x76383afd3C3501C2b0f5B4450E819eD430Ce4de0;
    address public constant VAI = 0x4BD17003473389A42DAF6a0a729f6Fdb328BbBd7;
    address public constant BUSD = 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56;

    address public constant AMV_BNB = 0xA10a38d028fcB8C15311b7dfedB6B67B0C5Cac8f;

    IPancakeFactory private constant factory = IPancakeFactory(0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73);

    /* ========== STATE VARIABLES ========== */

    mapping(address => address) private pairTokens;
    mapping(address => address) private tokenFeeds;

    /* ========== INITIALIZER ========== */

    function initialize() external initializer {
        __Ownable_init();
        setPairToken(VAI, BUSD);
    }

    /* ========== Restricted Operation ========== */

    function setPairToken(address asset, address pairToken) public onlyOwner {
        pairTokens[asset] = pairToken;
    }

    function setTokenFeed(address asset, address feed) public onlyOwner {
        tokenFeeds[asset] = feed;
    }

    /* ========== Value Calculation ========== */

    function priceOfBNB() view public returns (uint) {
        (, int price, , ,) = AggregatorV3Interface(tokenFeeds[WBNB]).latestRoundData();
        return uint(price).mul(1e10);
    }

    function priceOfCake() view public returns (uint) {
        (, int price, , ,) = AggregatorV3Interface(tokenFeeds[CAKE]).latestRoundData();
        return uint(price).mul(1e10);
    }

    function priceOfAMV() view public returns (uint) {
        (, uint amvPriceInUSD) = valueOfAsset(AMV, 1e18);
        return amvPriceInUSD;
    }

    function pricesInUSD(address[] memory assets) public view override returns (uint[] memory) {
        uint[] memory prices = new uint[](assets.length);
        for (uint i = 0; i < assets.length; i++) {
            (, uint valueInUSD) = valueOfAsset(assets[i], 1e18);
            prices[i] = valueInUSD;
        }
        return prices;
    }

    function valueOfAsset(address asset, uint amount) public view override returns (uint valueInBNB, uint valueInUSD) {
        if (asset == address(0) || asset == WBNB) {
            return _oracleValueOf(WBNB, amount);
        } else if (asset == AMV || asset == AMV_BNB) {
            return _unsafeValueOfAsset(asset, amount);
        } else if (keccak256(abi.encodePacked(IPancakePair(asset).symbol())) == keccak256("Cake-LP")) {
            return _getPairPrice(asset, amount);
        } else {
            return _oracleValueOf(asset, amount);
        }
    }

    function _oracleValueOf(address asset, uint amount) private view returns (uint valueInBNB, uint valueInUSD) {
        (, int price, , ,) = AggregatorV3Interface(tokenFeeds[asset]).latestRoundData();
        valueInUSD = uint(price).mul(1e10).mul(amount).div(1e18);
        valueInBNB = valueInUSD.mul(1e18).div(priceOfBNB());
    }

    function _getPairPrice(address pair, uint amount) private view returns (uint valueInBNB, uint valueInUSD) {
        address token0 = IPancakePair(pair).token0();
        address token1 = IPancakePair(pair).token1();
        uint totalSupply = IPancakePair(pair).totalSupply();
        (uint r0, uint r1, ) = IPancakePair(pair).getReserves();

        uint sqrtK = HomoraMath.sqrt(r0.mul(r1)).fdiv(totalSupply);
        (uint px0,) = _oracleValueOf(token0, 1e18);
        (uint px1,) = _oracleValueOf(token1, 1e18);
        uint fairPriceInBNB = sqrtK.mul(2).mul(HomoraMath.sqrt(px0)).div(2**56).mul(HomoraMath.sqrt(px1)).div(2**56);

        valueInBNB = fairPriceInBNB.mul(amount).div(1e18);
        valueInUSD = valueInBNB.mul(priceOfBNB()).div(1e18);
    }

    function _unsafeValueOfAsset(address asset, uint amount) private view returns (uint valueInBNB, uint valueInUSD) {
        if (asset == address(0) || asset == WBNB) {
            valueInBNB = amount;
            valueInUSD = amount.mul(priceOfBNB()).div(1e18);
        }
        else if (keccak256(abi.encodePacked(IPancakePair(asset).symbol())) == keccak256("Cake-LP")) {
            if (IPancakePair(asset).totalSupply() == 0) return (0, 0);

            (uint reserve0, uint reserve1, ) = IPancakePair(asset).getReserves();
            if (IPancakePair(asset).token0() == WBNB) {
                valueInBNB = amount.mul(reserve0).mul(2).div(IPancakePair(asset).totalSupply());
                valueInUSD = valueInBNB.mul(priceOfBNB()).div(1e18);
            } else if (IPancakePair(asset).token1() == WBNB) {
                valueInBNB = amount.mul(reserve1).mul(2).div(IPancakePair(asset).totalSupply());
                valueInUSD = valueInBNB.mul(priceOfBNB()).div(1e18);
            } else {
                (uint token0PriceInBNB,) = valueOfAsset(IPancakePair(asset).token0(), 1e18);
                valueInBNB = amount.mul(reserve0).mul(2).mul(token0PriceInBNB).div(1e18).div(IPancakePair(asset).totalSupply());
                valueInUSD = valueInBNB.mul(priceOfBNB()).div(1e18);
            }
        }
        else {
            address pairToken = pairTokens[asset] == address(0) ? WBNB : pairTokens[asset];
            address pair = factory.getPair(asset, pairToken);
            if (IBEP20(asset).balanceOf(pair) == 0) return (0, 0);

            (uint reserve0, uint reserve1, ) = IPancakePair(pair).getReserves();
            if (IPancakePair(pair).token0() == pairToken) {
                valueInBNB = reserve0.mul(amount).div(reserve1);
            } else if (IPancakePair(pair).token1() == pairToken) {
                valueInBNB = reserve1.mul(amount).div(reserve0);
            } else {
                return (0, 0);
            }

            if (pairToken != WBNB) {
                (uint pairValueInBNB,) = valueOfAsset(pairToken, 1e18);
                valueInBNB = valueInBNB.mul(pairValueInBNB).div(1e18);
            }
            valueInUSD = valueInBNB.mul(priceOfBNB()).div(1e18);
        }
    }
}