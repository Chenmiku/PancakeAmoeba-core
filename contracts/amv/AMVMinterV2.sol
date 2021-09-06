// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "../library/BEP20.sol";
import "../library/SafeBEP20.sol";
import "../library/SafeMath.sol";

import "../interfaces/IAMVMinterV2.sol";
import "../interfaces/IStakingRewards.sol";
import "../interfaces/IPriceCalculator.sol";

import "../zap/ZapBSC.sol";
import "../library/SafeToken.sol";
import "../library/Ownable.sol";

contract AMVMinterV2 is IAMVMinterV2, Initializable, Ownable {
    using SafeMath for uint;
    using SafeBEP20 for IBEP20;

    /* ========== CONSTANTS ============= */

    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address public constant AMV = 0x76383afd3C3501C2b0f5B4450E819eD430Ce4de0;
    address public constant AMV_BNB = 0xA10a38d028fcB8C15311b7dfedB6B67B0C5Cac8f;
    address public constant AMV_POOL = 0x09FE865e8249104748Ad4a2ae57d4134E43Edd6B;

    address public constant DEPLOYER = 0x011Fa799bbBbD64A8bEa4C821E5c1bC28C768236;
    address private constant TIMELOCK = 0x9d5BC131EB4811F60d7354ec18EA76cA5F3abE74;
    address private constant DEAD = 0x000000000000000000000000000000000000dEaD;

    uint public constant FEE_MAX = 10000;

    ZapBSC public constant zapBSC = ZapBSC(0xe675EcF46970783607115b2eC9BFe58a2DB4FB73); // ZapBSC
    IPriceCalculator public constant priceCalculator = IPriceCalculator(0x9469c89dE5a8D79C948E9a2258DD5e18D22EAC3c); // PriceCalculatorBSC

    /* ========== STATE VARIABLES ========== */

    address public amvChef;
    mapping(address => bool) private _minters;
    address public _deprecated_helper; // deprecated

    uint public PERFORMANCE_FEE;
    uint public override WITHDRAWAL_FEE_FREE_PERIOD;
    uint public override WITHDRAWAL_FEE;

    uint public override amvPerProfitBNB;
    uint public amvPerAMVBNBFlip;   // will be deprecated

    /* ========== MODIFIERS ========== */

    modifier onlyMinter {
        require(isMinter(msg.sender) == true, "AMVMinterV2: caller is not the minter");
        _;
    }

    modifier onlyAMVChef {
        require(msg.sender == amvChef, "AMVMinterV2: caller not the amv chef");
        _;
    }

    receive() external payable {}

    /* ========== INITIALIZER ========== */

    function initialize() external initializer {
        WITHDRAWAL_FEE_FREE_PERIOD = 3 days;
        WITHDRAWAL_FEE = 50;
        PERFORMANCE_FEE = 3000;

        amvPerProfitBNB = 5e18;
        amvPerAMVBNBFlip = 6e18;

        IBEP20(AMV).approve(AMV_POOL, uint(-1));
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function transferAMVOwner(address _owner) external onlyOwner {
        Ownable(AMV).transferOwnership(_owner);
    }

    function setWithdrawalFee(uint _fee) external onlyOwner {
        require(_fee < 500, "wrong fee");
        // less 5%
        WITHDRAWAL_FEE = _fee;
    }

    function setPerformanceFee(uint _fee) external onlyOwner {
        require(_fee < 5000, "wrong fee");
        PERFORMANCE_FEE = _fee;
    }

    function setWithdrawalFeeFreePeriod(uint _period) external onlyOwner {
        WITHDRAWAL_FEE_FREE_PERIOD = _period;
    }

    function setMinter(address minter, bool canMint) external override onlyOwner {
        if (canMint) {
            _minters[minter] = canMint;
        } else {
            delete _minters[minter];
        }
    }

    function setAMVPerProfitBNB(uint _ratio) external onlyOwner {
        amvPerProfitBNB = _ratio;
    }

    function setAMVPerAMVBNBFlip(uint _amvPerAMVBNBFlip) external onlyOwner {
        amvPerAMVBNBFlip = _amvPerAMVBNBFlip;
    }

    function setAMVChef(address _amvChef) external onlyOwner {
        require(amvChef == address(0), "AMVMinterV2: setAMVChef only once");
        amvChef = _amvChef;
    }

    /* ========== VIEWS ========== */

    function isMinter(address account) public view override returns (bool) {
        if (IBEP20(AMV).getOwner() != address(this)) {
            return false;
        }
        return _minters[account];
    }

    function amountAMVToMint(uint bnbProfit) public view override returns (uint) {
        return bnbProfit.mul(amvPerProfitBNB).div(1e18);
    }

    function amountAMVToMintForAMVBNB(uint amount, uint duration) public view override returns (uint) {
        return amount.mul(amvPerAMVBNBFlip).mul(duration).div(365 days).div(1e18);
    }

    function withdrawalFee(uint amount, uint depositedAt) external view override returns (uint) {
        if (depositedAt.add(WITHDRAWAL_FEE_FREE_PERIOD) > block.timestamp) {
            return amount.mul(WITHDRAWAL_FEE).div(FEE_MAX);
        }
        return 0;
    }

    function performanceFee(uint profit) public view override returns (uint) {
        return profit.mul(PERFORMANCE_FEE).div(FEE_MAX);
    }

    /* ========== V1 FUNCTIONS ========== */

    function mintFor(address asset, uint _withdrawalFee, uint _performanceFee, address to, uint) external payable override onlyMinter {
        uint feeSum = _performanceFee.add(_withdrawalFee);
        _transferAsset(asset, feeSum);

        if (asset == AMV) {
            IBEP20(AMV).safeTransfer(DEAD, feeSum);
            return;
        }

        uint amvBNBAmount = _zapAssetsToAMVBNB(asset);
        if (amvBNBAmount == 0) return;

        IBEP20(AMV_BNB).safeTransfer(AMV_POOL, amvBNBAmount);
        IStakingRewards(AMV_POOL).notifyRewardAmount(amvBNBAmount);

        (uint valueInBNB,) = priceCalculator.valueOfAsset(AMV_BNB, amvBNBAmount);
        uint contribution = valueInBNB.mul(_performanceFee).div(feeSum);
        uint mintAMV = amountAMVToMint(contribution);
        if (mintAMV == 0) return;
        _mint(mintAMV, to);
    }

    // @dev will be deprecated
    function mintForAMVBNB(uint amount, uint duration, address to) external override onlyMinter {
        uint mintAMV = amountAMVToMintForAMVBNB(amount, duration);
        if (mintAMV == 0) return;
        _mint(mintAMV, to);
    }

    /* ========== V2 FUNCTIONS ========== */

    function mint(uint amount) external override onlyAMVChef {
        if (amount == 0) return;
        _mint(amount, address(this));
    }

    function safeAMVTransfer(address _to, uint _amount) external override onlyAMVChef {
        if (_amount == 0) return;

        uint bal = IBEP20(AMV).balanceOf(address(this));
        if (_amount <= bal) {
            IBEP20(AMV).safeTransfer(_to, _amount);
        } else {
            IBEP20(AMV).safeTransfer(_to, bal);
        }
    }

    // @dev should be called when determining mint in governance. AMV is transferred to the timelock contract.
    function mintGov(uint amount) external override onlyOwner {
        if (amount == 0) return;
        _mint(amount, TIMELOCK);
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _transferAsset(address asset, uint amount) private {
        if (asset == address(0)) {
            // case) transferred BNB
            require(msg.value >= amount);
        } else {
            IBEP20(asset).safeTransferFrom(msg.sender, address(this), amount);
        }
    }

    function _zapAssetsToAMVBNB(address asset) private returns (uint) {
        if (asset != address(0) && IBEP20(asset).allowance(address(this), address(zapBSC)) == 0) {
            IBEP20(asset).safeApprove(address(zapBSC), uint(-1));
        }

        if (asset == address(0)) {
            zapBSC.zapIn{value : address(this).balance}(AMV_BNB);
        }
        else if (keccak256(abi.encodePacked(IPancakePair(asset).symbol())) == keccak256("Cake-LP")) {
            zapBSC.zapOut(asset, IBEP20(asset).balanceOf(address(this)));

            IPancakePair pair = IPancakePair(asset);
            address token0 = pair.token0();
            address token1 = pair.token1();
            if (token0 == WBNB || token1 == WBNB) {
                address token = token0 == WBNB ? token1 : token0;
                if (IBEP20(token).allowance(address(this), address(zapBSC)) == 0) {
                    IBEP20(token).safeApprove(address(zapBSC), uint(-1));
                }
                zapBSC.zapIn{value : address(this).balance}(AMV_BNB);
                zapBSC.zapInToken(token, IBEP20(token).balanceOf(address(this)), AMV_BNB);
            } else {
                if (IBEP20(token0).allowance(address(this), address(zapBSC)) == 0) {
                    IBEP20(token0).safeApprove(address(zapBSC), uint(-1));
                }
                if (IBEP20(token1).allowance(address(this), address(zapBSC)) == 0) {
                    IBEP20(token1).safeApprove(address(zapBSC), uint(-1));
                }

                zapBSC.zapInToken(token0, IBEP20(token0).balanceOf(address(this)), AMV_BNB);
                zapBSC.zapInToken(token1, IBEP20(token1).balanceOf(address(this)), AMV_BNB);
            }
        }
        else {
            zapBSC.zapInToken(asset, IBEP20(asset).balanceOf(address(this)), AMV_BNB);
        }

        return IBEP20(AMV_BNB).balanceOf(address(this));
    }

    function _mint(uint amount, address to) private {
        BEP20 tokenAMV = BEP20(AMV);

        tokenAMV.mint(amount);
        if (to != address(this)) {
            tokenAMV.transfer(to, amount);
        }

        uint amvForDev = amount.mul(15).div(100);
        tokenAMV.mint(amvForDev);
        IStakingRewards(AMV_POOL).stakeTo(amvForDev, DEPLOYER);
    }
}