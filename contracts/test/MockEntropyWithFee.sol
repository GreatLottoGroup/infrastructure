// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {IEntropyV2} from "@pythnetwork/entropy-sdk-solidity/IEntropyV2.sol";
import {IEntropyConsumer} from "@pythnetwork/entropy-sdk-solidity/IEntropyConsumer.sol";
import {EntropyStructsV2} from "@pythnetwork/entropy-sdk-solidity/EntropyStructsV2.sol";
import {EntropyEventsV2} from "@pythnetwork/entropy-sdk-solidity/EntropyEventsV2.sol";
import {EntropyStatusConstants} from "@pythnetwork/entropy-sdk-solidity/EntropyStatusConstants.sol";

/// @dev Test-only harness implementing the slice of IEntropyV2 that
///      EntropyConsumerBase / its tests exercise. Pyth's stock MockEntropy
///      hardcodes getFeeV2 as `pure returns 0`, which makes "insufficient fee"
///      / "refund excess" branches unreachable AND prevents overriding to
///      `view` (Solidity disallows loosening pure → view). This standalone
///      mock exposes a configurable fee plus mockReveal helper so tests can
///      drive the full request → callback lifecycle end-to-end.
contract MockEntropyWithFee is IEntropyV2 {
    uint128 public mockFee;
    uint64 public nextSequenceNumber = 1;
    address public defaultProvider;

    mapping(uint64 sequenceNumber => EntropyStructsV2.Request) private _requests;
    mapping(uint64 sequenceNumber => bool) private _failed;

    constructor(address defaultProvider_, uint128 initialFee_) {
        require(defaultProvider_ != address(0), "Invalid default provider");
        defaultProvider = defaultProvider_;
        mockFee = initialFee_;
    }

    function setFee(uint128 newFee) external {
        mockFee = newFee;
    }

    /// @notice Simulate Pyth provider triggering callback with a successful reveal.
    function mockReveal(address requester, uint64 sequenceNumber, bytes32 randomNumber) external {
        EntropyStructsV2.Request storage req = _requests[sequenceNumber];
        require(req.requester != address(0), "Request not found");
        require(req.requester == requester, "Requester mismatch");

        address provider = req.provider;
        delete _requests[sequenceNumber];

        IEntropyConsumer(requester)._entropyCallback(sequenceNumber, provider, randomNumber);
    }

    /// @notice Simulate "callback failed" path. Mark the request as CALLBACK_FAILED
    ///         without calling the consumer; getRequestV2 will reflect the failed status.
    function markCallbackFailed(uint64 sequenceNumber) external {
        EntropyStructsV2.Request storage req = _requests[sequenceNumber];
        require(req.requester != address(0), "Request not found");
        _failed[sequenceNumber] = true;
    }

    // ============ IEntropyV2 implementation ============

    function requestV2() external payable override returns (uint64) {
        return _request(defaultProvider, bytes32(0), 0, msg.value);
    }

    function requestV2(uint32 gasLimit) external payable override returns (uint64) {
        return _request(defaultProvider, bytes32(0), gasLimit, msg.value);
    }

    function requestV2(address provider, uint32 gasLimit) external payable override returns (uint64) {
        return _request(provider, bytes32(0), gasLimit, msg.value);
    }

    function requestV2(
        address provider,
        bytes32 userRandomNumber,
        uint32 gasLimit
    ) external payable override returns (uint64) {
        return _request(provider, userRandomNumber, gasLimit, msg.value);
    }

    function _request(
        address provider,
        bytes32 userRandomNumber,
        uint32 gasLimit,
        uint256 paid
    ) internal returns (uint64 sequenceNumber) {
        require(paid >= mockFee, "Insufficient fee");

        sequenceNumber = nextSequenceNumber;
        nextSequenceNumber += 1;

        EntropyStructsV2.Request storage req = _requests[sequenceNumber];
        req.provider = provider;
        req.sequenceNumber = sequenceNumber;
        req.requester = msg.sender;
        req.blockNumber = uint64(block.number);
        req.useBlockhash = false;
        req.gasLimit10k = uint16(gasLimit / 10000);
        req.numHashes = 0;
        req.callbackStatus = EntropyStatusConstants.CALLBACK_NOT_STARTED;

        emit Requested(provider, msg.sender, sequenceNumber, userRandomNumber, gasLimit, bytes(""));
    }

    function getFeeV2() external view override returns (uint128) {
        return mockFee;
    }

    function getFeeV2(uint32) external view override returns (uint128) {
        return mockFee;
    }

    function getFeeV2(address, uint32) external view override returns (uint128) {
        return mockFee;
    }

    function getRequestV2(
        address /*provider*/,
        uint64 sequenceNumber
    ) external view override returns (EntropyStructsV2.Request memory r) {
        r = _requests[sequenceNumber];
        if (_failed[sequenceNumber]) {
            r.callbackStatus = EntropyStatusConstants.CALLBACK_FAILED;
        }
    }

    function getDefaultProvider() external view override returns (address) {
        return defaultProvider;
    }

    function getProviderInfoV2(
        address /*provider*/
    ) external pure override returns (EntropyStructsV2.ProviderInfo memory info) {
        return info;
    }
}
