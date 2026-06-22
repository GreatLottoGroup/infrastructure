// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {BaseTest} from "./base/BaseTest.sol";
import {AccessControlPartnerContract} from "../../contracts/base/AccessControlPartnerContract.sol";
import {IErrorsBase} from "../../contracts/interfaces/IErrorsBase.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/// @dev 具体化抽象基类（Foundry 惯用法：harness 内联在测试文件里，不污染 contracts/）。
contract ACPCHarness is AccessControlPartnerContract {
    constructor(address owner_) AccessControlPartnerContract(owner_) {}
}

/// @dev 运行时字节码极小（< 1000 字节），用于触发 _isContract 的「不足合约门槛」分支。
contract Tiny {}

/// @title AccessControlPartnerContractTest
/// @notice 全覆盖：PARTNER_CONTRACT_ROLE 常量 / 角色管理树 / grantRole 三道守卫
///         （零地址、非合约/小字节码、仅 admin），含 _isContract 的 >1000 字节阈值边界。
contract AccessControlPartnerContractTest is BaseTest {
    ACPCHarness internal acpc;

    bytes32 internal constant PARTNER_ROLE = keccak256("PARTNER_CONTRACT_ROLE");
    bytes32 internal constant ADMIN_ROLE = 0x00; // DEFAULT_ADMIN_ROLE

    function setUp() public {
        acpc = new ACPCHarness(owner);
    }

    // ---------------------------------------------------------------------
    // 角色常量与管理树
    // ---------------------------------------------------------------------

    function test_partnerRole_constant() public view {
        assertEq(acpc.PARTNER_CONTRACT_ROLE(), PARTNER_ROLE);
    }

    function test_owner_hasAdminRole() public view {
        assertTrue(acpc.hasRole(ADMIN_ROLE, owner));
    }

    function test_partnerRole_adminIsDefaultAdmin() public view {
        assertEq(acpc.getRoleAdmin(PARTNER_ROLE), ADMIN_ROLE);
    }

    function test_constructor_zeroOwner_fallsBackToDeployer() public {
        ACPCHarness c = new ACPCHarness(address(0));
        assertTrue(c.hasRole(ADMIN_ROLE, address(this)));
    }

    // ---------------------------------------------------------------------
    // grantRole — 守卫
    // ---------------------------------------------------------------------

    function test_grantRole_success_forContractOverThreshold() public {
        // 第二个 harness 字节码远超 1000 字节，满足合约门槛
        ACPCHarness grantee = new ACPCHarness(owner);
        vm.prank(owner);
        acpc.grantRole(PARTNER_ROLE, address(grantee));
        assertTrue(acpc.hasRole(PARTNER_ROLE, address(grantee)));
    }

    function test_grantRole_revert_whenZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(IErrorsBase.ErrorZeroAddress.selector);
        acpc.grantRole(PARTNER_ROLE, address(0));
    }

    function test_grantRole_revert_whenEOA() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IErrorsBase.ErrorInvalidAddress.selector, alice));
        acpc.grantRole(PARTNER_ROLE, alice);
    }

    function test_grantRole_revert_whenContractBelowByteThreshold() public {
        Tiny tiny = new Tiny();
        // 有 code 但 < 1000 字节 → 仍判定为「非合约」
        assertGt(address(tiny).code.length, 0);
        assertLt(address(tiny).code.length, 1000);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IErrorsBase.ErrorInvalidAddress.selector, address(tiny)));
        acpc.grantRole(PARTNER_ROLE, address(tiny));
    }

    function test_grantRole_revert_whenCallerNotAdmin() public {
        ACPCHarness grantee = new ACPCHarness(owner);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, ADMIN_ROLE)
        );
        acpc.grantRole(PARTNER_ROLE, address(grantee));
    }
}
