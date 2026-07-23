// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.36;

import {EntropyConsumerBase} from "../../../contracts/base/EntropyConsumerBase.sol";

/// @dev 最小子类：仅实现强制的 `_onRequestFulfilled`，刻意**不** override 三个可选 hook
///      （`_postRequest` / `_beforeRetry` / `_postRetry`），从而让基类的空默认实现被实际执行，
///      覆盖 MockEntropyConsumer（全部 override）无法触及的基类默认 hook 体。
contract DefaultHooksEntropyConsumer is EntropyConsumerBase {
    uint64 public lastSequence;

    constructor(address entropy_, address provider_, address owner_)
        EntropyConsumerBase(entropy_, provider_, owner_)
    {}

    function _onRequestFulfilled(uint64 sequenceNumber, Request memory, bytes32) internal override {
        lastSequence = sequenceNumber;
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
}
