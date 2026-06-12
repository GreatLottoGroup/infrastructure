// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {BaseTest} from "./base/BaseTest.sol";
import {DaoCoin} from "../../contracts/DaoCoin.sol";
import {IDaoCoin} from "../../contracts/interfaces/IDaoCoin.sol";
import {IErrorsBase} from "../../contracts/interfaces/IErrorsBase.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/// @title DaoCoinTest
/// @notice 全覆盖 DaoCoin 自身逻辑：mint / mintToUser（份额换算）/ changePrice / 角色门，
///         BeneficiaryBase 的 _update 分润名单逻辑放在 BeneficiaryBase.t.sol。
contract DaoCoinTest is BaseTest {
    DaoCoin internal dao;

    bytes32 internal constant PARTNER_ROLE = keccak256("PARTNER_CONTRACT_ROLE");
    bytes32 internal constant ADMIN_ROLE = 0x00;

    uint256 internal constant INIT_PRICE = 1e18;

    function setUp() public {
        dao = new DaoCoin(owner);
        // 把 PARTNER 角色授给测试合约自身（测试合约即合约、字节码 > 1000），
        // 之后可直接 dao.mintToUser(...) 而无需独立的 PartnerTest 桩。
        vm.prank(owner);
        dao.grantRole(PARTNER_ROLE, address(this));
    }

    // ---------------------------------------------------------------------
    // constructor / 元数据
    // ---------------------------------------------------------------------

    function test_constructor_metadataAndRoles() public view {
        assertEq(dao.name(), "GreatLottoDAOCoin");
        assertEq(dao.symbol(), "GLDC");
        assertEq(dao.coinPrice(), INIT_PRICE);
        assertTrue(dao.hasRole(ADMIN_ROLE, owner));
    }

    // ---------------------------------------------------------------------
    // mint (onlyRole DEFAULT_ADMIN_ROLE)
    // ---------------------------------------------------------------------

    function test_mint_success() public {
        vm.prank(owner);
        bool ok = dao.mint(alice, 10_000e18);
        assertTrue(ok);
        assertEq(dao.balanceOf(alice), 10_000e18);
        assertEq(dao.totalSupply(), 10_000e18);
    }

    function test_mint_revert_whenNotAdmin() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, ADMIN_ROLE)
        );
        dao.mint(alice, 1e18);
    }

    // ---------------------------------------------------------------------
    // mintToUser (onlyRole PARTNER_CONTRACT_ROLE) — 份额换算
    // ---------------------------------------------------------------------

    function test_mintToUser_success_atDefaultPrice() public {
        // price = 1e18 → shares == assets
        dao.mintToUser(alice, 1_000e18);
        assertEq(dao.balanceOf(alice), 1_000e18);
    }

    function test_mintToUser_success_afterPriceChange() public {
        vm.prank(owner);
        dao.changePrice(2e18); // 2$ / 份
        dao.mintToUser(alice, 1_000e18);
        // shares = assets * 1e18 / price = 1000e18 / 2 = 500e18
        assertEq(dao.balanceOf(alice), 500e18);
    }

    function test_mintToUser_revert_whenNotPartner() public {
        // owner 只有 ADMIN、没有 PARTNER 角色
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, owner, PARTNER_ROLE)
        );
        dao.mintToUser(alice, 1e18);
    }

    function testFuzz_mintToUser_shareMath(uint256 price, uint256 assets) public {
        price = bound(price, 1, 1e30);
        assets = bound(assets, 0, 1e30);
        vm.prank(owner);
        dao.changePrice(price);
        dao.mintToUser(alice, assets);
        assertEq(dao.balanceOf(alice), assets * 1e18 / price);
    }

    // ---------------------------------------------------------------------
    // changePrice (onlyRole DEFAULT_ADMIN_ROLE)
    // ---------------------------------------------------------------------

    function test_changePrice_success_emits() public {
        vm.expectEmit(false, false, false, true, address(dao));
        emit IDaoCoin.PriceChanged(200e18);
        vm.prank(owner);
        bool ok = dao.changePrice(200e18);
        assertTrue(ok);
        assertEq(dao.coinPrice(), 200e18);
    }

    function test_changePrice_revert_whenZero() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IErrorsBase.ErrorInvalidAmount.selector, 0));
        dao.changePrice(0);
    }

    function test_changePrice_revert_whenNotAdmin() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, ADMIN_ROLE)
        );
        dao.changePrice(2e18);
    }

    // ---------------------------------------------------------------------
    // ERC20Permit / Votes 基础
    // ---------------------------------------------------------------------

    function test_nonces_startAtZero() public view {
        assertEq(dao.nonces(alice), 0);
    }
}
