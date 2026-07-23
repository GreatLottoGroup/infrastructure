// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.36;

/// @title IPrizePoolBase
/// @notice Contract interface for the prize-pool base: pull-based payout fallback (claim / query) and
///         benefit-rate governance (sell rate setter + read-only channel / sell rate getters).
/// @dev    All amounts are in wei of the settlement currency GLC. Benefit rates are expressed in per-mille
///         (denominator 1000); both the channel rate and sell rate are capped at 5% (= 50 per-mille).
interface IPrizePoolBase {

    /// @notice Emitted when the sell benefit rate is changed via `setSellBenefitRate`.
    event SellBenefitRateChanged(uint16 rate);

    /// @notice Payout fallback: a push payment failed and was recorded for pull withdrawal. `coin` is always GLC.
    event PayoutPending(address indexed user, address indexed coin, uint256 amount);
    /// @notice Payout fallback: a previously-pending payout was claimed by the user. `coin` is always GLC.
    event PayoutClaimed(address indexed user, address indexed coin, uint256 amount);

    /// @dev Reverts when `claimPayout` is called but the user has no pending fallback payout.
    error ErrorNoPendingPayout();

    /// @dev Reverts when `_payoutTransfer` is not invoked via the contract's own `this.` self-call
    ///      (the soft-payment frame-isolation guard).
    error ErrorUnauthorizedSelfCall();

    /// @dev Reverts when a sell rate (constructor initial value or `setSellBenefitRate` input) exceeds the
    ///      hard cap `MAX_SELL_BENEFIT_RATE` (5% = 50 per-mille).
    error ErrorSellRateTooHigh(uint16 rate, uint16 max);

    /// @dev Reverts when the constructor `initialChannelRate` exceeds the hard cap `MAX_CHANNEL_BENEFIT_RATE`
    ///      (5% = 50 per-mille). The channel rate is immutable after deployment (no setter), so it is only
    ///      validated at construction time.
    error ErrorChannelRateTooHigh(uint16 rate, uint16 max);

    /// @notice Governance: set the sell benefit rate. Restricted to `DEFAULT_ADMIN_ROLE`.
    /// @dev    The channel rate is fixed at construction and has no setter; the sell rate is adjustable but
    ///         capped at `MAX_SELL_BENEFIT_RATE` (5% = 50 per-mille) — reverts `ErrorSellRateTooHigh` above it,
    ///         and `ErrorInvalidAmount(0)` for a zero rate.
    /// @param  rate The new sell benefit rate, in per-mille (denominator 1000).
    /// @return True on success.
    function setSellBenefitRate(uint16 rate) external returns (bool);

    /// @notice Withdraw the caller's fallback payout that was recorded when an earlier push payment failed (GLC).
    /// @dev    Pull payment; reverts `ErrorNoPendingPayout` when there is nothing to claim.
    function claimPayout() external;
    /// @notice Query the pending fallback payout amount for an address.
    /// @param  user The address to query.
    /// @return The pending payout amount in wei (GLC).
    function pendingPayoutOf(address user) external view returns (uint256);

    /// @notice The current channel benefit rate, in per-mille (denominator 1000). Fixed at construction.
    /// @return The channel benefit rate.
    function channelBenefitRate() external view returns (uint16);
    /// @notice The current sell benefit rate, in per-mille (denominator 1000). Adjustable via `setSellBenefitRate`.
    /// @return The sell benefit rate.
    function sellBenefitRate() external view returns (uint16);

}
