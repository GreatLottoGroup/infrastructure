// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

/// @dev Test-only contract that refuses ETH transfers. Used to exercise the
///      _refundFee revert branch in EntropyConsumerBase.
contract RejectingReceiver {
    fallback() external payable {
        revert("rejecting");
    }
    receive() external payable {
        revert("rejecting");
    }
}
