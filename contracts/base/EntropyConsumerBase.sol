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

    function entropyCallback(uint64 sequenceNumber, address /*provider*/, bytes32 randomNumber) internal override {
        Request memory req = _request[sequenceNumber];
        if (!req.exists) return;
        delete _request[sequenceNumber];
        _onRequestFulfilled(sequenceNumber, req, randomNumber);
        emit RequestFulfilled(sequenceNumber, req.requester, req.tokenId);
    }

    function _onRequestFulfilled(uint64 sequenceNumber, Request memory req, bytes32 randomNumber) internal virtual;
}
