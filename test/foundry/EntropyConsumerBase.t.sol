// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {BaseTest} from "./base/BaseTest.sol";
import {MockEntropyWithFee} from "./mocks/MockEntropyWithFee.sol";
import {MockEntropyConsumer} from "./harness/MockEntropyConsumer.sol";
import {DefaultHooksEntropyConsumer} from "./harness/DefaultHooksEntropyConsumer.sol";
import {IEntropyConsumerBase} from "../../contracts/interfaces/IEntropyConsumerBase.sol";
import {IErrorsBase} from "../../contracts/interfaces/IErrorsBase.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

/// @dev 拒收 ETH，用于触发退款失败分支。
contract EthRejecter {
    receive() external payable {
        revert("reject");
    }
}

/// @title EntropyConsumerBaseTest
/// @notice 经 MockEntropyConsumer 全覆盖 EntropyConsumerBase：部署默认值、请求（含退款/退款失败）、
///         回调（成功 / 晚到幂等 / fulfill revert）、重试（4 类前置守卫 + 超时/回调失败两条放行 + 退款）、
///         三个治理 setter（边界 + 权限）。含 fuzz。
contract EntropyConsumerBaseTest is BaseTest {
    MockEntropyWithFee internal entropy;
    MockEntropyConsumer internal consumer;

    address internal provider = makeAddr("provider");
    uint128 internal constant FEE = 100;
    bytes32 internal constant ADMIN_ROLE = 0x00;
    bytes32 internal constant RAND = bytes32(uint256(0x1111));
    bytes32 internal constant RAND2 = bytes32(uint256(0x2222));

    function setUp() public {
        entropy = new MockEntropyWithFee(provider, FEE);
        consumer = new MockEntropyConsumer(address(entropy), provider, owner);
        vm.deal(address(this), 1000 ether);
    }

    function _request(uint256 tokenId, address requester, uint32 itemCount, bytes32 rand, uint256 paid)
        internal
        returns (uint64 seq)
    {
        (seq,) = consumer.requestRandomness{value: paid}(tokenId, requester, itemCount, rand);
    }

    // ---------------------------------------------------------------------
    // 部署默认值 / 构造守卫
    // ---------------------------------------------------------------------

    function test_deployment_defaults() public view {
        assertEq(address(consumer.entropy()), address(entropy));
        assertEq(consumer.entropyProvider(), provider);
        assertEq(consumer.callbackGasLimit(), 2_500_000);
        assertEq(consumer.entropyTimeout(), 3600);
        assertEq(consumer.entropyFee(), FEE);
        assertTrue(consumer.hasRole(ADMIN_ROLE, owner));
    }

    function test_constructor_revert_onZeroEntropy() public {
        vm.expectRevert(IErrorsBase.ErrorZeroAddress.selector);
        new MockEntropyConsumer(address(0), provider, owner);
    }

    function test_constructor_revert_onZeroProvider() public {
        vm.expectRevert(IErrorsBase.ErrorZeroAddress.selector);
        new MockEntropyConsumer(address(entropy), address(0), owner);
    }

    function test_getRequest_unknownSeq_empty() public view {
        IEntropyConsumerBase.Request memory r = consumer.getRequest(999);
        assertFalse(r.exists);
        assertEq(r.tokenId, 0);
    }

    // ---------------------------------------------------------------------
    // requestRandomness
    // ---------------------------------------------------------------------

    function test_request_revert_whenUserRandomZero() public {
        vm.expectRevert(IEntropyConsumerBase.ErrorInvalidUserRandom.selector);
        consumer.requestRandomness{value: FEE}(1, alice, 1, bytes32(0));
    }

    function test_request_revert_whenInsufficientFee() public {
        vm.expectRevert(abi.encodeWithSelector(IEntropyConsumerBase.ErrorInsufficientEntropyFee.selector, FEE, 1));
        consumer.requestRandomness{value: 1}(1, alice, 1, RAND);
    }

    function test_request_success_storesAndEmits() public {
        vm.expectEmit(true, true, true, true, address(consumer));
        emit IEntropyConsumerBase.RequestSubmitted(1, alice, 7, 3, FEE);
        (uint64 seq, uint128 paidFee) = consumer.requestRandomness{value: FEE}(7, alice, 3, RAND);

        assertEq(seq, 1);
        assertEq(paidFee, FEE);
        IEntropyConsumerBase.Request memory r = consumer.getRequest(seq);
        assertTrue(r.exists);
        assertEq(r.tokenId, 7);
        assertEq(r.requester, alice);
        assertEq(r.itemCount, 3);
        assertEq(r.paidFee, FEE);
    }

    function test_request_refundsExcess() public {
        uint256 before = alice.balance;
        _request(1, alice, 1, RAND, FEE + 50);
        assertEq(alice.balance, before + 50);
    }

    function test_request_revert_whenRefundRejected() public {
        EthRejecter rej = new EthRejecter();
        vm.expectRevert(IEntropyConsumerBase.ErrorRefundFailed.selector);
        consumer.requestRandomness{value: FEE + 50}(1, address(rej), 1, RAND);
    }

    // ---------------------------------------------------------------------
    // callback
    // ---------------------------------------------------------------------

    function test_callback_success_fulfillsAndDeletes() public {
        uint64 seq = _request(42, alice, 5, RAND, FEE);

        vm.expectEmit(true, true, true, false, address(consumer));
        emit IEntropyConsumerBase.RequestFulfilled(seq, alice, 42);
        entropy.mockReveal(address(consumer), seq, RAND2);

        assertEq(consumer.lastSequence(), seq);
        assertEq(consumer.lastRandomNumber(), RAND2);
        assertEq(consumer.lastTokenId(), 42);
        assertEq(consumer.lastRequester(), alice);
        assertEq(consumer.lastItemCount(), 5);
        // 请求已删除
        assertFalse(consumer.getRequest(seq).exists);
    }

    function test_callback_unknownSeq_silentReturn() public {
        // 从未请求的 seq → 基类 !exists 静默 return，不写状态、不 revert
        entropy.mockForceCallback(address(consumer), 12345, RAND2);
        assertEq(consumer.lastSequence(), 0);
    }

    function test_callback_revertsWhenFulfillReverts() public {
        uint64 seq = _request(1, alice, 1, RAND, FEE);
        consumer.setRevertOnFulfill(true);
        vm.expectRevert(bytes("fulfill-revert"));
        entropy.mockReveal(address(consumer), seq, RAND2);
    }

    // ---------------------------------------------------------------------
    // retryRequest — 前置守卫
    // ---------------------------------------------------------------------

    function test_retry_revert_whenNotFound() public {
        vm.prank(alice);
        vm.expectRevert(IEntropyConsumerBase.ErrorRequestNotFound.selector);
        consumer.retryRequest(999, RAND2, futureDeadline());
    }

    function test_retry_revert_whenNotRequester() public {
        uint64 seq = _request(1, alice, 1, RAND, FEE);
        vm.prank(bob);
        vm.expectRevert(IEntropyConsumerBase.ErrorNotRequester.selector);
        consumer.retryRequest(seq, RAND2, futureDeadline());
    }

    function test_retry_revert_whenNewRandomZero() public {
        uint64 seq = _request(1, alice, 1, RAND, FEE);
        vm.prank(alice);
        vm.expectRevert(IEntropyConsumerBase.ErrorInvalidUserRandom.selector);
        consumer.retryRequest(seq, bytes32(0), futureDeadline());
    }

    function test_retry_revert_whenInFlightNotAllowed() public {
        uint64 seq = _request(1, alice, 1, RAND, FEE);
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(IEntropyConsumerBase.ErrorRetryNotAllowed.selector);
        consumer.retryRequest{value: FEE}(seq, RAND2, futureDeadline());
    }

    // ---------------------------------------------------------------------
    // retryRequest — 放行（超时 / 回调失败）+ 退款
    // ---------------------------------------------------------------------

    function test_retry_success_afterTimeout() public {
        uint64 seq = _request(9, alice, 2, RAND, FEE);
        // 推过超时窗口
        vm.warp(block.timestamp + consumer.entropyTimeout());

        vm.deal(alice, 1 ether);
        uint256 before = alice.balance;

        vm.expectEmit(true, true, true, true, address(consumer));
        emit IEntropyConsumerBase.RequestRetried(seq, 2, alice, FEE, FEE);
        vm.prank(alice);
        (uint64 newSeq, uint128 paidFee) = consumer.retryRequest{value: FEE + 30}(seq, RAND2, futureDeadline());

        assertEq(newSeq, 2);
        assertEq(paidFee, FEE); // 返回的就是本次实付 entropy fee
        assertFalse(consumer.getRequest(seq).exists);
        IEntropyConsumerBase.Request memory r = consumer.getRequest(newSeq);
        assertTrue(r.exists);
        assertEq(r.tokenId, 9);
        assertEq(r.requester, alice);
        assertEq(r.itemCount, 2);
        // 退还多付的 30
        assertEq(alice.balance, before - FEE);
    }

    function test_retry_success_afterCallbackFailed() public {
        uint64 seq = _request(1, alice, 1, RAND, FEE);
        entropy.markCallbackFailed(seq); // 未超时但 Pyth 标记回调失败 → 放行

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (uint64 newSeq, uint128 paidFee) = consumer.retryRequest{value: FEE}(seq, RAND2, futureDeadline());
        assertEq(newSeq, 2);
        assertEq(paidFee, FEE);
        assertTrue(consumer.getRequest(newSeq).exists);
    }

    function test_retry_revert_whenInsufficientFee() public {
        uint64 seq = _request(1, alice, 1, RAND, FEE);
        vm.warp(block.timestamp + consumer.entropyTimeout());
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IEntropyConsumerBase.ErrorInsufficientEntropyFee.selector, FEE, 1));
        consumer.retryRequest{value: 1}(seq, RAND2, futureDeadline());
    }

    // ---------------------------------------------------------------------
    // 治理 setter
    // ---------------------------------------------------------------------

    function test_setEntropyProvider_success_emits() public {
        address np = makeAddr("np");
        vm.expectEmit(false, false, false, true, address(consumer));
        emit IEntropyConsumerBase.EntropyProviderChanged(provider, np);
        vm.prank(owner);
        consumer.setEntropyProvider(np);
        assertEq(consumer.entropyProvider(), np);
    }

    function test_setEntropyProvider_revert_whenZero() public {
        vm.prank(owner);
        vm.expectRevert(IErrorsBase.ErrorZeroAddress.selector);
        consumer.setEntropyProvider(address(0));
    }

    function test_setEntropyProvider_revert_whenNotAdmin() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, alice, ADMIN_ROLE)
        );
        consumer.setEntropyProvider(alice);
    }

    function test_setCallbackGasLimit_success() public {
        vm.prank(owner);
        consumer.setCallbackGasLimit(750_000);
        assertEq(consumer.callbackGasLimit(), 750_000);
    }

    function test_setCallbackGasLimit_success_atNewMax() public {
        // 上限已抬至 MAX_CALLBACK_GAS = 5_000_000，顶满边界应成功
        vm.prank(owner);
        consumer.setCallbackGasLimit(5_000_000);
        assertEq(consumer.callbackGasLimit(), 5_000_000);
    }

    function test_setCallbackGasLimit_revert_belowMin() public {
        vm.prank(owner);
        vm.expectRevert(IEntropyConsumerBase.ErrorInvalidCallbackGasLimit.selector);
        consumer.setCallbackGasLimit(99_999);
    }

    function test_setCallbackGasLimit_revert_aboveMax() public {
        // 2_000_001 在旧上限(2M)外、新上限(5M)内 → 不再 revert；改用越过新上限的值
        vm.prank(owner);
        vm.expectRevert(IEntropyConsumerBase.ErrorInvalidCallbackGasLimit.selector);
        consumer.setCallbackGasLimit(5_000_001);
    }

    function test_setEntropyTimeout_success() public {
        vm.prank(owner);
        consumer.setEntropyTimeout(2 hours);
        assertEq(consumer.entropyTimeout(), 2 hours);
    }

    function test_setEntropyTimeout_revert_belowMin() public {
        vm.prank(owner);
        vm.expectRevert(IEntropyConsumerBase.ErrorInvalidEntropyTimeout.selector);
        consumer.setEntropyTimeout(59);
    }

    function test_setEntropyTimeout_revert_aboveMax() public {
        vm.prank(owner);
        vm.expectRevert(IEntropyConsumerBase.ErrorInvalidEntropyTimeout.selector);
        consumer.setEntropyTimeout(uint64(24 hours) + 1);
    }

    // ---------------------------------------------------------------------
    // 基类默认 hook 体（子类不 override _postRequest/_beforeRetry/_postRetry）
    // ---------------------------------------------------------------------

    /// @dev 用一个仅实现强制 hook、其余 hook 走基类空默认实现的子类，驱动 request→callback→retry
    ///      全链路，覆盖 MockEntropyConsumer（全 override）触及不到的基类默认 hook 体。
    function test_defaultHooks_requestCallbackRetry_coversBaseHookBodies() public {
        DefaultHooksEntropyConsumer dh = new DefaultHooksEntropyConsumer(address(entropy), provider, owner);
        vm.deal(address(dh), 0);

        // request → 触发基类默认 _postRequest（空体）
        (uint64 seq,) = dh.requestRandomness{value: FEE}(1, alice, 1, RAND);
        assertTrue(dh.getRequest(seq).exists);

        // 超时后 retry → 触发基类默认 _beforeRetry + _postRetry（空体）
        vm.warp(block.timestamp + dh.entropyTimeout());
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        (uint64 newSeq, ) = dh.retryRequest{value: FEE}(seq, RAND2, futureDeadline());
        assertTrue(dh.getRequest(newSeq).exists);
        assertFalse(dh.getRequest(seq).exists);

        // callback → fulfill
        entropy.mockReveal(address(dh), newSeq, RAND2);
        assertEq(dh.lastSequence(), newSeq);
    }

    // ---------------------------------------------------------------------
    // fuzz
    // ---------------------------------------------------------------------

    function testFuzz_request_refundsExactExcess(uint96 excess, uint32 itemCount) public {
        uint256 paid = uint256(FEE) + excess;
        vm.deal(address(this), paid);
        uint256 before = alice.balance;
        (uint64 seq,) = consumer.requestRandomness{value: paid}(1, alice, itemCount, RAND);
        assertEq(alice.balance, before + excess);
        assertEq(consumer.getRequest(seq).itemCount, itemCount);
    }
}
