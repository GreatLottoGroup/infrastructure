// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.36;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {PrizePoolBaseHarness} from "../harness/PrizePoolBaseHarness.sol";
import {GreatLottoCoin} from "../../../contracts/GreatLottoCoin.sol";
import {SalesVault} from "../../../contracts/SalesVault.sol";
import {SalesChannel} from "../../../contracts/SalesChannel.sol";
import {MockERC20Permit} from "../mocks/MockERC20.sol";

/// @dev 随机驱动兜底记账（record / softPay / claim），供 invariant 校验账本守恒。
contract PrizePoolPayoutHandler is Test {
    PrizePoolBaseHarness internal h;
    GreatLottoCoin internal glc;
    address[3] public actors;

    constructor(PrizePoolBaseHarness h_, GreatLottoCoin glc_, address[3] memory actors_) {
        h = h_;
        glc = glc_;
        actors = actors_;
    }

    function record(uint256 ai, uint256 amt) external {
        amt = bound(amt, 0, 1e24);
        h.recordPendingPayout(actors[ai % 3], amt);
    }

    function softPay(uint256 ai, uint256 amt, bool fund) external {
        amt = bound(amt, 0, 1e24);
        if (fund) deal(address(glc), address(h), amt);
        h.softPay(actors[ai % 3], amt);
    }

    function claim(uint256 ai) external {
        address a = actors[ai % 3];
        // 充足资金保证 claim 能成功（claim 自身会校验有无 pending）
        deal(address(glc), address(h), glc.balanceOf(address(h)) + h.pendingPayoutOf(a));
        vm.prank(a);
        try h.claimPayout() {} catch {}
    }

    function sumPending() external view returns (uint256 s) {
        for (uint256 i; i < 3; i++) {
            s += h.pendingPayoutOf(actors[i]);
        }
    }
}

/// @title PrizePoolPayoutInvariant
/// @notice 不变量：pendingPayoutTotal() 恒等于 Σ pendingPayoutOf(user)
///         （PrizePoolBase 文档承诺；record 自增、claim 自减两处维护）。
contract PrizePoolPayoutInvariant is StdInvariant, Test {
    PrizePoolBaseHarness internal h;
    GreatLottoCoin internal glc;
    PrizePoolPayoutHandler internal handler;

    function setUp() public {
        address owner = makeAddr("owner");
        MockERC20Permit usdc = new MockERC20Permit("USDC", "USDC", 6);
        address[] memory toks = new address[](1);
        toks[0] = address(usdc);

        glc = new GreatLottoCoin(toks, owner);
        SalesVault vault = new SalesVault(address(glc), owner);
        SalesChannel channels = new SalesChannel(address(glc), owner);
        h = new PrizePoolBaseHarness(
            address(glc), address(vault), address(channels), owner, 30, 50
        );
        vm.prank(owner);
        glc.grantRole(keccak256("PARTNER_CONTRACT_ROLE"), address(h));

        address[3] memory actors = [makeAddr("a0"), makeAddr("a1"), makeAddr("a2")];
        handler = new PrizePoolPayoutHandler(h, glc, actors);
        targetContract(address(handler));
    }

    function invariant_pendingTotalEqualsSumOfPending() public view {
        assertEq(h.pendingPayoutTotal(), handler.sumPending());
    }
}
