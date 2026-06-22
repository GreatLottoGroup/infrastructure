// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {BaseTest} from "./base/BaseTest.sol";
import {SalesChannel} from "../../contracts/SalesChannel.sol";
import {ISalesChannel} from "../../contracts/interfaces/ISalesChannel.sol";
import {NoDelegateCall} from "../../contracts/base/NoDelegateCall.sol";
import {DeadLine} from "../../contracts/base/DeadLine.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

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

/// @title SalesChannelTest
/// @notice 全覆盖：registerChannel / changeChannelName / disable / enable / 视图 getter，
///         以及继承自 base 的 DeadLine（过期）与 NoDelegateCall（delegatecall）守卫、Ownable 权限门。
contract SalesChannelTest is BaseTest {
    SalesChannel internal channel;

    string internal constant NAME = "channel-A";

    function setUp() public {
        channel = new SalesChannel(owner);
    }

    // ---------------------------------------------------------------------
    // constructor
    // ---------------------------------------------------------------------

    function test_constructor_setsOwner() public view {
        assertEq(channel.owner(), owner);
    }

    function test_constructor_zeroOwner_fallsBackToDeployer() public {
        SalesChannel c = new SalesChannel(address(0));
        assertEq(c.owner(), address(this));
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

        (bool status, address chn, string memory name) = channel.getChannelById(1);
        assertTrue(status);
        assertEq(chn, alice);
        assertEq(name, NAME);

        (bool status2, uint256 id2, string memory name2) = channel.getChannelByAddr(alice);
        assertTrue(status2);
        assertEq(id2, 1);
        assertEq(name2, NAME);

        assertEq(channel.getChannelCount(), 1);
    }

    function test_registerChannel_assignsSequentialIds() public {
        vm.prank(alice);
        channel.registerChannel("a", futureDeadline());
        vm.prank(bob);
        channel.registerChannel("b", futureDeadline());

        (, uint256 idA,) = channel.getChannelByAddr(alice);
        (, uint256 idB,) = channel.getChannelByAddr(bob);
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
        (,, string memory name) = channel.getChannelById(1);
        assertEq(name, "renamed");
    }

    function test_changeChannelName_revert_whenNotExists() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ISalesChannel.SalesChannelNotExists.selector, alice));
        channel.changeChannelName("x", futureDeadline());
    }

    function test_changeChannelName_revert_whenDisabled() public {
        vm.prank(alice);
        channel.registerChannel(NAME, futureDeadline());

        vm.prank(owner);
        channel.disableChannel(1);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ISalesChannel.SalesChannelAlreadyDisabled.selector, alice));
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
        (bool s1, uint256 id1, string memory n1) = channel.getChannelByAddr(address(0));
        assertFalse(s1);
        assertEq(id1, 0);
        assertEq(n1, "");

        (bool s2, uint256 id2, string memory n2) = channel.getChannelByAddr(bob);
        assertFalse(s2);
        assertEq(id2, 0);
        assertEq(n2, "");
    }

    function test_getChannelById_zeroAndUnknown_returnEmpty() public view {
        (bool s1, address a1, string memory n1) = channel.getChannelById(0);
        assertFalse(s1);
        assertEq(a1, address(0));
        assertEq(n1, "");

        (bool s2, address a2, string memory n2) = channel.getChannelById(999);
        assertFalse(s2);
        assertEq(a2, address(0));
        assertEq(n2, "");
    }

    function test_getChannelCount_startsAtZero() public view {
        assertEq(channel.getChannelCount(), 0);
    }

    // ---------------------------------------------------------------------
    // disableChannel
    // ---------------------------------------------------------------------

    function test_disableChannel_success_emitsAndFlips() public {
        vm.prank(alice);
        channel.registerChannel(NAME, futureDeadline());

        vm.expectEmit(true, false, false, true, address(channel));
        emit ISalesChannel.SalesChannelDisabled(1, alice);
        vm.prank(owner);
        channel.disableChannel(1);

        (bool status,,) = channel.getChannelById(1);
        assertFalse(status);
    }

    function test_disableChannel_revert_whenNotExists() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ISalesChannel.SalesChannelNotExists.selector, address(0)));
        channel.disableChannel(42);
    }

    function test_disableChannel_revert_whenAlreadyDisabled() public {
        vm.prank(alice);
        channel.registerChannel(NAME, futureDeadline());
        vm.startPrank(owner);
        channel.disableChannel(1);
        vm.expectRevert(abi.encodeWithSelector(ISalesChannel.SalesChannelAlreadyDisabled.selector, alice));
        channel.disableChannel(1);
        vm.stopPrank();
    }

    function test_disableChannel_revert_whenNotOwner() public {
        vm.prank(alice);
        channel.registerChannel(NAME, futureDeadline());
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        channel.disableChannel(1);
    }

    // ---------------------------------------------------------------------
    // enableChannel
    // ---------------------------------------------------------------------

    function test_enableChannel_success_emitsAndFlips() public {
        vm.prank(alice);
        channel.registerChannel(NAME, futureDeadline());
        vm.startPrank(owner);
        channel.disableChannel(1);

        vm.expectEmit(true, false, false, true, address(channel));
        emit ISalesChannel.SalesChannelEnabled(1, alice);
        channel.enableChannel(1);
        vm.stopPrank();

        (bool status,,) = channel.getChannelById(1);
        assertTrue(status);
    }

    function test_enableChannel_revert_whenNotExists() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ISalesChannel.SalesChannelNotExists.selector, address(0)));
        channel.enableChannel(42);
    }

    function test_enableChannel_revert_whenAlreadyEnabled() public {
        vm.prank(alice);
        channel.registerChannel(NAME, futureDeadline());
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ISalesChannel.SalesChannelAlreadyEnabled.selector, alice));
        channel.enableChannel(1);
    }

    function test_enableChannel_revert_whenNotOwner() public {
        vm.prank(alice);
        channel.registerChannel(NAME, futureDeadline());
        vm.prank(owner);
        channel.disableChannel(1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        channel.enableChannel(1);
    }
}
