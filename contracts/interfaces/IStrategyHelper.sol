// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "./IAMVMinterV2.sol";

interface IStrategyHelper {
    function tokenPriceInBNB(address _token) view external returns(uint);
    function cakePriceInBNB() view external returns(uint);
    function bnbPriceInUSD() view external returns(uint);
    function profitOf(IAMVMinterV2 minter, address _flip, uint amount) external view returns (uint _usd, uint _amv, uint _bnb);

    function tvl(address _flip, uint amount) external view returns (uint);    // in USD
    function tvlInBNB(address _flip, uint amount) external view returns (uint);    // in BNB
    function apy(IAMVMinterV2 minter, uint pid) external view returns(uint _usd, uint _amv, uint _bnb);
}