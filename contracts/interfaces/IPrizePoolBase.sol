// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

interface IPrizePoolBase {

    event SellBenefitRateChanged(uint16 rate);

    // 付奖兜底（push 付款失败 → 转 pull 模式）：记账与提取事件，coin 始终为资产币 GLC
    event PayoutPending(address indexed user, address indexed coin, uint256 amount);
    event PayoutClaimed(address indexed user, address indexed coin, uint256 amount);

    // 无可提取的兜底欠款时 revert
    error ErrorNoPendingPayout();

    // `_payoutTransfer` 仅允许本合约经 `this.` 自调用；非自调用时 revert（供下游软付款 frame 隔离守卫）
    error ErrorUnauthorizedSelfCall();

    // 销售分润率（构造初值 / setSellBenefitRate 入参）超过硬上限 MAX_SELL_BENEFIT_RATE（5% = 50‰）时 revert
    error ErrorSellRateTooHigh(uint16 rate, uint16 max);

    // 构造初值 initialChannelRate 超过硬上限 MAX_CHANNEL_BENEFIT_RATE（5% = 50‰）时 revert。
    // 渠道率部署后不可改（无 setter），故仅在构造期校验。
    error ErrorChannelRateTooHigh(uint16 rate, uint16 max);

    // 渠道分润率为构造期固定值，无运行时 setter（治理面收敛）；销售分润率可调但有硬上限。
    function setSellBenefitRate(uint16 rate) external returns (bool);

    // 付奖兜底：用户提取此前 push 失败而记账的欠款；查询某地址的待提取兜底金额。
    function claimPayout() external;
    function pendingPayoutOf(address user) external view returns (uint256);

    // 分润率只读 getter（由 PrizePoolBase 的 public 状态变量实现）；
    // 下游通过 `is IPrizePoolBase` 即可经接口读取实时分润率，无需重复声明。
    function channelBenefitRate() external view returns (uint16);
    function sellBenefitRate() external view returns (uint16);

}
