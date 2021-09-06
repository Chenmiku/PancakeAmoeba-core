// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

library PoolConstant {

    enum PoolTypes {
        AMVStake,
        CakeStake, 
        FlipToFlip, 
        FlipToBNB,
        AMVBNB,
        Venus
    }

    struct PoolInfoBSC {
        address pool;
        uint balance;
        uint principal;
        uint available;
        uint tvl;
        uint utilized;
        uint liquidity;
        uint pBASE;
        uint pAMV;
        uint depositedAt;
        uint feeDuration;
        uint feePercentage;
        uint portfolio;
    }

    struct PoolInfoETH {
        address pool;
        uint collateralETH;
        uint collateralBSC;
        uint bnbDebt;
        uint leverage;
        uint tvl;
        uint updatedAt;
        uint depositedAt;
        uint feeDuration;
        uint feePercentage;
    }
}