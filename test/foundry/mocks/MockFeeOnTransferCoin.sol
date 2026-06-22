// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

// Hardhat-only mock: fee-on-transfer ERC20. Each transfer burns a fixed fee from the sender's send,
// so the recipient receives less than `amount` and the sender pays an extra `fee` beyond `amount`.
// Used to exercise PrizePoolBase._transferTo fee-on-transfer revert path.

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockFeeOnTransferCoin is ERC20 {
    uint256 public constant FEE = 1;

    constructor() ERC20("MockFeeOnTransfer", "MFT") {}

    function mintFor(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @dev On every transfer, burn an extra `FEE` from `from`. recipient still receives `value`,
    /// so sender's balance drops by `value + FEE`. PrizePoolBase._transferTo's strict equality
    /// post-check (`balanceOf(this) == _balance - amount`) will see `_balance - amount - FEE` and revert.
    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0) && value > 0) {
            super._update(from, address(0), FEE);
        }
        super._update(from, to, value);
    }
}
