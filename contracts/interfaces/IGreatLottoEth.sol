// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "./ICoinBase.sol";

interface IGreatLottoEth is ICoinBase {

    // 存款成功事件 eth
    event GreatLottoEthWrapped(address indexed payer, uint256 amount);
    // 提款成功事件 eth
    event GreatLottoEthUnwrapped(address indexed recipient, uint256 amount);

    function wrap() external payable returns (bool);
    function unwrap(uint256 amount) external payable returns (bool);

}
