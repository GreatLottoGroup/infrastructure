// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {BaseTest} from "./base/BaseTest.sol";
import {DaoBenefitPool} from "../../contracts/DaoBenefitPool.sol";
import {DaoCoin} from "../../contracts/DaoCoin.sol";
import {IBenefitPoolBase} from "../../contracts/interfaces/IBenefitPoolBase.sol";
import {NoDelegateCall} from "../../contracts/base/NoDelegateCall.sol";
import {DeadLine} from "../../contracts/base/DeadLine.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/// @dev 经 delegatecall 转调 executeBenefit，触发 noDelegateCall 守卫。
contract BenefitDelegateCaller {
    function callExecute(address target, uint256 deadline) external returns (bool ok, bytes memory data) {
        (ok, data) = target.delegatecall(
            abi.encodeWithSelector(IBenefitPoolBase.executeBenefit.selector, deadline)
        );
    }
}

/// @title DaoBenefitPoolTest
/// @notice 覆盖 BenefitPoolBase（经具体的 DaoBenefitPool）：构造地址、executeBenefit 比例分润、
///         BenefitExecuted 事件、BenefitPoolNoBenefit / deadline / noDelegateCall 守卫。
contract DaoBenefitPoolTest is BaseTest {
    DaoCoin internal dao;
    MockERC20 internal glc; // 资产币（被分配的利润）
    DaoBenefitPool internal pool;
    uint256 internal MIN;

    function setUp() public {
        dao = new DaoCoin(owner);
        glc = new MockERC20("GreatLottoCoin", "GLC");
        pool = new DaoBenefitPool(address(glc), address(dao));
        MIN = dao.MIN_BENEFIT_SHARES();
    }

    function _grantShares(address to, uint256 amount) internal {
        vm.prank(owner);
        dao.mint(to, amount);
    }

    function test_constructor_setsAddresses() public view {
        assertEq(pool.GreatLottoCoinAddress(), address(glc));
        assertEq(pool.GovernCoinAddress(), address(dao));
    }

    function test_executeBenefit_distributesProportionally_andEmits() public {
        _grantShares(alice, MIN);
        _grantShares(bob, MIN); // total 2*MIN，各占 1/2
        glc.mint(address(pool), 1_000e18);

        vm.expectEmit(true, false, false, true, address(pool));
        emit IBenefitPoolBase.BenefitExecuted(address(this), 1_000e18);
        bool ok = pool.executeBenefit(futureDeadline());
        assertTrue(ok);

        assertEq(glc.balanceOf(alice), 500e18);
        assertEq(glc.balanceOf(bob), 500e18);
        assertEq(glc.balanceOf(address(pool)), 0);
    }

    function test_executeBenefit_skipsBelowThresholdHolders_strandsTheirShare() public {
        _grantShares(alice, MIN); // 合格
        _grantShares(bob, MIN - 1); // 不合格（不进名单、收不到）
        glc.mint(address(pool), 1_000e18);

        pool.executeBenefit(futureDeadline());
        // 分母仍按 totalSupply(≈2*MIN) 计：alice 占 MIN/(2MIN-1) ≈ 1/2 → 500e18；
        // bob 那一半因不合格被跳过 → 滞留池内（不会重分配给 alice）。
        assertEq(glc.balanceOf(alice), 500e18);
        assertEq(glc.balanceOf(bob), 0);
        assertEq(glc.balanceOf(address(pool)), 500e18);
    }

    function test_executeBenefit_revert_whenNoBenefit() public {
        _grantShares(alice, MIN);
        // 池内余额为 0
        vm.expectRevert(IBenefitPoolBase.BenefitPoolNoBenefit.selector);
        pool.executeBenefit(futureDeadline());
    }

    function test_executeBenefit_revert_whenDeadlineExpired() public {
        _grantShares(alice, MIN);
        glc.mint(address(pool), 1_000e18);
        uint256 expired = block.timestamp - 1;
        vm.expectRevert(
            abi.encodeWithSelector(DeadLine.DeadLineExpiredTransaction.selector, expired, block.timestamp)
        );
        pool.executeBenefit(expired);
    }

    function test_executeBenefit_revert_onDelegateCall() public {
        _grantShares(alice, MIN);
        glc.mint(address(pool), 1_000e18);
        BenefitDelegateCaller caller = new BenefitDelegateCaller();
        (bool ok, bytes memory data) = caller.callExecute(address(pool), futureDeadline());
        assertFalse(ok);
        assertEq(bytes4(data), NoDelegateCall.DelegateCalled.selector);
    }
}
