// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.36;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import "../interfaces/ICoinBase.sol";
import "../interfaces/ISalesChannel.sol";
import "../interfaces/IPrizePoolBase.sol";

import "./AccessControlPartnerContract.sol";
import "./NoDelegateCall.sol";

/// @title PrizePoolBase
/// @notice Abstract prize-pool base: composable internal helpers for prize-pool collection (direct GLC transfer /
///         foreign-token mint / EIP-2612 permit), benefit computation, and the two-stage channel + sales-vault
///         distribution pipeline, plus the sell benefit-rate governance setter. Downstreams inherit via
///         `is PrizePoolBase` and compose the helpers as needed.
/// @dev    Implements `IPrizePoolBase`. Helpers are all internal; the setter is external and guarded by
///         `DEFAULT_ADMIN_ROLE`. The channel benefit rate is fixed at construction with no setter (its initial
///         value is capped by `MAX_CHANNEL_BENEFIT_RATE`, 5% = 50 per-mille); the sell benefit rate is adjustable
///         via `setSellBenefitRate`, with both the constructor initial value and the setter capped by
///         `MAX_SELL_BENEFIT_RATE` (5% = 50 per-mille). Rates use denominator 1000; amounts are in wei of GLC.
abstract contract PrizePoolBase is AccessControlPartnerContract, NoDelegateCall, ReentrancyGuard, IPrizePoolBase {
    using SafeERC20 for ICoinBase;

    // 资产币地址（GLC）
    address public immutable GreatLottoCoinAddress;
    // 销售利润金库（ERC4626，销售分润经 transfer 入库自动按份额增值）
    address public immutable SalesVaultAddress;
    // SalesChannel 注册表
    address public immutable SalesChannelAddress;

    // 渠道分润率硬上限（千分比）：5% = 50‰。构造期 initialChannelRate 不得超过此值。
    uint16 public constant MAX_CHANNEL_BENEFIT_RATE = 50;

    // 销售分润率硬上限（千分比）：5% = 50‰。构造期 initialSellRate 与 setSellBenefitRate 均不得超过此值。
    uint16 public constant MAX_SELL_BENEFIT_RATE = 50;

    // 渠道分润率（千分比）；构造期固定、无运行时 setter（治理面收敛、增强渠道方信任）。
    // public getter 实现 IPrizePoolBase.channelBenefitRate()。
    uint16 public override channelBenefitRate;

    // 销售分润率（千分比）；public getter 实现 IPrizePoolBase.sellBenefitRate()。可经 setSellBenefitRate 调整，受 MAX_SELL_BENEFIT_RATE 上限约束。
    uint16 public override sellBenefitRate;

    // 付奖兜底：push 付款（如 callback 内付奖、债务清偿）失败时按 user 记账，转 pull 模式，
    // 避免整笔交易 / entropy 回调 revert。资产币为单一 GLC，故仅记金额。
    mapping(address user => uint256) private _pendingPayouts;

    // 兜底欠款聚合：恒等于 Σ _pendingPayouts[user]，即「当前滞留合约内、尚未被 claim 的兜底欠款总额」。
    // 仅在 _recordPendingPayout 自增、claimPayout 自减两处维护；供下游（如 GreatLottoCore）把滞留
    // 兜底资金纳入余额不变量。
    uint256 private _pendingPayoutTotal;

    constructor(
        address coin,
        address salesVaultAddr,
        address salesChannelAddr,
        address owner_,
        uint16 initialChannelRate,
        uint16 initialSellRate
    )
    AccessControlPartnerContract(owner_)
    {
        // 构造初值各自受硬上限约束：渠道率部署后不可改（无 setter），故必须在构造期就卡死；
        // 销售率复用 setSellBenefitRate 的同一上限 MAX_SELL_BENEFIT_RATE，保证构造初值与运行时
        // setter 口径一致。两档各 <= 50‰ ⇒ 之和 <= 100‰ << 1000，_distributeChannelAndSalesBenefits
        // 绝不 underflow。下游若另有分润档（如 investor），其与本两档之和 <= 1000 由下游自行保证。
        if (initialChannelRate > MAX_CHANNEL_BENEFIT_RATE) {
            revert ErrorChannelRateTooHigh(initialChannelRate, MAX_CHANNEL_BENEFIT_RATE);
        }
        if (initialSellRate > MAX_SELL_BENEFIT_RATE) {
            revert ErrorSellRateTooHigh(initialSellRate, MAX_SELL_BENEFIT_RATE);
        }
        GreatLottoCoinAddress = coin;
        SalesVaultAddress = salesVaultAddr;
        SalesChannelAddress = salesChannelAddr;
        channelBenefitRate = initialChannelRate;
        sellBenefitRate = initialSellRate;
    }

    function _getCoin() internal view returns (ICoinBase coin) {
        coin = ICoinBase(GreatLottoCoinAddress);
    }

    /// @notice Collect payment (direct version).
    /// @dev    GLC path: `getAmount` + `safeTransferFrom`; foreign-token path: `coin.mint`.
    function _colletWithCoin(address token, address payer, uint amount) internal returns (ICoinBase coin) {
        if (amount == 0) {
            revert ErrorInvalidAmount(0);
        }
        coin = _getCoin();

        if (token == GreatLottoCoinAddress) {
            uint underlyingAmount = coin.getAmount(amount);
            coin.safeTransferFrom(payer, address(this), underlyingAmount);
        } else {
            coin.mint(token, amount, payer);
        }
    }

    /// @notice Collect payment (permit version).
    /// @dev    GLC path: if allowance is insufficient, `permit` first, then `safeTransferFrom`; foreign-token
    ///         path: `coin.mint` (permit overload).
    function _colletWithCoin(
        address token,
        address payer,
        uint amount,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) internal returns (ICoinBase coin) {
        if (amount == 0) {
            revert ErrorInvalidAmount(0);
        }
        coin = _getCoin();

        if (token == GreatLottoCoinAddress) {
            uint underlyingAmount = coin.getAmount(amount);
            if (coin.allowance(payer, address(this)) < underlyingAmount) {
                coin.permit(payer, address(this), underlyingAmount, deadline, v, r, s);
            }
            coin.safeTransferFrom(payer, address(this), underlyingAmount);
        } else {
            coin.mint(token, amount, payer, deadline, v, r, s);
        }
    }

    /// @notice Strict-invariant transfer. Early-returns when `amount == 0`; pre-check of balance; post-check with
    ///         strict equality that simultaneously catches silent-fail tokens (transfer returns true but does not
    ///         debit) and fee-on-transfer tokens (over-charge).
    function _transferTo(ICoinBase coin, address recipient, uint amount) internal {
        if (amount == 0) return;

        uint _balance = coin.balanceOf(address(this));
        if (_balance < amount) {
            revert ErrorInsufficientBalance(address(coin), address(this), _balance, amount);
        }
        coin.safeTransfer(recipient, amount);
        if (coin.balanceOf(address(this)) != _balance - amount) {
            revert ErrorPaymentUnsuccessful();
        }
    }

    /// @notice Payout fallback: record a debt per user when a push payment fails (switch to pull mode).
    /// @dev    internal; called by subclasses in the try/catch failure branch of a payout to avoid reverting the
    ///         whole callback / transaction.
    function _recordPendingPayout(address user, uint256 amount) internal {
        _pendingPayouts[user] += amount;
        _pendingPayoutTotal += amount;
        emit PayoutPending(user, GreatLottoCoinAddress, amount);
    }

    /// @notice Self-call-only strict payout transfer used to isolate the soft-payment rollback boundary.
    /// @dev    Intended ONLY for `_softPay` to invoke via `this._payoutTransfer(...)` — creating a separate
    ///         message-call frame so its revert only rolls back this frame's transfer, not the caller's ledger
    ///         decrement written before `_softPay`, guaranteeing "debit the ledger once + record the fallback
    ///         once" with no double accounting. MUST NOT be called directly (external or internal) — guarded by
    ///         `msg.sender == address(this)` (reverts `ErrorUnauthorizedSelfCall`); and MUST NOT be rewritten as
    ///         internal, otherwise it shares the same frame, frame isolation is lost, and the double-accounting
    ///         correction no longer holds.
    /// @param  to     Recipient of the payout.
    /// @param  amount Amount to transfer, in wei (GLC).
    function _payoutTransfer(address to, uint256 amount) external {
        if (msg.sender != address(this)) revert ErrorUnauthorizedSelfCall();
        _transferTo(_getCoin(), to, amount);
    }

    /// @notice Soft payment: on push-transfer failure, fall back to `pendingPayout`; never reverts (callback-safe).
    /// @dev    Calls `_payoutTransfer` via a separate frame; any transfer failure (recipient revert / token
    ///         blacklist / insufficient balance / post-check failure) is caught, funds stay in the contract and
    ///         switch to pull fallback. The caller MUST complete its own ledger decrement BEFORE calling this
    ///         helper (CEI), so "debit the ledger once + record the fallback once" still balances on push failure.
    ///         When `amount == 0`, `_transferTo` early-returns, is treated as success, and records no fallback.
    function _softPay(address to, uint256 amount) internal {
        try this._payoutTransfer(to, amount) {
            // 已付
        } catch {
            _recordPendingPayout(to, amount);
        }
    }

    /// @inheritdoc IPrizePoolBase
    /// @dev pull payment; CEI zeroes the ledger before transferring; `noDelegateCall` prevents tampering with the
    ///      accounting context via delegatecall; `nonReentrant` is defense-in-depth so safety no longer relies
    ///      solely on GLC having no transfer hook.
    function claimPayout() external noDelegateCall nonReentrant {
        uint256 amount = _pendingPayouts[msg.sender];
        if (amount == 0) revert ErrorNoPendingPayout();
        _pendingPayouts[msg.sender] = 0;
        _pendingPayoutTotal -= amount;
        _transferTo(_getCoin(), msg.sender, amount);
        emit PayoutClaimed(msg.sender, GreatLottoCoinAddress, amount);
    }

    /// @inheritdoc IPrizePoolBase
    function pendingPayoutOf(address user) external view returns (uint256) {
        return _pendingPayouts[user];
    }

    /// @notice The total fallback debt currently held in the contract and not yet claimed (= Σ pendingPayoutOf(user)).
    /// @dev    Lets downstreams include funds stranded by failed soft payments in their balance invariants (e.g.
    ///         GreatLottoCore's solvency check).
    /// @return The total pending payout amount in wei (GLC).
    function pendingPayoutTotal() public view returns (uint256) {
        return _pendingPayoutTotal;
    }

    /// @notice Pay benefit to a specific channel; reverts when the id does not exist (chn == address(0)).
    /// @dev    The recipient is the SalesChannel contract (not the channel EOA): transfer an equal `benefit` into
    ///         SalesChannel first, then call `creditChannel` to record it per `chnId`; the channel withdraws it
    ///         itself via `SalesChannel.withdraw` (pull payment). Transfer and credit amounts are equal, in the
    ///         order "transfer before credit" — the precondition of SalesChannel's solvency invariant.
    ///         Early-returns when `benefit == 0` (no transfer, no credit).
    function _channelBenefitTransfer(ICoinBase coin, uint256 benefit, uint256 chnId) internal {
        (address chn, ) = ISalesChannel(SalesChannelAddress).getChannelById(chnId);
        if (chn == address(0)) {
            revert ISalesChannel.SalesChannelInvalid(chn);
        }
        if (benefit == 0) return;
        _transferTo(coin, SalesChannelAddress, benefit);
        ISalesChannel(SalesChannelAddress).creditChannel(chnId, benefit);
    }

    /// @notice Pay into the sales-profit vault (semantic sugar); this transfer raises the vault's `totalAssets`
    ///         without touching `totalSupply`.
    function _salesVaultTransfer(ICoinBase coin, uint256 benefit) internal {
        _transferTo(coin, SalesVaultAddress, benefit);
    }

    /// @notice Benefit computation (per-mille, denominator 1000).
    function _getBenefitByRate(uint originAmount, uint16 benefitRate) internal pure returns (uint benefit, uint afterAmount) {
        benefit = originAmount * benefitRate / 1000;
        afterAmount = originAmount - benefit;
    }

    /// @notice Two-stage channel + sales-vault distribution pipeline.
    /// @param  coin         GLC `ICoinBase` reference (returned by the caller's `_getCoin` or `_colletWithCoin`).
    /// @param  amountByCoin The base amount used to compute benefits (denominated in GLC).
    /// @param  channelId    When > 0, pay the channel separately (channel + sell -> vault); when == 0, merge into
    ///                      the vault (both channel and sell go to the vault).
    /// @return netAmount    `amountByCoin - channelBenefit - sellBenefit`; the caller decides where the net goes.
    /// @dev    The caller must ensure the contract's GLC balance covers the total benefit due; otherwise
    ///         `_transferTo` reverts `ErrorInsufficientBalance`. This helper emits no dedicated event; off-chain
    ///         consumers infer it from the ERC20 Transfer events.
    function _distributeChannelAndSalesBenefits(
        ICoinBase coin,
        uint amountByCoin,
        uint256 channelId
    ) internal returns (uint netAmount) {
        (uint channelBenefit, ) = _getBenefitByRate(amountByCoin, channelBenefitRate);
        (uint sellBenefit, ) = _getBenefitByRate(amountByCoin, sellBenefitRate);

        uint salesBenefit;
        if (channelId > 0) {
            _channelBenefitTransfer(coin, channelBenefit, channelId);
            salesBenefit = sellBenefit;
        } else {
            salesBenefit = sellBenefit + channelBenefit;
        }

        if (salesBenefit > 0) {
            _salesVaultTransfer(coin, salesBenefit);
        }

        netAmount = amountByCoin - channelBenefit - sellBenefit;
    }

    /// @inheritdoc IPrizePoolBase
    /// @dev The channel benefit rate is fixed at construction with no setter; the sell benefit rate is adjustable
    ///      but capped by `MAX_SELL_BENEFIT_RATE` (5% = 50 per-mille), and a zero rate reverts `ErrorInvalidAmount(0)`.
    function setSellBenefitRate(uint16 rate) external virtual onlyRole(DEFAULT_ADMIN_ROLE) returns (bool) {
        if (rate == 0) {
            revert ErrorInvalidAmount(0);
        }
        if (rate > MAX_SELL_BENEFIT_RATE) {
            revert ErrorSellRateTooHigh(rate, MAX_SELL_BENEFIT_RATE);
        }
        sellBenefitRate = rate;
        emit SellBenefitRateChanged(rate);
        return true;
    }

}
