// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "./base/BenefitPoolBase.sol";

//import "hardhat/console.sol";

// 利润池合约
contract DaoBenefitPool is BenefitPoolBase{

    constructor(address coinAddr, address ethAddr, address daoCoinAddr) {
        GreatLottoCoinAddress = coinAddr;
        GreatLottoEthAddress = ethAddr;
        GovernCoinAddress = daoCoinAddr;
        GovernEthAddress = daoCoinAddr;
    }

}