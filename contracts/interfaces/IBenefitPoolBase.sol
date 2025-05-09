// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

interface IBenefitPoolBase {

    /**
     * @dev No Benefit
     */
    error BenefitPoolNoBenefit();

    event BenefitExecuted(address indexed executor, bool isEth, uint256 totalBenefitAmount);

    function executeBenefit(bool isEth, uint256 deadline) external returns (bool);
    
}
