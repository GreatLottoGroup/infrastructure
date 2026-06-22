// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

/// @title BaseTest
/// @notice Foundry 测试公共脚手架：统一 actor 地址、时间基准与常用 helper。
///         token / 全栈部署类 fixture 后续在子类或专门的部署基类里扩展。
abstract contract BaseTest is Test {
    // 统一 actor（vm.label 后在 trace 里可读）
    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    constructor() {
        // 把块时间推到一个合理的非零基准，避免 deadline = now - 1 下溢
        vm.warp(1_700_000_000);
    }

    /// @dev 一个不会过期的 deadline（当前块时间 + 1h）
    function futureDeadline() internal view returns (uint256) {
        return block.timestamp + 1 hours;
    }
}
