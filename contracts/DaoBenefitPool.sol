// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "./base/BenefitPoolBase.sol";

// 利润池合约
contract DaoBenefitPool is BenefitPoolBase{

    constructor(address coinAddr, address daoCoinAddr) {
        GreatLottoCoinAddress = coinAddr;
        GovernCoinAddress = daoCoinAddr;
    }

}
