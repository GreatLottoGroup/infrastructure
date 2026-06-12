// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {BaseTest} from "./base/BaseTest.sol";
import {PrizePoolBaseHarness} from "./harness/PrizePoolBaseHarness.sol";
import {GreatLottoCoin} from "../../contracts/GreatLottoCoin.sol";
import {DaoCoin} from "../../contracts/DaoCoin.sol";
import {DaoBenefitPool} from "../../contracts/DaoBenefitPool.sol";
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
contract PrizePoolBaseTest is BaseTest {
    PrizePoolBaseHarness internal h;
    GreatLottoCoin internal glc;
    DaoCoin internal dao;
    DaoBenefitPool internal daoPool;
    SalesChannel internal channels;
    MockERC20Permit internal usdc;

    bytes32 internal constant PARTNER_ROLE = keccak256("PARTNER_CONTRACT_ROLE");
    bytes32 internal constant ADMIN_ROLE = 0x00;
    uint16 internal constant CH_RATE = 30; // 3%
    uint16 internal constant SELL_RATE = 70; // 7%

    address internal channelAddr = makeAddr("channelAddr");

    function setUp() public {
        usdc = new MockERC20Permit("USDC", "USDC", 6);
        address[] memory toks = new address[](1);
        toks[0] = address(usdc);

        glc = new GreatLottoCoin(toks, owner);
        dao = new DaoCoin(owner);
        daoPool = new DaoBenefitPool(address(glc), address(dao));
        channels = new SalesChannel(owner);
        h = new PrizePoolBaseHarness(
            address(glc), address(dao), address(daoPool), address(channels), owner, CH_RATE, SELL_RATE
        );

        // harness 需要 PARTNER 角色以 mint GLC / DaoCoin
        vm.startPrank(owner);
        glc.grantRole(PARTNER_ROLE, address(h));
        dao.grantRole(PARTNER_ROLE, address(h));
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
        assertEq(h.DaoCoinAddress(), address(dao));
        assertEq(h.DaoBenefitPoolAddress(), address(daoPool));
        assertEq(h.SalesChannelAddress(), address(channels));
        assertEq(h.channelBenefitRate(), CH_RATE);
        assertEq(h.sellBenefitRate(), SELL_RATE);
        assertEq(address(h.getCoin()), address(glc));
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

    function test_distribute_withChannel_splitsChannelAndDao() public {
        deal(address(glc), address(h), 1000e18);
        uint256 net = h.distributeChannelAndDaoBenefits(ICoinBase(address(glc)), 1000e18, 1);
        // channel 3% = 30e18, sell 7% = 70e18 → DAO
        assertEq(glc.balanceOf(channelAddr), 30e18);
        assertEq(glc.balanceOf(address(daoPool)), 70e18);
        assertEq(net, 900e18);
    }

    function test_distribute_withoutChannel_allBenefitToDao() public {
        deal(address(glc), address(h), 1000e18);
        uint256 net = h.distributeChannelAndDaoBenefits(ICoinBase(address(glc)), 1000e18, 0);
        // channel(30e18) + sell(70e18) 全进 DAO
        assertEq(glc.balanceOf(address(daoPool)), 100e18);
        assertEq(glc.balanceOf(channelAddr), 0);
        assertEq(net, 900e18);
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

    function test_mintDaoCoinToPayer() public {
        h.mintDaoCoinToPayer(alice, 1000e18);
        // price 1e18 → shares == assets
        assertEq(dao.balanceOf(alice), 1000e18);
    }

    // ---------------------------------------------------------------------
    // 治理：分润率 setter
    // ---------------------------------------------------------------------

    function test_setChannelBenefitRate_success_emits() public {
        vm.expectEmit(false, false, false, true, address(h));
        emit IPrizePoolBase.ChannelBenefitRateChanged(50);
        vm.prank(owner);
        h.setChannelBenefitRate(50);
        assertEq(h.channelBenefitRate(), 50);
    }

    function test_setSellBenefitRate_success_emits() public {
        vm.expectEmit(false, false, false, true, address(h));
        emit IPrizePoolBase.SellBenefitRateChanged(120);
        vm.prank(owner);
        h.setSellBenefitRate(120);
        assertEq(h.sellBenefitRate(), 120);
    }

    function test_setChannelBenefitRate_revert_whenZero() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IErrorsBase.ErrorInvalidAmount.selector, 0));
        h.setChannelBenefitRate(0);
    }

    function test_setSellBenefitRate_revert_whenZero() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IErrorsBase.ErrorInvalidAmount.selector, 0));
        h.setSellBenefitRate(0);
    }

    function test_setChannelBenefitRate_revert_whenNotAdmin() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, ADMIN_ROLE)
        );
        h.setChannelBenefitRate(50);
    }
}
