// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {BaseTest} from "./base/BaseTest.sol";
import {DaoCoin} from "../../contracts/DaoCoin.sol";

/// @title BeneficiaryBaseTest
/// @notice 经 DaoCoin（is BeneficiaryBase）覆盖 _update 分润名单维护、isBenefitAccount、
///         getBenefitAmount 比例计算与 MIN_BENEFIT_SHARES 门槛进出（含 swap-pop 移除）。
contract BeneficiaryBaseTest is BaseTest {
    DaoCoin internal dao;
    uint256 internal MIN; // 1e4 * 1e18

    function setUp() public {
        dao = new DaoCoin(owner);
        MIN = dao.MIN_BENEFIT_SHARES();
    }

    function _mint(address to, uint256 amount) internal {
        vm.prank(owner);
        dao.mint(to, amount);
    }

    function test_minBenefitShares_constant() public view {
        assertEq(MIN, 1e4 * 1e18);
    }

    function test_beneficiaryList_emptyInitially() public view {
        assertEq(dao.getBeneficiaryList().length, 0);
    }

    function test_isBenefitAccount_belowThreshold_false() public {
        _mint(alice, MIN - 1);
        assertFalse(dao.isBenefitAccount(alice));
        assertEq(dao.getBeneficiaryList().length, 0);
    }

    function test_isBenefitAccount_atThreshold_true_andListed() public {
        _mint(alice, MIN);
        assertTrue(dao.isBenefitAccount(alice));
        address[] memory list = dao.getBeneficiaryList();
        assertEq(list.length, 1);
        assertEq(list[0], alice);
    }

    function test_beneficiaryList_notDuplicatedOnSecondMint() public {
        _mint(alice, MIN);
        _mint(alice, MIN);
        assertEq(dao.getBeneficiaryList().length, 1);
    }

    function test_beneficiaryList_removedWhenBalanceDropsBelowThreshold() public {
        _mint(alice, MIN);
        assertEq(dao.getBeneficiaryList().length, 1);

        // alice 转走 1 wei → 余额 < MIN → 移出名单
        vm.prank(alice);
        dao.transfer(bob, 1);

        assertFalse(dao.isBenefitAccount(alice));
        assertEq(dao.getBeneficiaryList().length, 0);
    }

    function test_beneficiaryList_swapPopRemovesMiddle() public {
        _mint(alice, MIN);
        _mint(bob, MIN);
        address carol = makeAddr("carol");
        _mint(carol, MIN);
        assertEq(dao.getBeneficiaryList().length, 3);

        // 移除中间的 bob（swap-pop：carol 顶上）
        vm.prank(bob);
        dao.transfer(alice, MIN); // bob 清零

        address[] memory list = dao.getBeneficiaryList();
        assertEq(list.length, 2);
        // bob 不应再在名单
        for (uint256 i; i < list.length; i++) {
            assertTrue(list[i] != bob);
        }
        assertFalse(dao.isBenefitAccount(bob));
    }

    function test_getBenefitAmount_zeroWhenBelowThreshold() public {
        _mint(alice, MIN - 1);
        assertEq(dao.getBenefitAmount(alice, 1_000e18), 0);
    }

    function test_getBenefitAmount_proportionalWhenQualified() public {
        _mint(alice, MIN); // alice MIN
        _mint(bob, MIN * 3); // bob 3*MIN ; total = 4*MIN
        uint256 pool = 1_000e18;
        // alice 占 1/4
        assertEq(dao.getBenefitAmount(alice, pool), pool * MIN / (MIN * 4));
        // bob 占 3/4
        assertEq(dao.getBenefitAmount(bob, pool), pool * (MIN * 3) / (MIN * 4));
    }

    function testFuzz_getBenefitAmount_neverExceedsPool(uint256 balA, uint256 balB, uint256 pool) public {
        balA = bound(balA, MIN, 1e30);
        balB = bound(balB, MIN, 1e30);
        pool = bound(pool, 0, 1e30);
        _mint(alice, balA);
        _mint(bob, balB);
        uint256 a = dao.getBenefitAmount(alice, pool);
        uint256 b = dao.getBenefitAmount(bob, pool);
        assertLe(a + b, pool);
    }
}
