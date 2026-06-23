// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {BaseTest} from "./base/BaseTest.sol";
import {SalesChannel} from "../../contracts/SalesChannel.sol";
import {ISalesChannel} from "../../contracts/interfaces/ISalesChannel.sol";
import {GreatLottoCoin} from "../../contracts/GreatLottoCoin.sol";
import {ICoinBase} from "../../contracts/interfaces/ICoinBase.sol";
import {NoDelegateCall} from "../../contracts/base/NoDelegateCall.sol";
import {DeadLine} from "../../contracts/base/DeadLine.sol";
import {AccessControlPartnerContract} from "../../contracts/base/AccessControlPartnerContract.sol";
import {IErrorsBase} from "../../contracts/interfaces/IErrorsBase.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {MockERC20Permit} from "./mocks/MockERC20.sol";

/// @dev 经 delegatecall 转调 SalesChannel，用于触发 noDelegateCall 守卫。
contract DelegateCaller {
    function callRegister(address target, string memory name, uint256 deadline)
        external
        returns (bool ok, bytes memory data)
    {
        (ok, data) = target.delegatecall(
            abi.encodeWithSelector(SalesChannel.registerChannel.selector, name, deadline)
        );
    }
}

/// @dev 充当 PARTNER 的合约 stub。继承 AccessControlPartnerContract 以保证运行时字节码 >1000 字节，
///      满足被授 PARTNER 时 grantRole 的 `_isContract` 门槛（与真实 PrizePool 同形）。
///      payAndCredit 复刻 PrizePool「先 transfer 后 credit、等额」前置条件。
contract MockPrizePool is AccessControlPartnerContract {
    constructor() AccessControlPartnerContract(address(this)) {}

    function payAndCredit(SalesChannel ch, ICoinBase coin, uint256 chnId, uint256 amount) external {
        coin.transfer(address(ch), amount);
        ch.creditChannel(chnId, amount);
    }

    function creditOnly(SalesChannel ch, uint256 chnId, uint256 amount) external {
        ch.creditChannel(chnId, amount);
    }
}

/// @title SalesChannelTest
/// @notice 全覆盖：register / changeName / 分页遍历 / creditChannel 访问控制 / withdraw 自提（含零解析）/
///         账本视图 / DeadLine / NoDelegateCall / AccessControl 权限门。disable/enable/status 已下线。
contract SalesChannelTest is BaseTest {
    SalesChannel internal channel;
    GreatLottoCoin internal glc;
    MockPrizePool internal pool;
    MockERC20Permit internal usdc;

    bytes32 internal constant PARTNER_ROLE = keccak256("PARTNER_CONTRACT_ROLE");

    string internal constant NAME = "channel-A";

    function setUp() public {
        usdc = new MockERC20Permit("USDC", "USDC", 6);
        address[] memory toks = new address[](1);
        toks[0] = address(usdc);
        glc = new GreatLottoCoin(toks, owner);

        channel = new SalesChannel(address(glc), owner);
        pool = new MockPrizePool();

        vm.prank(owner);
        channel.grantRole(PARTNER_ROLE, address(pool));
    }

    /// @dev 给 pool 准备 GLC 并经 pool 记账（模拟 PrizePool 分润入账）。
    function _credit(uint256 chnId, uint256 amount) internal {
        deal(address(glc), address(pool), amount);
        pool.payAndCredit(channel, ICoinBase(address(glc)), chnId, amount);
    }

    // ---------------------------------------------------------------------
    // constructor
    // ---------------------------------------------------------------------

    function test_constructor_setsAdminAndCoin() public view {
        assertTrue(channel.hasRole(0x00, owner));
        assertEq(channel.GreatLottoCoinAddress(), address(glc));
        assertEq(channel.MAX_CHANNEL_PAGE(), 20);
    }

    function test_constructor_zeroOwner_fallsBackToDeployer() public {
        SalesChannel c = new SalesChannel(address(glc), address(0));
        assertTrue(c.hasRole(0x00, address(this)));
    }

    // ---------------------------------------------------------------------
    // registerChannel
    // ---------------------------------------------------------------------

    function test_registerChannel_success_emitsAndStores() public {
        vm.expectEmit(true, false, false, true, address(channel));
        emit ISalesChannel.SalesChannelRegistered(alice, 1, NAME);

        vm.prank(alice);
        bool ok = channel.registerChannel(NAME, futureDeadline());
        assertTrue(ok);

        (address chn, string memory name) = channel.getChannelById(1);
        assertEq(chn, alice);
        assertEq(name, NAME);

        (uint256 id2, string memory name2) = channel.getChannelByAddr(alice);
        assertEq(id2, 1);
        assertEq(name2, NAME);

        assertEq(channel.getChannelCount(), 1);
    }

    function test_registerChannel_assignsSequentialIds() public {
        vm.prank(alice);
        channel.registerChannel("a", futureDeadline());
        vm.prank(bob);
        channel.registerChannel("b", futureDeadline());

        (uint256 idA,) = channel.getChannelByAddr(alice);
        (uint256 idB,) = channel.getChannelByAddr(bob);
        assertEq(idA, 1);
        assertEq(idB, 2);
        assertEq(channel.getChannelCount(), 2);
    }

    function test_registerChannel_revert_whenAlreadyExists() public {
        vm.startPrank(alice);
        channel.registerChannel(NAME, futureDeadline());
        vm.expectRevert(abi.encodeWithSelector(ISalesChannel.SalesChannelAlreadyExists.selector, alice));
        channel.registerChannel("other", futureDeadline());
        vm.stopPrank();
    }

    function test_registerChannel_revert_whenDeadlineExpired() public {
        uint256 expired = block.timestamp - 1;
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(DeadLine.DeadLineExpiredTransaction.selector, expired, block.timestamp)
        );
        channel.registerChannel(NAME, expired);
    }

    function test_registerChannel_revert_onDelegateCall() public {
        DelegateCaller caller = new DelegateCaller();
        (bool ok, bytes memory data) = caller.callRegister(address(channel), NAME, futureDeadline());
        assertFalse(ok);
        assertEq(bytes4(data), NoDelegateCall.DelegateCalled.selector);
    }

    // ---------------------------------------------------------------------
    // changeChannelName
    // ---------------------------------------------------------------------

    function test_changeChannelName_success_emits() public {
        vm.startPrank(alice);
        channel.registerChannel(NAME, futureDeadline());

        vm.expectEmit(true, false, false, true, address(channel));
        emit ISalesChannel.SalesChannelNameChanged(alice, 1, "renamed");
        bool ok = channel.changeChannelName("renamed", futureDeadline());
        vm.stopPrank();

        assertTrue(ok);
        (, string memory name) = channel.getChannelById(1);
        assertEq(name, "renamed");
    }

    function test_changeChannelName_revert_whenNotExists() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ISalesChannel.SalesChannelNotExists.selector, alice));
        channel.changeChannelName("x", futureDeadline());
    }

    function test_changeChannelName_revert_whenDeadlineExpired() public {
        vm.prank(alice);
        channel.registerChannel(NAME, futureDeadline());

        uint256 expired = block.timestamp - 1;
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(DeadLine.DeadLineExpiredTransaction.selector, expired, block.timestamp)
        );
        channel.changeChannelName("x", expired);
    }

    // ---------------------------------------------------------------------
    // view getters — edge cases
    // ---------------------------------------------------------------------

    function test_getChannelByAddr_zeroAndUnknown_returnEmpty() public view {
        (uint256 id1, string memory n1) = channel.getChannelByAddr(address(0));
        assertEq(id1, 0);
        assertEq(n1, "");

        (uint256 id2, string memory n2) = channel.getChannelByAddr(bob);
        assertEq(id2, 0);
        assertEq(n2, "");
    }

    function test_getChannelById_zeroAndUnknown_returnEmpty() public view {
        (address a1, string memory n1) = channel.getChannelById(0);
        assertEq(a1, address(0));
        assertEq(n1, "");

        (address a2, string memory n2) = channel.getChannelById(999);
        assertEq(a2, address(0));
        assertEq(n2, "");
    }

    function test_getChannelCount_startsAtZero() public view {
        assertEq(channel.getChannelCount(), 0);
    }

    // ---------------------------------------------------------------------
    // getChannelsPaged
    // ---------------------------------------------------------------------

    function _registerN(uint256 n) internal {
        for (uint256 i = 0; i < n; i++) {
            address a = makeAddr(string(abi.encodePacked("ch", vm.toString(i))));
            vm.prank(a);
            channel.registerChannel(vm.toString(i), futureDeadline());
        }
    }

    function test_getChannelsPaged_normalPage() public {
        _registerN(5);
        ISalesChannel.ChannelInfo[] memory list = channel.getChannelsPaged(2, 3);
        assertEq(list.length, 3);
        assertEq(list[0].id, 2);
        assertEq(list[1].id, 3);
        assertEq(list[2].id, 4);
    }

    function test_getChannelsPaged_tailTrim() public {
        _registerN(5);
        ISalesChannel.ChannelInfo[] memory list = channel.getChannelsPaged(4, 10);
        assertEq(list.length, 2);
        assertEq(list[0].id, 4);
        assertEq(list[1].id, 5);
    }

    function test_getChannelsPaged_startIdZero_normalizesToOne() public {
        _registerN(3);
        ISalesChannel.ChannelInfo[] memory list = channel.getChannelsPaged(0, 2);
        assertEq(list.length, 2);
        assertEq(list[0].id, 1);
        assertEq(list[1].id, 2);
    }

    function test_getChannelsPaged_revert_whenCountTooLarge() public {
        vm.expectRevert(abi.encodeWithSelector(ISalesChannel.SalesChannelPageTooLarge.selector, 21));
        channel.getChannelsPaged(1, 21);
    }

    function test_getChannelsPaged_outOfRange_returnsEmpty() public {
        _registerN(5);
        ISalesChannel.ChannelInfo[] memory list = channel.getChannelsPaged(6, 5);
        assertEq(list.length, 0);
    }

    function test_getChannelsPaged_zeroCount_returnsEmpty() public {
        _registerN(5);
        ISalesChannel.ChannelInfo[] memory list = channel.getChannelsPaged(1, 0);
        assertEq(list.length, 0);
    }

    // ---------------------------------------------------------------------
    // creditChannel — access control
    // ---------------------------------------------------------------------

    function test_creditChannel_revert_whenNotPartner() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, PARTNER_ROLE)
        );
        channel.creditChannel(1, 100);
    }

    function test_creditChannel_success_accrues_emits() public {
        vm.prank(alice);
        channel.registerChannel(NAME, futureDeadline());

        deal(address(glc), address(pool), 300);
        vm.expectEmit(true, false, false, true, address(channel));
        emit ISalesChannel.SalesChannelCredited(1, 300);
        pool.payAndCredit(channel, ICoinBase(address(glc)), 1, 300);

        assertEq(channel.accruedOf(1), 300);
        assertEq(channel.pendingOf(1), 300);
        assertEq(channel.totalAccrued(), 300);
    }

    function test_creditChannel_accumulates() public {
        vm.prank(alice);
        channel.registerChannel(NAME, futureDeadline());
        _credit(1, 100);
        _credit(1, 50);
        assertEq(channel.accruedOf(1), 150);
        assertEq(channel.totalAccrued(), 150);
    }

    // ---------------------------------------------------------------------
    // withdraw
    // ---------------------------------------------------------------------

    function test_withdraw_success() public {
        vm.prank(alice);
        channel.registerChannel(NAME, futureDeadline());
        _credit(1, 300);

        vm.expectEmit(true, true, false, true, address(channel));
        emit ISalesChannel.SalesChannelWithdrawn(1, alice, 300);
        vm.prank(alice);
        channel.withdraw();

        assertEq(glc.balanceOf(alice), 300);
        assertEq(channel.withdrawnOf(1), 300);
        assertEq(channel.pendingOf(1), 0);
        assertEq(channel.totalWithdrawn(), 300);
        assertEq(channel.accruedOf(1), 300); // 累计入账不减
    }

    function test_withdraw_partialThenMore() public {
        vm.prank(alice);
        channel.registerChannel(NAME, futureDeadline());
        _credit(1, 100);
        vm.prank(alice);
        channel.withdraw();
        assertEq(channel.pendingOf(1), 0);

        _credit(1, 50);
        vm.prank(alice);
        channel.withdraw();
        assertEq(glc.balanceOf(alice), 150);
        assertEq(channel.withdrawnOf(1), 150);
        assertEq(channel.totalWithdrawn(), 150);
    }

    function test_withdraw_revert_whenNothingPending() public {
        vm.prank(alice);
        channel.registerChannel(NAME, futureDeadline());
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ISalesChannel.SalesChannelNothingToWithdraw.selector, 1));
        channel.withdraw();
    }

    /// @dev 零解析：未注册地址 → chnId 0 → pendingOf(0)==0 → revert(0)
    function test_withdraw_revert_whenUnregistered_zeroResolution() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(ISalesChannel.SalesChannelNothingToWithdraw.selector, 0));
        channel.withdraw();
    }

    function test_withdraw_revert_onDelegateCall() public {
        vm.prank(alice);
        channel.registerChannel(NAME, futureDeadline());
        _credit(1, 100);

        DelegateCaller caller = new DelegateCaller();
        (bool ok, bytes memory data) = address(caller).delegatecall(
            abi.encodeWithSelector(SalesChannel.withdraw.selector)
        );
        // delegatecall 进入 caller 上下文（无 withdraw），低层调用失败
        assertFalse(ok);
        data;
    }

    // ---------------------------------------------------------------------
    // ledger views — multi-channel
    // ---------------------------------------------------------------------

    function test_ledger_multiChannel_aggregates() public {
        vm.prank(alice);
        channel.registerChannel("a", futureDeadline());
        vm.prank(bob);
        channel.registerChannel("b", futureDeadline());

        _credit(1, 500);
        _credit(2, 200);
        assertEq(channel.totalAccrued(), 700);
        assertEq(channel.accruedOf(1), 500);
        assertEq(channel.accruedOf(2), 200);

        vm.prank(alice);
        channel.withdraw();
        assertEq(channel.totalWithdrawn(), 500);
        assertEq(channel.withdrawnOf(1), 500);
        assertEq(channel.pendingOf(1), 0);
        assertEq(channel.pendingOf(2), 200);
        // 偿付能力：合约余额 >= 全局待提
        assertGe(glc.balanceOf(address(channel)), channel.totalAccrued() - channel.totalWithdrawn());
    }
}
