// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

import "../library/Math.sol";
import "../library/SafeMath.sol";
import "../library/SafeBEP20.sol";
import "../library/ReentrancyGuard.sol";
import "../library/ReentrancyGuardUpgradeable.sol";

import "../interfaces/IAMVStrategy.sol";
import "../interfaces/IAMVMinterV2.sol";
import "../interfaces/IAMVChef.sol";
import "./VaultAMVController.sol";
import {PoolConstant} from "../library/PoolConstant.sol";


contract VaultAMV is VaultAMVController, IAMVStrategy, ReentrancyGuardUpgradeable {
    using SafeMath for uint;
    using SafeBEP20 for IBEP20;

    /* ========== CONSTANTS ============= */

    address private constant AMV = 0x4b6BE454C48d24144CBaa581A8eBC86F64139580;
    PoolConstant.PoolTypes public constant override poolType = PoolConstant.PoolTypes.AMVStake;

    /* ========== STATE VARIABLES ========== */

    uint public override pid;
    uint private _totalSupply;
    mapping(address => uint) private _balances;
    mapping(address => uint) private _depositedAt;

    /* ========== INITIALIZER ========== */

    function initialize() external initializer {
        __VaultController_init(IBEP20(AMV));
        __ReentrancyGuard_init();
    }

    /* ========== VIEWS ========== */

    function totalSupply() external view override returns (uint) {
        return _totalSupply;
    }

    function balance() external view override returns (uint) {
        return _totalSupply;
    }

    function balanceOf(address account) external view override returns (uint) {
        return _balances[account];
    }

    function sharesOf(address account) external view override returns (uint) {
        return _balances[account];
    }

    function principalOf(address account) external view override returns (uint) {
        return _balances[account];
    }

    function depositedAt(address account) external view override returns (uint) {
        return _depositedAt[account];
    }

    function withdrawableBalanceOf(address account) public view override returns (uint) {
        return _balances[account];
    }

    function rewardsToken() external view override returns (address) {
        return AMV;
    }

    function priceShare() external view override returns (uint) {
        return 1e18;
    }

    function earned(address) override public view returns (uint) {
        return 0;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function deposit(uint amount) override public {
        _deposit(amount, msg.sender);
    }

    function depositAll() override external {
        deposit(_stakingToken.balanceOf(msg.sender));
    }

    function withdraw(uint amount) override public nonReentrant {
        require(amount > 0, "VaultAMV: amount must be greater than zero");
        _amvChef.notifyWithdrawn(msg.sender, amount);

        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = _balances[msg.sender].sub(amount);

        uint withdrawalFee;
        if (canMint()) {
            uint depositTimestamp = _depositedAt[msg.sender];
            withdrawalFee = _minter.withdrawalFee(amount, depositTimestamp);
            if (withdrawalFee > 0) {
                _minter.mintFor(address(_stakingToken), withdrawalFee, 0, msg.sender, depositTimestamp);
                amount = amount.sub(withdrawalFee);
            }
        }

        _stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount, withdrawalFee);
    }

    function withdrawAll() external override {
        uint _withdraw = withdrawableBalanceOf(msg.sender);
        if (_withdraw > 0) {
            withdraw(_withdraw);
        }
        getReward();
    }

    function getReward() public override nonReentrant {
        uint amvAmount = _amvChef.safeAMVTransfer(msg.sender);
        emit ProfitPaid(msg.sender, amvAmount, 0);
    }

    function harvest() public override {
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function setMinter(address _minter) public override onlyOwner {
        VaultAMVController.setMinter(_minter);
    }

    function setAMVChef(IAMVChef _chef) public override onlyOwner {
        require(address(_amvChef) == address(0), "VaultAMV: setAMVChef only once");
        VaultAMVController.setAMVChef(IAMVChef(_chef));
    }

    /* ========== PRIVATE FUNCTIONS ========== */

    function _deposit(uint amount, address _to) private nonReentrant notPaused {
        require(amount > 0, "VaultBunny: amount must be greater than zero");
        _totalSupply = _totalSupply.add(amount);
        _balances[_to] = _balances[_to].add(amount);
        _depositedAt[_to] = block.timestamp;
        _stakingToken.safeTransferFrom(msg.sender, address(this), amount);

        _amvChef.notifyDeposited(msg.sender, amount);
        emit Deposited(_to, amount);
    }

    /* ========== SALVAGE PURPOSE ONLY ========== */

    function recoverToken(address tokenAddress, uint tokenAmount) external override onlyOwner {
        require(tokenAddress != address(_stakingToken), "VaultBunny: cannot recover underlying token");
        IBEP20(tokenAddress).safeTransfer(owner(), tokenAmount);
        emit Recovered(tokenAddress, tokenAmount);
    }
}