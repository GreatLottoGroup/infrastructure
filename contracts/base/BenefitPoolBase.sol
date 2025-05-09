// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import "../interfaces/IBenefitPoolBase.sol";
import "../interfaces/IBeneficiaryBase.sol";
import "../interfaces/IErrors.sol";

import "./NoDelegateCall.sol";
import "./DeadLine.sol";

//import "hardhat/console.sol";

abstract contract BenefitPoolBase is DeadLine, NoDelegateCall, IBenefitPoolBase, IErrors {

    using SafeERC20 for IERC20;

    // 资产币地址
    address public immutable GreatLottoCoinAddress;

    // 资产币地址
    address public immutable GreatLottoEthAddress;

    // 治理币地址
    address public immutable GovernCoinAddress;

    // 治理币地址
    address public immutable GovernEthAddress;

    constructor() {}

    // 执行分润
    function _executeBenefit(IERC20 coin, IBeneficiaryBase governCoin) private returns (uint256 totalBenefitAmount) {
        
        // 获取利润金额
        uint256 benefitTotalAmount = coin.balanceOf(address(this));
        // 获取分润受益人列表
        address[] memory beneficiaryList = governCoin.getBeneficiaryList();

        // 没有分润
        if(benefitTotalAmount == 0){
            revert BenefitPoolNoBenefit();
        }

        // 遍历受益人列表
        for (uint256 i = 0; i < beneficiaryList.length; i++) {
            // 获取分润受益人地址
            address beneficiary = beneficiaryList[i];
            if (governCoin.isBenefitAccount(beneficiary)) {
                // 获取分润金额
                uint256 _benefitAmount = governCoin.getBenefitAmount(beneficiary, benefitTotalAmount);
                totalBenefitAmount += _benefitAmount;
                // 给受益人打款
                coin.safeTransfer(beneficiary, _benefitAmount);
            }
        }

        // 校验
        if(benefitTotalAmount - totalBenefitAmount < coin.balanceOf(address(this))){
            revert ErrorPaymentUnsuccessful();
        }

    }

    // 执行分润
    function executeBenefit(bool isEth, uint256 deadline) external noDelegateCall checkDeadline(deadline) returns (bool) {
        
        // 获取资产币合约
        IERC20 coin = IERC20(isEth ? GreatLottoEthAddress : GreatLottoCoinAddress);
        // 获取治理币合约
        IBeneficiaryBase governCoin = IBeneficiaryBase(isEth ? GovernEthAddress : GovernCoinAddress);

        uint256 totalBenefitAmount = _executeBenefit(coin, governCoin);

        // 触发事件
        emit BenefitExecuted(msg.sender, isEth, totalBenefitAmount);

        return true;

    }

    // 分润计算
    function _getBenefitByRate(uint originAmount, uint16 benefitRate) private pure returns(uint benefit, uint afterAmount){
        benefit = originAmount * benefitRate / 1000;
        afterAmount = originAmount - benefit;
    }
    
}
