// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {IErrorsBase} from "./IErrorsBase.sol";

/// @title IEntropyConsumerBase
/// @notice Contract interface for the asynchronous Pyth Entropy V2 consumer base: request/retry a random draw,
///         read a pending request, and govern the entropy provider / callback gas / timeout parameters.
/// @dev    Randomness is delivered in two phases (request then provider callback). Amounts paid for entropy are
///         in wei (native gas token); timeouts and deadlines are unix timestamps / durations in seconds.
interface IEntropyConsumerBase is IErrorsBase {
    struct Request {
        uint256 tokenId;
        address requester;
        uint64  requestedAt;
        uint32  itemCount;
        uint128 paidFee;
        bool    exists;
    }

    event RequestSubmitted(
        uint64  indexed sequenceNumber,
        address indexed requester,
        uint256 indexed tokenId,
        uint32 itemCount,
        uint128 paidFee
    );
    event RequestFulfilled(
        uint64  indexed sequenceNumber,
        address indexed requester,
        uint256 indexed tokenId
    );
    event RequestRetried(
        uint64  indexed oldSequenceNumber,
        uint64  indexed newSequenceNumber,
        address indexed requester,
        uint128 oldFee,
        uint128 newFee
    );
    event EntropyProviderChanged(address oldProvider, address newProvider);
    event CallbackGasLimitChanged(uint32 oldLimit, uint32 newLimit);
    event EntropyTimeoutChanged(uint64 oldTimeout, uint64 newTimeout);

    error ErrorInvalidUserRandom();
    error ErrorInsufficientEntropyFee(uint256 needed, uint256 paid);
    error ErrorRequestNotFound();
    error ErrorNotRequester();
    error ErrorRetryNotAllowed();
    error ErrorInvalidEntropyTimeout();
    error ErrorInvalidCallbackGasLimit();
    error ErrorRefundFailed();

    /// @notice The current entropy fee (in wei), equal to `entropy.getFeeV2(provider, callbackGasLimit)`.
    /// @return The entropy fee in wei.
    function entropyFee() external view returns (uint256);

    /// @notice Read the request record for a given sequence number.
    /// @param  sequenceNumber The Pyth sequence number to look up.
    /// @return The stored `Request` (an empty struct with `exists == false` when not found).
    function getRequest(uint64 sequenceNumber) external view returns (Request memory);

    /// @notice Retry a timed-out or callback-failed randomness request by paying a fresh entropy fee.
    /// @dev    Only the original requester may retry, and only once the request has timed out or its Pyth
    ///         callback has failed; the old request record is deleted and replaced by the new one. Requires
    ///         `msg.value >= entropyFee()`; overpayment is refunded. `newUserRandomNumber` must be non-zero.
    /// @param  oldSequenceNumber   The sequence number of the stalled request being retried.
    /// @param  newUserRandomNumber A fresh non-zero user-supplied random seed for the new request.
    /// @param  deadline            Transaction deadline, a unix timestamp in seconds.
    /// @return newSequenceNumber The new Pyth sequence number.
    /// @return paidFee The entropy fee actually paid this time (in wei; matches `RequestRetried.newFee`).
    function retryRequest(
        uint64 oldSequenceNumber,
        bytes32 newUserRandomNumber,
        uint256 deadline
    ) external payable returns (uint64 newSequenceNumber, uint128 paidFee);

    /// @notice Governance: switch the entropy provider. Restricted to `DEFAULT_ADMIN_ROLE`.
    /// @param  newProvider The new entropy provider address (must be non-zero).
    function setEntropyProvider(address newProvider) external;

    /// @notice Governance: adjust the callback gas limit, within `[MIN_CALLBACK_GAS, MAX_CALLBACK_GAS]`.
    ///         Restricted to `DEFAULT_ADMIN_ROLE`.
    /// @param  newLimit The new callback gas limit.
    function setCallbackGasLimit(uint32 newLimit) external;

    /// @notice Governance: adjust the request timeout window (in seconds), within
    ///         `[MIN_ENTROPY_TIMEOUT, MAX_ENTROPY_TIMEOUT]`. Restricted to `DEFAULT_ADMIN_ROLE`.
    /// @param  newTimeout The new timeout in seconds.
    function setEntropyTimeout(uint64 newTimeout) external;
}
