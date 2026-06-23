// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {PermitHelper} from "./base/PermitHelper.sol";
import {PrizePoolBaseHarness} from "./harness/PrizePoolBaseHarness.sol";
import {GreatLottoCoin} from "../../contracts/GreatLottoCoin.sol";
import {SalesVault} from "../../contracts/SalesVault.sol";
import {SalesChannel} from "../../contracts/SalesChannel.sol";
import {ICoinBase} from "../../contracts/interfaces/ICoinBase.sol";
import {IPrizePoolBase} from "../../contracts/interfaces/IPrizePoolBase.sol";
import {IErrorsBase} from "../../contracts/interfaces/IErrorsBase.sol";
import {ISalesChannel} from "../../contracts/interfaces/ISalesChannel.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {MockERC20Permit} from "./mocks/MockERC20.sol";
import {MockFeeOnTransferCoin} from "./mocks/MockFeeOnTransferCoin.sol";
import {MockSilentFailCoin} from "./mocks/MockSilentFailCoin.sol";

/// @title PrizePoolBaseTest
/// @notice 经 PrizePoolBaseHarness 全覆盖 PrizePoolBase 的 internal helper 与治理 setter：
///         收款 / 严格转账（含 fee-on-transfer & silent-fail 异常代币）/ 两段分润 / 兜底记账
///         （softPay→pending→claim）/ 自调用守卫 / 分润率治理。GLC 余额用 deal 直接铸，免跑底层 mint。
contract PrizePoolBaseTest is PermitHelper {
    PrizePoolBaseHarness internal h;
    GreatLottoCoin internal glc;
    SalesVault internal vault;
    SalesChannel internal channels;
    MockERC20Permit internal usdc;

    bytes32 internal constant PARTNER_ROLE = keccak256("PARTNER_CONTRACT_ROLE");
    bytes32 internal constant ADMIN_ROLE = 0x00;
    uint16 internal constant CH_RATE = 30; // 3%（<= MAX_CHANNEL_BENEFIT_RATE 50）
    uint16 internal constant SELL_RATE = 50; // 5%（= MAX_SELL_BENEFIT_RATE 上限）

    address internal channelAddr = makeAddr("channelAddr");

    function setUp() public {
        usdc = new MockERC20Permit("USDC", "USDC", 6);
        address[] memory toks = new address[](1);
        toks[0] = address(usdc);

        glc = new GreatLottoCoin(toks, owner);
        vault = new SalesVault(address(glc), owner);
        channels = new SalesChannel(address(glc), owner);
        h = new PrizePoolBaseHarness(
            address(glc), address(vault), address(channels), owner, CH_RATE, SELL_RATE
        );

        // harness 需要 PARTNER 角色以 mint GLC；并需在 SalesChannel 上有 PARTNER 角色以 creditChannel
        vm.startPrank(owner);
        glc.grantRole(PARTNER_ROLE, address(h));
        channels.grantRole(PARTNER_ROLE, address(h));
        vm.stopPrank();

        // 注册一个渠道（chnId = 1 → channelAddr）
        vm.prank(channelAddr);
        channels.registerChannel("ch", futureDeadline());
    }

    // ---------------------------------------------------------------------
    // 构造 / getter
    // ---------------------------------------------------------------------

    function test_constructor_immutablesAndRates() public view {
        assertEq(h.GreatLottoCoinAddress(), address(glc));
        assertEq(h.SalesVaultAddress(), address(vault));
        assertEq(h.SalesChannelAddress(), address(channels));
        assertEq(h.channelBenefitRate(), CH_RATE);
        assertEq(h.sellBenefitRate(), SELL_RATE);
        assertEq(address(h.getCoin()), address(glc));
    }

    function test_constructor_revert_whenChannelRateAboveCap() public {
        // 构造初值 channel 超 50‰ 上限 → revert（渠道率部署后不可改，必须构造期卡死）
        vm.expectRevert(abi.encodeWithSelector(IPrizePoolBase.ErrorChannelRateTooHigh.selector, uint16(51), uint16(50)));
        new PrizePoolBaseHarness(address(glc), address(vault), address(channels), owner, 51, 50);
    }

    function test_constructor_revert_whenSellRateAboveCap() public {
        // 构造初值 sell 超 50‰ 上限 → revert（与 setSellBenefitRate 同一上限）
        vm.expectRevert(abi.encodeWithSelector(IPrizePoolBase.ErrorSellRateTooHigh.selector, uint16(51), uint16(50)));
        new PrizePoolBaseHarness(address(glc), address(vault), address(channels), owner, 50, 51);
    }

    function test_constructor_success_whenBothAtCap() public {
        // 边界：两档恰各 50‰ 允许
        PrizePoolBaseHarness edge =
            new PrizePoolBaseHarness(address(glc), address(vault), address(channels), owner, 50, 50);
        assertEq(edge.channelBenefitRate(), 50);
        assertEq(edge.sellBenefitRate(), 50);
    }

    // ---------------------------------------------------------------------
    // _colletWithCoin (GLC 路径)
    // ---------------------------------------------------------------------

    function test_colletWithCoin_glcPath_pullsScaledAmount() public {
        deal(address(glc), alice, 100e18);
        vm.prank(alice);
        glc.approve(address(h), 100e18);

        h.colletWithCoin(address(glc), alice, 100); // getAmount(100) = 100e18

        assertEq(glc.balanceOf(address(h)), 100e18);
        assertEq(glc.balanceOf(alice), 0);
    }

    function test_colletWithCoin_revert_whenAmountZero() public {
        vm.expectRevert(abi.encodeWithSelector(IErrorsBase.ErrorInvalidAmount.selector, 0));
        h.colletWithCoin(address(glc), alice, 0);
    }

    function test_colletWithCoin_permit_revert_whenAmountZero() public {
        // permit 重载的零额守卫（与直接版独立的一条分支）
        vm.expectRevert(abi.encodeWithSelector(IErrorsBase.ErrorInvalidAmount.selector, 0));
        h.colletWithCoin(address(glc), alice, 0, futureDeadline(), 0, bytes32(0), bytes32(0));
    }

    function test_colletWithCoin_externalTokenPath_mintsGlc() public {
        // token != GLC → 走 coin.mint(token, amount, payer)：拉 payer 的底层 usdc、铸 GLC 给 harness
        usdc.mint(alice, 100e6);
        vm.prank(alice);
        usdc.approve(address(glc), 100e6);

        h.colletWithCoin(address(usdc), alice, 100);

        assertEq(usdc.balanceOf(address(glc)), 100e6);
        assertEq(glc.balanceOf(address(h)), 100e18);
    }

    function test_colletWithCoin_permitGlcPath_permitsThenPulls() public {
        // GLC 路径 permit 重载：allowance 不足 → 先 permit 再 transferFrom
        (address payer, uint256 pk) = makeAddrAndKey("payer");
        deal(address(glc), payer, 100e18);
        uint256 dl = futureDeadline();
        (uint8 v, bytes32 r, bytes32 s) =
            signPermit(address(glc), pk, payer, address(h), 100e18, glc.nonces(payer), dl);

        h.colletWithCoin(address(glc), payer, 100, dl, v, r, s);

        assertEq(glc.balanceOf(address(h)), 100e18);
        assertEq(glc.balanceOf(payer), 0);
    }

    function test_colletWithCoin_permitExternalPath_mintsGlc() public {
        // 外币路径 permit 重载：coin.mint(token, amount, payer, deadline, v, r, s)
        (address payer, uint256 pk) = makeAddrAndKey("payer");
        usdc.mint(payer, 100e6);
        uint256 dl = futureDeadline();
        (uint8 v, bytes32 r, bytes32 s) =
            signPermit(address(usdc), pk, payer, address(glc), 100e6, usdc.nonces(payer), dl);

        h.colletWithCoin(address(usdc), payer, 100, dl, v, r, s);

        assertEq(usdc.balanceOf(address(glc)), 100e6);
        assertEq(glc.balanceOf(address(h)), 100e18);
    }

    // ---------------------------------------------------------------------
    // _transferTo
    // ---------------------------------------------------------------------

    function test_transferTo_success() public {
        deal(address(glc), address(h), 50e18);
        h.transferTo(ICoinBase(address(glc)), bob, 20e18);
        assertEq(glc.balanceOf(bob), 20e18);
        assertEq(glc.balanceOf(address(h)), 30e18);
    }

    function test_transferTo_zeroAmount_isNoop() public {
        h.transferTo(ICoinBase(address(glc)), bob, 0);
        assertEq(glc.balanceOf(bob), 0);
    }

    function test_transferTo_revert_whenInsufficientBalance() public {
        deal(address(glc), address(h), 10e18);
        vm.expectRevert(
            abi.encodeWithSelector(
                IErrorsBase.ErrorInsufficientBalance.selector, address(glc), address(h), 10e18, 20e18
            )
        );
        h.transferTo(ICoinBase(address(glc)), bob, 20e18);
    }

    function test_transferTo_revert_onFeeOnTransferToken() public {
        MockFeeOnTransferCoin fee = new MockFeeOnTransferCoin();
        fee.mintFor(address(h), 100e18);
        vm.expectRevert(IErrorsBase.ErrorPaymentUnsuccessful.selector);
        h.transferTo(ICoinBase(address(fee)), bob, 20e18);
    }

    function test_transferTo_revert_onSilentFailToken() public {
        MockSilentFailCoin sf = new MockSilentFailCoin();
        sf.mintFor(address(h), 100e18);
        vm.expectRevert(IErrorsBase.ErrorPaymentUnsuccessful.selector);
        h.transferTo(ICoinBase(address(sf)), bob, 20e18);
    }

    // ---------------------------------------------------------------------
    // 分润率计算与 pipeline
    // ---------------------------------------------------------------------

    function test_getBenefitByRate() public view {
        (uint256 benefit, uint256 after_) = h.getBenefitByRate(1000e18, 30);
        assertEq(benefit, 30e18);
        assertEq(after_, 970e18);
    }

    function testFuzz_getBenefitByRate(uint256 origin, uint16 rate) public view {
        origin = bound(origin, 0, 1e30);
        rate = uint16(bound(rate, 0, 1000));
        (uint256 benefit, uint256 after_) = h.getBenefitByRate(origin, rate);
        assertEq(benefit, origin * rate / 1000);
        assertEq(benefit + after_, origin);
    }

    function test_distribute_withChannel_splitsChannelAndVault() public {
        uint256 vaultBefore = glc.balanceOf(address(vault));
        deal(address(glc), address(h), 1000e18);
        uint256 net = h.distributeChannelAndSalesBenefits(ICoinBase(address(glc)), 1000e18, 1);
        // channel 3% = 30e18 → 转入 SalesChannel 合约并记账（非渠道 EOA）；sell 5% = 50e18 → 销售金库
        assertEq(glc.balanceOf(address(channels)), 30e18);
        assertEq(channels.pendingOf(1), 30e18);
        assertEq(channels.accruedOf(1), 30e18);
        assertEq(channels.totalAccrued(), 30e18);
        assertEq(glc.balanceOf(channelAddr), 0); // 渠道 EOA 不再直接收款
        assertEq(glc.balanceOf(address(vault)), vaultBefore + 50e18);
        assertEq(net, 920e18);
    }

    function test_distribute_withoutChannel_allBenefitToVault() public {
        uint256 vaultBefore = glc.balanceOf(address(vault));
        deal(address(glc), address(h), 1000e18);
        uint256 net = h.distributeChannelAndSalesBenefits(ICoinBase(address(glc)), 1000e18, 0);
        // channel(30e18) + sell(50e18) 全进销售金库；SalesChannel 不收款不记账
        assertEq(glc.balanceOf(address(vault)), vaultBefore + 80e18);
        assertEq(glc.balanceOf(address(channels)), 0);
        assertEq(channels.totalAccrued(), 0);
        assertEq(glc.balanceOf(channelAddr), 0);
        assertEq(net, 920e18);
    }

    function test_channelBenefitTransfer_transfersToSalesChannelAndCredits() public {
        deal(address(glc), address(h), 1000e18);
        h.channelBenefitTransfer(ICoinBase(address(glc)), 10e18, 1);
        assertEq(glc.balanceOf(address(channels)), 10e18);
        assertEq(channels.pendingOf(1), 10e18);
        assertEq(glc.balanceOf(channelAddr), 0);
    }

    function test_channelBenefitTransfer_zeroBenefit_earlyReturns() public {
        deal(address(glc), address(h), 1000e18);
        h.channelBenefitTransfer(ICoinBase(address(glc)), 0, 1);
        // 不转账、不记账、不 revert
        assertEq(glc.balanceOf(address(channels)), 0);
        assertEq(channels.pendingOf(1), 0);
        assertEq(channels.totalAccrued(), 0);
    }

    function test_channelBenefitTransfer_revert_whenChannelInvalid() public {
        deal(address(glc), address(h), 1000e18);
        vm.expectRevert(abi.encodeWithSelector(ISalesChannel.SalesChannelInvalid.selector, address(0)));
        h.channelBenefitTransfer(ICoinBase(address(glc)), 10e18, 999);
    }

    // ---------------------------------------------------------------------
    // 兜底记账：recordPendingPayout / claimPayout / softPay / 自调用守卫
    // ---------------------------------------------------------------------

    function test_recordPendingPayout_tracksAndEmits() public {
        vm.expectEmit(true, true, false, true, address(h));
        emit IPrizePoolBase.PayoutPending(alice, address(glc), 5e18);
        h.recordPendingPayout(alice, 5e18);
        assertEq(h.pendingPayoutOf(alice), 5e18);
        assertEq(h.pendingPayoutTotal(), 5e18);
    }

    function test_claimPayout_success() public {
        h.recordPendingPayout(alice, 5e18);
        deal(address(glc), address(h), 5e18);

        vm.expectEmit(true, true, false, true, address(h));
        emit IPrizePoolBase.PayoutClaimed(alice, address(glc), 5e18);
        vm.prank(alice);
        h.claimPayout();

        assertEq(glc.balanceOf(alice), 5e18);
        assertEq(h.pendingPayoutOf(alice), 0);
        assertEq(h.pendingPayoutTotal(), 0);
    }

    function test_claimPayout_revert_whenNoPending() public {
        vm.prank(alice);
        vm.expectRevert(IPrizePoolBase.ErrorNoPendingPayout.selector);
        h.claimPayout();
    }

    function test_softPay_success_paysDirectly() public {
        deal(address(glc), address(h), 10e18);
        h.softPay(bob, 10e18);
        assertEq(glc.balanceOf(bob), 10e18);
        assertEq(h.pendingPayoutOf(bob), 0);
    }

    function test_softPay_fallsBackToPending_whenTransferFails() public {
        // harness GLC 余额不足 → push 失败 → 记 pending（永不 revert）
        h.softPay(bob, 10e18);
        assertEq(glc.balanceOf(bob), 0);
        assertEq(h.pendingPayoutOf(bob), 10e18);
        assertEq(h.pendingPayoutTotal(), 10e18);
    }

    function test_payoutTransfer_revert_whenNotSelfCall() public {
        vm.expectRevert(IPrizePoolBase.ErrorUnauthorizedSelfCall.selector);
        h._payoutTransfer(alice, 1e18);
    }

    // ---------------------------------------------------------------------
    // 治理：分润率 setter
    // ---------------------------------------------------------------------

    function test_setSellBenefitRate_success_emits() public {
        vm.expectEmit(false, false, false, true, address(h));
        emit IPrizePoolBase.SellBenefitRateChanged(40);
        vm.prank(owner);
        h.setSellBenefitRate(40);
        assertEq(h.sellBenefitRate(), 40);
    }

    function test_setSellBenefitRate_success_atMaxCap() public {
        uint16 cap = h.MAX_SELL_BENEFIT_RATE();
        vm.prank(owner);
        h.setSellBenefitRate(cap);
        assertEq(h.sellBenefitRate(), 50);
    }

    function test_setSellBenefitRate_revert_whenZero() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IErrorsBase.ErrorInvalidAmount.selector, 0));
        h.setSellBenefitRate(0);
    }

    function test_setSellBenefitRate_revert_whenAboveCap() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IPrizePoolBase.ErrorSellRateTooHigh.selector, 51, 50));
        h.setSellBenefitRate(51);
    }

    function test_setSellBenefitRate_revert_whenNotAdmin() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, ADMIN_ROLE)
        );
        h.setSellBenefitRate(40);
    }
}
