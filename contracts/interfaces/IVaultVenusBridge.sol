// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

interface IVaultVenusBridge {

    struct MarketInfo {
        address token;
        address vToken;
        uint available;
        uint vTokenAmount;
    }

    function infoOf(address vault) external view returns (MarketInfo memory);
    function availableOf(address vault) external view returns (uint);

    function migrateTo(address payable target) external;
    function deposit(address vault, uint amount) external payable;
    function withdraw(address account, uint amount) external;
    function harvest() external;
    function balanceOfUnderlying(address vault) external returns (uint);

    function mint(uint amount) external;
    function redeemUnderlying(uint amount) external;
    function redeemAll() external;
    function borrow(uint amount) external;
    function repayBorrow(uint amount) external;
}