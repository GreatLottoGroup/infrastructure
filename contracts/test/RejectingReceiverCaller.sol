// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

interface IConsumerForCaller {
    function requestRandomness(uint256, address, uint32, bytes32) external payable returns (uint64, uint128);
    function retryRequest(uint64, bytes32, uint256) external payable returns (uint64);
}

/// @dev Test-only: calls into the consumer but rejects ETH refunds, used to
///      exercise the ErrorRefundFailed branch in retryRequest.
contract RejectingReceiverCaller {
    IConsumerForCaller public immutable consumer;
    constructor(address consumer_) { consumer = IConsumerForCaller(consumer_); }

    function submitRequest(uint256 tokenId, bytes32 userRandomNumber) external payable {
        consumer.requestRandomness{value: msg.value}(tokenId, address(this), 1, userRandomNumber);
    }

    function retryRequestFromMe(uint64 oldSeq, bytes32 newRandom, uint256 deadline) external payable {
        consumer.retryRequest{value: msg.value}(oldSeq, newRandom, deadline);
    }

    receive() external payable { revert("rejecting"); }
    fallback() external payable { revert("rejecting"); }
}
