// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {IErrorsBase} from "./IErrorsBase.sol";

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

    /// @notice 当前 entropy fee（= entropy.getFeeV2(provider, callbackGasLimit)）
    function entropyFee() external view returns (uint256);

    /// @notice 读取某个 sequenceNumber 的请求记录（不存在则 exists=false 的空结构）
    function getRequest(uint64 sequenceNumber) external view returns (Request memory);

    /// @notice 重新触发一个已超时 / 回调失败的随机请求；支付新的 entropy fee。
    /// @return newSequenceNumber 新的 Pyth sequenceNumber
    /// @return paidFee 本次实付的 entropy fee（与 RequestRetried.newFee 一致）
    function retryRequest(
        uint64 oldSequenceNumber,
        bytes32 newUserRandomNumber,
        uint256 deadline
    ) external payable returns (uint64 newSequenceNumber, uint128 paidFee);

    /// @notice 治理：切换 entropy provider（仅 DEFAULT_ADMIN_ROLE）
    function setEntropyProvider(address newProvider) external;

    /// @notice 治理：调整回调 gas 上限，范围 [MIN_CALLBACK_GAS, MAX_CALLBACK_GAS]（仅 DEFAULT_ADMIN_ROLE）
    function setCallbackGasLimit(uint32 newLimit) external;

    /// @notice 治理：调整请求超时窗口，范围 [MIN_ENTROPY_TIMEOUT, MAX_ENTROPY_TIMEOUT]（仅 DEFAULT_ADMIN_ROLE）
    function setEntropyTimeout(uint64 newTimeout) external;
}
