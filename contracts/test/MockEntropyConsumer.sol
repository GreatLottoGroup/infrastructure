// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {EntropyConsumerBase} from "../base/EntropyConsumerBase.sol";

/// @dev 测试用最小子类。把基类 internal 暴露为 public、把 callback 内的 randomNumber 写入 mapping。
contract MockEntropyConsumer is EntropyConsumerBase {
    bytes32 public lastRandomNumber;
    uint64  public lastSequence;
    uint256 public lastTokenId;
    address public lastRequester;
    uint32  public lastItemCount;
    bool    public revertOnFulfill;
    bool    public revertOnBeforeRetry;

    constructor(address entropy_, address provider_) EntropyConsumerBase(entropy_, provider_) {
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

    function setRevertOnFulfill(bool v) external { revertOnFulfill = v; }
    function setRevertOnBeforeRetry(bool v) external { revertOnBeforeRetry = v; }
}
