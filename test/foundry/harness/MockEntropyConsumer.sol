// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {EntropyConsumerBase} from "../../../contracts/base/EntropyConsumerBase.sol";

/// @dev 测试用最小子类。把基类 internal 暴露为 public、把 callback 内的 randomNumber 写入 mapping。
contract MockEntropyConsumer is EntropyConsumerBase {
    bytes32 public lastRandomNumber;
    uint64  public lastSequence;
    uint256 public lastTokenId;
    address public lastRequester;
    uint32  public lastItemCount;
    bool    public revertOnFulfill;
    bool    public revertOnBeforeRetry;
    uint64  public lastPostRequestSeq;
    uint64  public lastPostRetryOldSeq;
    uint64  public lastPostRetryNewSeq;

    constructor(address entropy_, address provider_, address owner_) EntropyConsumerBase(entropy_, provider_, owner_) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function _onRequestFulfilled(uint64 sequenceNumber, Request memory req, bytes32 randomNumber) internal override {
        if (revertOnFulfill) revert("fulfill-revert");
        lastSequence = sequenceNumber;
        lastRandomNumber = randomNumber;
        lastTokenId = req.tokenId;
        lastRequester = req.requester;
        lastItemCount = req.itemCount;
    }

    /// @dev 测试用 public wrapper，把 msg.value 当 paid 传入
    function requestRandomness(
        uint256 tokenId,
        address requester,
        uint32 itemCount,
        bytes32 userRandomNumber
    ) external payable returns (uint64 sequenceNumber, uint128 paidFee) {
        return _requestRandomness(tokenId, requester, itemCount, userRandomNumber, msg.value);
    }

    function _postRequest(uint64 sequenceNumber, Request memory /*req*/) internal override {
        lastPostRequestSeq = sequenceNumber;
    }

    function _beforeRetry(uint64 /*oldSequenceNumber*/, Request memory /*old*/) internal view override {
        if (revertOnBeforeRetry) revert("before-retry-revert");
    }

    function _postRetry(uint64 oldSequenceNumber, uint64 newSequenceNumber, Request memory /*updated*/) internal override {
        lastPostRetryOldSeq = oldSequenceNumber;
        lastPostRetryNewSeq = newSequenceNumber;
    }

    function setRevertOnFulfill(bool v) external { revertOnFulfill = v; }
    function setRevertOnBeforeRetry(bool v) external { revertOnBeforeRetry = v; }
}
