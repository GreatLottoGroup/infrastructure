// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

interface IPrizePoolBase {

    event ChannelBenefitRateChanged(uint16 rate);
    event SellBenefitRateChanged(uint16 rate);

    function setChannelBenefitRate(uint16 rate) external returns (bool);
    function setSellBenefitRate(uint16 rate) external returns (bool);

    // 分润率只读 getter（由 PrizePoolBase 的 public 状态变量实现）；
    // 下游通过 `is IPrizePoolBase` 即可经接口读取实时分润率，无需重复声明。
    function channelBenefitRate() external view returns (uint16);
    function sellBenefitRate() external view returns (uint16);

}
