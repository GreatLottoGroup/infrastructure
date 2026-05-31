// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {IEntropyConsumer} from "@pythnetwork/entropy-sdk-solidity/IEntropyConsumer.sol";
import {IEntropyV2} from "@pythnetwork/entropy-sdk-solidity/IEntropyV2.sol";
import {EntropyStructsV2} from "@pythnetwork/entropy-sdk-solidity/EntropyStructsV2.sol";
import {EntropyStatusConstants} from "@pythnetwork/entropy-sdk-solidity/EntropyStatusConstants.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {DeadLine} from "./DeadLine.sol";
import {IEntropyConsumerBase} from "../interfaces/IEntropyConsumerBase.sol";

abstract contract EntropyConsumerBase is IEntropyConsumer, AccessControl, DeadLine, IEntropyConsumerBase {
    uint64 public constant MIN_ENTROPY_TIMEOUT = 60;
    uint64 public constant MAX_ENTROPY_TIMEOUT = 24 hours;
    uint32 public constant MIN_CALLBACK_GAS = 100_000;
    uint32 public constant MAX_CALLBACK_GAS = 2_000_000;

    IEntropyV2 public immutable entropy;
    address public entropyProvider;
    uint32  public callbackGasLimit;
    uint64  public entropyTimeout;

    mapping(uint64 sequenceNumber => Request) internal _request;

    constructor(address entropy_, address entropyProvider_) {
        if (entropy_ == address(0) || entropyProvider_ == address(0)) revert ErrorZeroAddress();
        entropy = IEntropyV2(entropy_);
        entropyProvider = entropyProvider_;
        callbackGasLimit = 500_000;
        entropyTimeout = 1 hours;
    }

    function getEntropy() internal view override returns (address) {
        return address(entropy);
    }

    function entropyFee() public view returns (uint256) {
        return entropy.getFeeV2(entropyProvider, callbackGasLimit);
    }

    function getRequest(uint64 sequenceNumber) external view returns (Request memory) {
        return _request[sequenceNumber];
    }

    function _requestRandomness(
        uint256 tokenId,
        address requester,
        uint32 itemCount,
        bytes32 userRandomNumber,
        uint256 paid
    ) internal returns (uint64 sequenceNumber, uint128 paidFee) {
        if (userRandomNumber == bytes32(0)) revert ErrorInvalidUserRandom();
        uint256 fee = entropyFee();
        if (paid < fee) revert ErrorInsufficientEntropyFee(fee, paid);

        sequenceNumber = entropy.requestV2{value: fee}(entropyProvider, userRandomNumber, callbackGasLimit);
        paidFee = uint128(fee);

        _request[sequenceNumber] = Request({
            tokenId: tokenId,
            requester: requester,
            requestedAt: uint64(block.timestamp),
            itemCount: itemCount,
            paidFee: paidFee,
            exists: true
        });

        emit RequestSubmitted(sequenceNumber, requester, tokenId, itemCount, paidFee);

        _postRequest(sequenceNumber, _request[sequenceNumber]);

        uint256 excess = paid - fee;
        if (excess > 0) _refundFee(requester, excess);
    }

    /// @dev 子类可在 base 退余款（让出控制权）前继续写业务 storage / emit
    function _postRequest(uint64 /*sequenceNumber*/, Request memory /*req*/) internal virtual {}

    function _refundFee(address to, uint256 amount) internal {
        (bool ok, ) = payable(to).call{value: amount}("");
        if (!ok) revert ErrorRefundFailed();
    }

    function entropyCallback(uint64 sequenceNumber, address /*provider*/, bytes32 randomNumber) internal override {
        Request memory req = _request[sequenceNumber];
        if (!req.exists) return;
        delete _request[sequenceNumber];
        _onRequestFulfilled(sequenceNumber, req, randomNumber);
        emit RequestFulfilled(sequenceNumber, req.requester, req.tokenId);
    }

    function retryRequest(
        uint64 oldSequenceNumber,
        bytes32 newUserRandomNumber,
        uint256 deadline
    ) external payable checkDeadline(deadline) returns (uint64 newSequenceNumber) {
        Request memory old = _request[oldSequenceNumber];
        if (!old.exists) revert ErrorRequestNotFound();
        if (old.requester != msg.sender) revert ErrorNotRequester();
        if (newUserRandomNumber == bytes32(0)) revert ErrorInvalidUserRandom();

        bool timedOut = block.timestamp >= uint256(old.requestedAt) + uint256(entropyTimeout);
        bool callbackFailed = false;
        if (!timedOut) {
            EntropyStructsV2.Request memory pythReq = entropy.getRequestV2(entropyProvider, oldSequenceNumber);
            callbackFailed = (pythReq.callbackStatus == EntropyStatusConstants.CALLBACK_FAILED);
        }
        if (!timedOut && !callbackFailed) revert ErrorRetryNotAllowed();

        _beforeRetry(oldSequenceNumber, old);

        uint256 fee = entropyFee();
        if (msg.value < fee) revert ErrorInsufficientEntropyFee(fee, msg.value);

        newSequenceNumber = entropy.requestV2{value: fee}(entropyProvider, newUserRandomNumber, callbackGasLimit);
        uint128 newFee = uint128(fee);

        delete _request[oldSequenceNumber];
        _request[newSequenceNumber] = Request({
            tokenId: old.tokenId,
            requester: old.requester,
            requestedAt: uint64(block.timestamp),
            itemCount: old.itemCount,
            paidFee: newFee,
            exists: true
        });

        emit RequestRetried(oldSequenceNumber, newSequenceNumber, old.requester, old.paidFee, newFee);

        _postRetry(oldSequenceNumber, newSequenceNumber, _request[newSequenceNumber]);

        uint256 excess = msg.value - fee;
        if (excess > 0) _refundFee(msg.sender, excess);
    }

    function _beforeRetry(uint64 /*oldSequenceNumber*/, Request memory /*old*/) internal virtual {}

    /// @dev 子类可在 base 退余款前同步业务状态（例如把 NFT 的 sequenceNumber 切到 newSeq）
    function _postRetry(
        uint64 /*oldSequenceNumber*/,
        uint64 /*newSequenceNumber*/,
        Request memory /*updated*/
    ) internal virtual {}

    function _onRequestFulfilled(uint64 sequenceNumber, Request memory req, bytes32 randomNumber) internal virtual;

    function setEntropyProvider(address newProvider) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newProvider == address(0)) revert ErrorZeroAddress();
        emit EntropyProviderChanged(entropyProvider, newProvider);
        entropyProvider = newProvider;
    }

    function setCallbackGasLimit(uint32 newLimit) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newLimit < MIN_CALLBACK_GAS || newLimit > MAX_CALLBACK_GAS) revert ErrorInvalidCallbackGasLimit();
        emit CallbackGasLimitChanged(callbackGasLimit, newLimit);
        callbackGasLimit = newLimit;
    }

    function setEntropyTimeout(uint64 newTimeout) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newTimeout < MIN_ENTROPY_TIMEOUT || newTimeout > MAX_ENTROPY_TIMEOUT) revert ErrorInvalidEntropyTimeout();
        emit EntropyTimeoutChanged(entropyTimeout, newTimeout);
        entropyTimeout = newTimeout;
    }
}
