// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

interface IPrizePoolBase {

    event ChannelBenefitRateChanged(uint16 rate);
    event SellBenefitRateChanged(uint16 rate);

    function setChannelBenefitRate(uint16 rate) external returns (bool);
    function setSellBenefitRate(uint16 rate) external returns (bool);

}
