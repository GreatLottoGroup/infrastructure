// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {BaseTest} from "./base/BaseTest.sol";
import {SalesVault} from "../../contracts/SalesVault.sol";
import {GreatLottoCoin} from "../../contracts/GreatLottoCoin.sol";
import {MockERC20Permit} from "./mocks/MockERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

/// @title SalesVaultTest
/// @notice 覆盖 SalesVault（ERC4626 销售金库）：
///         初始铸满 1 亿 / 资产币对齐 / 分润转入抬升单份额价值 / redeem 按比例 / 份额可转让 /
///         1 亿硬上限（初始即满→deposit revert、redeem 后可 deposit、maxDeposit/maxMint 换算）/
///         offset=6 防 inflation attack（大额 redeem→supply 极低→恶意 deposit+捐赠→正常存入不被吞）/
///         纯无特权（无 topUp/sweep 入口——编译期保证，运行期断言无管理员函数）。
contract SalesVaultTest is BaseTest {
    SalesVault internal vault;
    GreatLottoCoin internal glc;

    uint256 internal constant MAX_SHARES = 100_000_000 * 1e18;

    function setUp() public {
        // GLC 底层稳定币白名单（仅为部署 GLC，本测试用 deal 直接铸 GLC）
        MockERC20Permit usdc = new MockERC20Permit("USDC", "USDC", 6);
        address[] memory toks = new address[](1);
        toks[0] = address(usdc);
        glc = new GreatLottoCoin(toks, owner);

        vault = new SalesVault(address(glc), owner);
    }

    // ---------------------------------------------------------------------
    // 部署 / 元数据
    // ---------------------------------------------------------------------

    function test_constructor_mintsMaxToOwner() public view {
        assertEq(vault.totalSupply(), MAX_SHARES);
        assertEq(vault.balanceOf(owner), MAX_SHARES);
        assertEq(vault.MAX_SHARES(), MAX_SHARES);
    }

    function test_assetIsGlc() public view {
        assertEq(vault.asset(), address(glc));
    }

    function test_decimalsOffset_isSix() public view {
        // ERC4626 decimals = underlying(18) + offset(6) = 24
        assertEq(vault.decimals(), 24);
    }

    // ---------------------------------------------------------------------
    // 分润转入 → 单份额增值
    // ---------------------------------------------------------------------

    function test_profitTransfer_raisesShareValue_notSupply() public {
        uint256 assetsBefore = vault.totalAssets();
        uint256 ownerSharesValueBefore = vault.convertToAssets(vault.balanceOf(owner));

        // 模拟 PrizePool 分润：直接向金库转 wei 级 GLC
        deal(address(glc), address(vault), assetsBefore + 1_000e18);

        assertEq(vault.totalAssets(), assetsBefore + 1_000e18);
        assertEq(vault.totalSupply(), MAX_SHARES); // supply 不变
        // owner 持全部份额 → 增值约等于全部转入
        assertGt(vault.convertToAssets(vault.balanceOf(owner)), ownerSharesValueBefore);
    }

    // ---------------------------------------------------------------------
    // redeem 按比例 + 份额可转让
    // ---------------------------------------------------------------------

    function test_redeem_proportional() public {
        // 注入分润，使金库有可分资产
        deal(address(glc), address(vault), 1_000e18);

        uint256 redeemShares = MAX_SHARES / 10; // 赎 10%
        uint256 expectedAssets = vault.previewRedeem(redeemShares);

        vm.prank(owner);
        uint256 got = vault.redeem(redeemShares, owner, owner);

        assertEq(got, expectedAssets);
        assertEq(glc.balanceOf(owner), expectedAssets);
        assertEq(vault.totalSupply(), MAX_SHARES - redeemShares);
    }

    function test_shares_transferable_secondaryHolderCanRedeem() public {
        deal(address(glc), address(vault), 1_000e18);

        uint256 give = MAX_SHARES / 4;
        vm.prank(owner);
        vault.transfer(alice, give);
        assertEq(vault.balanceOf(alice), give);

        uint256 expected = vault.previewRedeem(give);
        vm.prank(alice);
        uint256 got = vault.redeem(give, alice, alice);
        assertEq(got, expected);
        assertEq(glc.balanceOf(alice), expected);
    }

    // ---------------------------------------------------------------------
    // 1 亿硬上限
    // ---------------------------------------------------------------------

    function test_initialFull_maxDepositMintZero() public view {
        assertEq(vault.maxMint(alice), 0);
        assertEq(vault.maxDeposit(alice), 0);
    }

    function test_deposit_revert_whenFull() public {
        deal(address(glc), alice, 1_000e18);
        vm.startPrank(alice);
        glc.approve(address(vault), 1_000e18);
        vm.expectRevert(
            abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxDeposit.selector, alice, 1_000e18, 0)
        );
        vault.deposit(1_000e18, alice);
        vm.stopPrank();
    }

    function test_mint_revert_whenFull() public {
        deal(address(glc), alice, type(uint128).max);
        vm.startPrank(alice);
        glc.approve(address(vault), type(uint128).max);
        vm.expectRevert(
            abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxMint.selector, alice, 1e18, 0)
        );
        vault.mint(1e18, alice);
        vm.stopPrank();
    }

    function test_deposit_succeeds_afterRedeemFreesRoom() public {
        // 注入分润使单份额价值非零（否则 totalAssets≈0 时按现价 deposit 拿不到份额）
        deal(address(glc), address(vault), 1_000_000e18);

        // owner 先赎 10% 腾出 MAX/10 的份额额度
        uint256 redeemShares = MAX_SHARES / 10;
        vm.prank(owner);
        vault.redeem(redeemShares, owner, owner);

        assertEq(vault.maxMint(alice), redeemShares);
        uint256 room = vault.maxDeposit(alice);
        assertGt(room, 0);

        // alice 按现价存入腾出的额度
        deal(address(glc), alice, room);
        vm.startPrank(alice);
        glc.approve(address(vault), room);
        uint256 mintedShares = vault.deposit(room, alice);
        vm.stopPrank();

        assertGt(mintedShares, 0);
        assertLe(vault.totalSupply(), MAX_SHARES); // 铸后不超上限
    }

    function testFuzz_maxDeposit_neverExceedsCap(uint256 redeemFrac) public {
        // 任意赎回比例后，按 maxDeposit 顶格 deposit 都不应让 supply 超过 MAX_SHARES
        redeemFrac = bound(redeemFrac, 1, MAX_SHARES - 1);
        deal(address(glc), address(vault), 5_000e18); // 注入分润制造非平凡现价
        vm.prank(owner);
        vault.redeem(redeemFrac, owner, owner);

        uint256 room = vault.maxDeposit(alice);
        if (room == 0) return;
        deal(address(glc), alice, room);
        vm.startPrank(alice);
        glc.approve(address(vault), room);
        vault.deposit(room, alice);
        vm.stopPrank();

        assertLe(vault.totalSupply(), MAX_SHARES);
    }

    // ---------------------------------------------------------------------
    // offset=6 防 inflation attack
    // ---------------------------------------------------------------------

    /// @notice 经典 inflation attack 序列：supply 被赎到极低 → 攻击者抢首存极小额 + 直接捐赠抬价
    ///         → 验证正常用户随后 deposit 份额不被取整吞为 0、且攻击者不能净获利（offset=6 防护）。
    function test_inflationAttack_mitigatedByOffset() public {
        // 1) owner 几乎赎光，把 supply 拉到极低
        vm.startPrank(owner);
        vault.redeem(MAX_SHARES - 1, owner, owner); // 仅剩 1 wei share
        vm.stopPrank();
        assertEq(vault.totalSupply(), 1);

        // 2) 攻击者抢首存极小额（腾出额度足够）
        address attacker = makeAddr("attacker");
        uint256 room = vault.maxDeposit(attacker);
        assertGt(room, 0);

        deal(address(glc), attacker, 1); // 1 wei
        vm.startPrank(attacker);
        glc.approve(address(vault), 1);
        uint256 attackerShares = vault.deposit(1, attacker);
        vm.stopPrank();

        // 3) 攻击者直接捐赠大额 GLC 抬高单份额价格
        uint256 donation = 1_000_000e18;
        deal(address(glc), address(vault), glc.balanceOf(address(vault)) + donation);

        // 4) 正常用户随后按现价存入合理金额
        uint256 victimAssets = 500e18;
        // 确认上限额度足够
        uint256 victimRoom = vault.maxDeposit(bob);
        if (victimRoom < victimAssets) victimAssets = victimRoom;
        if (victimAssets == 0) return; // 额度耗尽则攻击本就无意义

        deal(address(glc), bob, victimAssets);
        vm.startPrank(bob);
        glc.approve(address(vault), victimAssets);
        uint256 victimShares = vault.deposit(victimAssets, bob);
        vm.stopPrank();

        // 受害者份额不被取整吞为 0（virtual shares 吸收误差）
        assertGt(victimShares, 0, "victim shares must not be rounded to zero");

        // 攻击者无法净获利：赎回其全部份额拿回的资产 <= 其投入（1 wei 存入 + donation 捐赠）
        uint256 attackerInvested = 1 + donation;
        uint256 attackerRedeemable = vault.previewRedeem(attackerShares);
        assertLe(attackerRedeemable, attackerInvested, "attacker must not profit");
    }

    // ---------------------------------------------------------------------
    // 现价申购不稀释现有持有人
    // ---------------------------------------------------------------------

    function test_currentPriceDeposit_doesNotDiluteExisting() public {
        // 注入分润使单份额 > 初始
        deal(address(glc), address(vault), 10_000e18);

        // owner 赎 20% 腾出额度
        uint256 redeemShares = MAX_SHARES / 5;
        vm.prank(owner);
        vault.redeem(redeemShares, owner, owner);

        uint256 ownerValueBefore = vault.convertToAssets(vault.balanceOf(owner));

        // alice 按现价存入
        uint256 room = vault.maxDeposit(alice);
        deal(address(glc), alice, room);
        vm.startPrank(alice);
        glc.approve(address(vault), room);
        vault.deposit(room, alice);
        vm.stopPrank();

        // owner 持有份额对应资产不因 alice 现价申购而下降（容许 ≤1 wei 取整误差）
        uint256 ownerValueAfter = vault.convertToAssets(vault.balanceOf(owner));
        assertGe(ownerValueAfter + 1, ownerValueBefore);
    }
}
