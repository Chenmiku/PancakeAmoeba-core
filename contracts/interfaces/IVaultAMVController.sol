// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface IVaultAMVController {
    function minter() external view returns (address);
    function amvChef() external view returns (address);
    function stakingToken() external view returns (address);
}