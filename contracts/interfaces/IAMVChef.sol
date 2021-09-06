// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

interface IAMVChef {

    struct UserInfo {
        uint balance;
        uint pending;
        uint rewardPaid;
    }

    struct VaultInfo {
        address token;
        uint allocPoint;       // How many allocation points assigned to this pool. AMVs to distribute per block.
        uint lastRewardBlock;  // Last block number that AMVs distribution occurs.
        uint accAMVPerShare; // Accumulated AMVs per share, times 1e12. See below.
    }

    function amvPerBlock() external view returns (uint);
    function totalAllocPoint() external view returns (uint);

    function vaultInfoOf(address vault) external view returns (VaultInfo memory);
    function vaultUserInfoOf(address vault, address user) external view returns (UserInfo memory);
    function pendingAMV(address vault, address user) external view returns (uint);

    function notifyDeposited(address user, uint amount) external;
    function notifyWithdrawn(address user, uint amount) external;
    function safeAMVTransfer(address user) external returns (uint);
    function safeAMVTransferToVaults(address user) external returns (uint);
}