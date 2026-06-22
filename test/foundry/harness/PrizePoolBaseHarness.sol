// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

// Foundry test harness: exposes PrizePoolBase internal helpers as external wrappers.
// MUST NOT be deployed to production networks.

import "../../../contracts/base/PrizePoolBase.sol";
import "../../../contracts/interfaces/ICoinBase.sol";

contract PrizePoolBaseHarness is PrizePoolBase {

    constructor(
        address coin,
        address salesVaultAddr,
        address salesChannelAddr,
        address _owner,
        uint16 initialChannelRate,
        uint16 initialSellRate
    ) PrizePoolBase(coin, salesVaultAddr, salesChannelAddr, _owner, initialChannelRate, initialSellRate) {}

    function getCoin() external view returns (ICoinBase) {
        return _getCoin();
    }

    function colletWithCoin(address token, address payer, uint amount) external returns (ICoinBase) {
        return _colletWithCoin(token, payer, amount);
    }

    function colletWithCoin(
        address token,
        address payer,
        uint amount,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (ICoinBase) {
        return _colletWithCoin(token, payer, amount, deadline, v, r, s);
    }

    function transferTo(ICoinBase coin, address recipient, uint amount) external {
        _transferTo(coin, recipient, amount);
    }

    // 付奖兜底：暴露 internal 记账入口，模拟子类在 push 付款失败分支调用
    function recordPendingPayout(address user, uint256 amount) external {
        _recordPendingPayout(user, amount);
    }

    // 软付款：暴露 internal 入口（_payoutTransfer 已是 base external，测试可直调以验证自调用守卫）
    function softPay(address to, uint256 amount) external {
        _softPay(to, amount);
    }

    function channelBenefitTransfer(ICoinBase coin, uint256 benefit, uint256 chnId) external {
        _channelBenefitTransfer(coin, benefit, chnId);
    }

    function salesVaultTransfer(ICoinBase coin, uint256 benefit) external {
        _salesVaultTransfer(coin, benefit);
    }

    function getBenefitByRate(uint originAmount, uint16 benefitRate) external pure returns (uint, uint) {
        return _getBenefitByRate(originAmount, benefitRate);
    }

    function distributeChannelAndSalesBenefits(
        ICoinBase coin,
        uint amountByCoin,
        uint256 channelId
    ) external returns (uint) {
        return _distributeChannelAndSalesBenefits(coin, amountByCoin, channelId);
    }
}
