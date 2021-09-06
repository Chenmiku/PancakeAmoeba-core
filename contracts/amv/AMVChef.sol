// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import '../library/SafeMath.sol';
import '../interfaces/IBEP20.sol';
import '../library/SafeBEP20.sol';
import "../library/OwnableUpgradeable.sol";

import "../interfaces/IAMVMinterV2.sol";
import "../interfaces/IAMVChef.sol";
import "../interfaces/IAMVStrategy.sol";
import "./AMVToken.sol";


contract AMVChef is IAMVChef, OwnableUpgradeable {
    using SafeMath for uint;
    using SafeBEP20 for IBEP20;

    /* ========== CONSTANTS ============= */

    AMVToken public constant AMV = AMVToken(0x76383afd3C3501C2b0f5B4450E819eD430Ce4de0);

    /* ========== STATE VARIABLES ========== */

    address[] private _vaultList;
    mapping(address => VaultInfo) vaults;
    mapping(address => mapping(address => UserInfo)) vaultUsers;

    IAMVMinterV2 public minter;

    uint public startBlock;
    uint public override amvPerBlock;
    uint public override totalAllocPoint;

    /* ========== MODIFIERS ========== */

    modifier onlyVaults {
        require(vaults[msg.sender].token != address(0), "AMVChef: caller is not on the vault");
        _;
    }

    modifier updateRewards(address vault) {
        VaultInfo storage vaultInfo = vaults[vault];
        if (block.number > vaultInfo.lastRewardBlock) {
            uint tokenSupply = tokenSupplyOf(vault);
            if (tokenSupply > 0) {
                uint multiplier = timeMultiplier(vaultInfo.lastRewardBlock, block.number);
                uint rewards = multiplier.mul(amvPerBlock).mul(vaultInfo.allocPoint).div(totalAllocPoint);
                vaultInfo.accAMVPerShare = vaultInfo.accAMVPerShare.add(rewards.mul(1e12).div(tokenSupply));
            }
            vaultInfo.lastRewardBlock = block.number;
        }
        _;
    }

    /* ========== EVENTS ========== */

    event NotifyDeposited(address indexed user, address indexed vault, uint amount);
    event NotifyWithdrawn(address indexed user, address indexed vault, uint amount);
    event AMVRewardPaid(address indexed user, address indexed vault, uint amount);

    /* ========== INITIALIZER ========== */

    function initialize(uint _startBlock, uint _AMVPerBlock) external initializer {
        __Ownable_init();

        startBlock = _startBlock;
        amvPerBlock = _AMVPerBlock;
    }

    /* ========== VIEWS ========== */

    function timeMultiplier(uint from, uint to) public pure returns (uint) {
        return to.sub(from);
    }

    function tokenSupplyOf(address vault) public view returns (uint) {
        return IAMVStrategy(vault).totalSupply();
    }

    function vaultInfoOf(address vault) external view override returns (VaultInfo memory) {
        return vaults[vault];
    }

    function vaultUserInfoOf(address vault, address user) external view override returns (UserInfo memory) {
        return vaultUsers[vault][user];
    }

    function pendingAMV(address vault, address user) public view override returns (uint) {
        UserInfo storage userInfo = vaultUsers[vault][user];
        VaultInfo storage vaultInfo = vaults[vault];

        uint accAMVPerShare = vaultInfo.accAMVPerShare;
        uint tokenSupply = tokenSupplyOf(vault);
        if (block.number > vaultInfo.lastRewardBlock && tokenSupply > 0) {
            uint multiplier = timeMultiplier(vaultInfo.lastRewardBlock, block.number);
            uint AMVRewards = multiplier.mul(amvPerBlock).mul(vaultInfo.allocPoint).div(totalAllocPoint);
            accAMVPerShare = accAMVPerShare.add(AMVRewards.mul(1e12).div(tokenSupply));
        }
        return userInfo.pending.add(userInfo.balance.mul(accAMVPerShare).div(1e12).sub(userInfo.rewardPaid));
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    function addVault(address vault, address token, uint allocPoint) public onlyOwner {
        require(vaults[vault].token == address(0), "AMVChef: vault is already set");
        bulkUpdateRewards();

        uint lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(allocPoint);
        vaults[vault] = VaultInfo(token, allocPoint, lastRewardBlock, 0);
        _vaultList.push(vault);
    }

    function updateVault(address vault, uint allocPoint) public onlyOwner {
        require(vaults[vault].token != address(0), "AMVChef: vault must be set");
        bulkUpdateRewards();

        uint lastAllocPoint = vaults[vault].allocPoint;
        if (lastAllocPoint != allocPoint) {
            totalAllocPoint = totalAllocPoint.sub(lastAllocPoint).add(allocPoint);
        }
        vaults[vault].allocPoint = allocPoint;
    }

    function setMinter(address _minter) external onlyOwner {
        require(address(minter) == address(0), "AMVChef: setMinter only once");
        minter = IAMVMinterV2(_minter);
    }

    function setAMVPerBlock(uint _AMVPerBlock) external onlyOwner {
        bulkUpdateRewards();
        amvPerBlock = _AMVPerBlock;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function notifyDeposited(address user, uint amount) external override onlyVaults updateRewards(msg.sender) {
        UserInfo storage userInfo = vaultUsers[msg.sender][user];
        VaultInfo storage vaultInfo = vaults[msg.sender];

        uint pending = userInfo.balance.mul(vaultInfo.accAMVPerShare).div(1e12).sub(userInfo.rewardPaid);
        userInfo.pending = userInfo.pending.add(pending);
        userInfo.balance = userInfo.balance.add(amount);
        userInfo.rewardPaid = userInfo.balance.mul(vaultInfo.accAMVPerShare).div(1e12);
        emit NotifyDeposited(user, msg.sender, amount);
    }

    function notifyWithdrawn(address user, uint amount) external override onlyVaults updateRewards(msg.sender) {
        UserInfo storage userInfo = vaultUsers[msg.sender][user];
        VaultInfo storage vaultInfo = vaults[msg.sender];

        uint pending = userInfo.balance.mul(vaultInfo.accAMVPerShare).div(1e12).sub(userInfo.rewardPaid);
        userInfo.pending = userInfo.pending.add(pending);
        userInfo.balance = userInfo.balance.sub(amount);
        userInfo.rewardPaid = userInfo.balance.mul(vaultInfo.accAMVPerShare).div(1e12);
        emit NotifyWithdrawn(user, msg.sender, amount);
    }

    function safeAMVTransfer(address user) external override onlyVaults updateRewards(msg.sender) returns (uint) {
        UserInfo storage userInfo = vaultUsers[msg.sender][user];
        VaultInfo storage vaultInfo = vaults[msg.sender];

        uint pending = userInfo.balance.mul(vaultInfo.accAMVPerShare).div(1e12).sub(userInfo.rewardPaid);
        uint amount = userInfo.pending.add(pending);
        userInfo.pending = 0;
        userInfo.rewardPaid = userInfo.balance.mul(vaultInfo.accAMVPerShare).div(1e12);

        minter.mint(amount);
        minter.safeAMVTransfer(user, amount);
        emit AMVRewardPaid(user, msg.sender, amount);
        return amount;
    }
    
    function safeAMVTransferToVaults(address user) external override onlyVaults updateRewards(msg.sender) returns (uint) {
        UserInfo storage userInfo = vaultUsers[msg.sender][user];
        VaultInfo storage vaultInfo = vaults[msg.sender];

        uint pending = userInfo.balance.mul(vaultInfo.accAMVPerShare).div(1e12).sub(userInfo.rewardPaid);
        uint amount = userInfo.pending.add(pending);
        userInfo.pending = 0;
        userInfo.rewardPaid = userInfo.balance.mul(vaultInfo.accAMVPerShare).div(1e12);

        minter.mint(amount);
        minter.safeAMVTransfer(msg.sender, amount);
        emit AMVRewardPaid(user, msg.sender, amount);
        return amount;
    }

    function bulkUpdateRewards() public {
        for (uint idx = 0; idx < _vaultList.length; idx++) {
            if (_vaultList[idx] != address(0) && vaults[_vaultList[idx]].token != address(0)) {
                updateRewardsOf(_vaultList[idx]);
            }
        }
    }

    function updateRewardsOf(address vault) public updateRewards(vault) {
    }

    /* ========== SALVAGE PURPOSE ONLY ========== */

    function recoverToken(address _token, uint amount) virtual external onlyOwner {
        require(_token != address(AMV), "AMVChef: cannot recover AMV token");
        IBEP20(_token).safeTransfer(owner(), amount);
    }
}