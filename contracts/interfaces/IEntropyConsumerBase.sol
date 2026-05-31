// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

interface IEntropyConsumerBase {
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
    error ErrorZeroAddress();
}
