// SPDX-License-Identifier: MIT
pragma solidity ^0.6.2;

import "./Math.sol";
import "./SafeMath.sol";
import "../interfaces/IBEP20.sol";
import "./OwnableUpgradeable.sol";

import "./SafeDecimal.sol";
import "../interfaces/IPriceCalculator.sol";
import "../interfaces/IVenusDistribution.sol";
import "../interfaces/IVenusPriceOracle.sol";
import "../interfaces/IVToken.sol";
import "../interfaces/IVaultVenusBridge.sol";

import "../vaults/venus/VaultVenus.sol";


contract SafeVenus is OwnableUpgradeable {
    using SafeMath for uint;
    using SafeDecimal for uint;

    IPriceCalculator private constant PRICE_CALCULATOR = IPriceCalculator(0xF5BF8A9249e3cc4cB684E3f23db9669323d4FB7d);
    IVenusDistribution private constant VENUS_UNITROLLER = IVenusDistribution(0xfD36E2c2a6789Db23113685031d7F16329158384);

    address private constant XVS = 0xcF6BB5389c92Bdda8a3747Ddb454cB7a64626C63;
    uint private constant BLOCK_PER_DAY = 28800;

    /* ========== INITIALIZER ========== */

    function initialize() external initializer {
        __Ownable_init();
    }

    function valueOfUnderlying(IVToken vToken, uint amount) internal view returns (uint) {
        IVenusPriceOracle venusOracle = IVenusPriceOracle(VENUS_UNITROLLER.oracle());
        return venusOracle.getUnderlyingPrice(vToken).mul(amount).div(1e18);
    }

    /* ========== safeMintAmount ========== */

    function safeMintAmount(address payable vault) public view returns (uint mintable, uint mintableInUSD) {
        VaultVenus vaultVenus = VaultVenus(vault);
        mintable = vaultVenus.balanceAvailable().sub(vaultVenus.balanceReserved());
        mintableInUSD = valueOfUnderlying(vaultVenus.vToken(), mintable);
    }

    /* ========== safeBorrowAndRedeemAmount ========== */

    function safeBorrowAndRedeemAmount(address payable vault) public returns (uint borrowable, uint redeemable) {
        VaultVenus vaultVenus = VaultVenus(vault);
        uint collateralRatioLimit = vaultVenus.collateralRatioLimit();

        (, uint accountLiquidityInUSD,) = VENUS_UNITROLLER.getAccountLiquidity(address(vaultVenus.venusBridge()));
        uint stakingTokenPriceInUSD = valueOfUnderlying(vaultVenus.vToken(), 1e18);
        uint safeLiquidity = accountLiquidityInUSD.mul(1e18).div(stakingTokenPriceInUSD).mul(990).div(1000);

        (uint accountBorrow, uint accountSupply) = venusBorrowAndSupply(vault);
        uint supplyFactor = collateralRatioLimit.mul(accountSupply).div(1e18);
        uint borrowAmount = supplyFactor > accountBorrow ? supplyFactor.sub(accountBorrow).mul(1e18).div(uint(1e18).sub(collateralRatioLimit)) : 0;
        uint redeemAmount = accountBorrow > supplyFactor ? accountBorrow.sub(supplyFactor).mul(1e18).div(uint(1e18).sub(collateralRatioLimit)) : uint(- 1);
        return (Math.min(borrowAmount, safeLiquidity), Math.min(redeemAmount, safeLiquidity));
    }

    function safeBorrowAmount(address payable vault) public returns (uint borrowable) {
        VaultVenus vaultVenus = VaultVenus(vault);
        IVToken vToken = vaultVenus.vToken();
        uint collateralRatioLimit = vaultVenus.collateralRatioLimit();
        uint stakingTokenPriceInUSD = valueOfUnderlying(vToken, 1e18);

        (, uint accountLiquidityInUSD,) = VENUS_UNITROLLER.getAccountLiquidity(address(vaultVenus.venusBridge()));
        uint accountLiquidity = accountLiquidityInUSD.mul(1e18).div(stakingTokenPriceInUSD);
        uint marketSupply = vToken.totalSupply().mul(vToken.exchangeRateCurrent()).div(1e18);
        uint marketLiquidity = marketSupply > vToken.totalBorrowsCurrent() ? marketSupply.sub(vToken.totalBorrowsCurrent()) : 0;
        uint safeLiquidity = Math.min(marketLiquidity, accountLiquidity).mul(990).div(1000);

        (uint accountBorrow, uint accountSupply) = venusBorrowAndSupply(vault);
        uint supplyFactor = collateralRatioLimit.mul(accountSupply).div(1e18);
        uint borrowAmount = supplyFactor > accountBorrow ? supplyFactor.sub(accountBorrow).mul(1e18).div(uint(1e18).sub(collateralRatioLimit)) : 0;
        return Math.min(borrowAmount, safeLiquidity);
    }

    function safeRedeemAmount(address payable vault) public returns (uint redeemable) {
        VaultVenus vaultVenus = VaultVenus(vault);
        IVToken vToken = vaultVenus.vToken();

        (, uint collateralFactorMantissa,) = VENUS_UNITROLLER.markets(address(vToken));
        uint collateralRatioLimit = collateralFactorMantissa.mul(vaultVenus.collateralRatioFactor()).div(1000);
        uint stakingTokenPriceInUSD = valueOfUnderlying(vToken, 1e18);

        (, uint accountLiquidityInUSD,) = VENUS_UNITROLLER.getAccountLiquidity(address(vaultVenus.venusBridge()));
        uint accountLiquidity = accountLiquidityInUSD.mul(1e18).div(stakingTokenPriceInUSD);
        uint marketSupply = vToken.totalSupply().mul(vToken.exchangeRateCurrent()).div(1e18);
        uint marketLiquidity = marketSupply > vToken.totalBorrowsCurrent() ? marketSupply.sub(vToken.totalBorrowsCurrent()) : 0;
        uint safeLiquidity = Math.min(marketLiquidity, accountLiquidity).mul(990).div(1000);

        (uint accountBorrow, uint accountSupply) = venusBorrowAndSupply(vault);
        uint supplyFactor = collateralRatioLimit.mul(accountSupply).div(1e18);
        uint redeemAmount = accountBorrow > supplyFactor ? accountBorrow.sub(supplyFactor).mul(1e18).div(uint(1e18).sub(collateralRatioLimit)) : uint(- 1);
        return Math.min(redeemAmount, safeLiquidity);
    }

    function venusBorrowAndSupply(address payable vault) public returns (uint borrow, uint supply) {
        VaultVenus vaultVenus = VaultVenus(vault);
        borrow = vaultVenus.vToken().borrowBalanceCurrent(address(vaultVenus.venusBridge()));
        supply = IVaultVenusBridge(vaultVenus.venusBridge()).balanceOfUnderlying(vault);
    }

    /* ========== safeCompoundDepth ========== */

    function safeCompoundDepth(address payable vault) public returns (uint) {
        VaultVenus vaultVenus = VaultVenus(vault);
        IVToken vToken = vaultVenus.vToken();
        address stakingToken = vaultVenus.stakingToken();

        (uint apyBorrow, bool borrowWithDebt) = _venusAPYBorrow(vToken, stakingToken);
        return borrowWithDebt && _venusAPYSupply(vToken, stakingToken) <= apyBorrow + 2e15 ? 0 : vaultVenus.collateralDepth();
    }

    function _venusAPYBorrow(IVToken vToken, address stakingToken) private returns (uint apy, bool borrowWithDebt) {
        (, uint xvsValueInUSD) = PRICE_CALCULATOR.valueOfAsset(XVS, VENUS_UNITROLLER.venusSpeeds(address(vToken)).mul(BLOCK_PER_DAY));
        (, uint borrowValueInUSD) = PRICE_CALCULATOR.valueOfAsset(stakingToken, vToken.totalBorrowsCurrent());

        uint apyBorrow = vToken.borrowRatePerBlock().mul(BLOCK_PER_DAY).add(1e18).power(365).sub(1e18);
        // uint apyBorrowXVS = xvsValueInUSD.mul(1e18).div(borrowValueInUSD).add(1e18).power(365).sub(1e18);
        uint apyBorrowXVS = borrowValueInUSD != 0 ? xvsValueInUSD.mul(1e18).div(borrowValueInUSD).add(1e18).power(365).sub(1e18) : 0;
        apy = apyBorrow > apyBorrowXVS ? apyBorrow.sub(apyBorrowXVS) : apyBorrowXVS.sub(apyBorrow);
        borrowWithDebt = apyBorrow > apyBorrowXVS;
    }

    function _venusAPYSupply(IVToken vToken, address stakingToken) private returns (uint apy) {
        (, uint xvsValueInUSD) = PRICE_CALCULATOR.valueOfAsset(XVS, VENUS_UNITROLLER.venusSpeeds(address(vToken)).mul(BLOCK_PER_DAY));
        (, uint supplyValueInUSD) = PRICE_CALCULATOR.valueOfAsset(stakingToken, vToken.totalSupply().mul(vToken.exchangeRateCurrent()).div(1e18));

        uint apySupply = vToken.supplyRatePerBlock().mul(BLOCK_PER_DAY).add(1e18).power(365).sub(1e18);
        // uint apySupplyXVS = xvsValueInUSD.mul(1e18).div(supplyValueInUSD).add(1e18).power(365).sub(1e18);
        uint apySupplyXVS = supplyValueInUSD != 0 ? xvsValueInUSD.mul(1e18).div(supplyValueInUSD).add(1e18).power(365).sub(1e18) : 0;
        apy = apySupply.add(apySupplyXVS);
    }
}