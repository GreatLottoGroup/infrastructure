// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.36;

/// @title DeadLine
/// @notice Base contract providing a `checkDeadline` modifier that reverts once a transaction's deadline has passed.
/// @dev    `deadline` is a unix timestamp in seconds; reverts `DeadLineExpiredTransaction` when
///         `block.timestamp > deadline`.
abstract contract DeadLine {
    /**
     * @dev DeadLine: Transaction is too old
     */
    error DeadLineExpiredTransaction(uint256 deadline, uint256 timestamp);

    modifier checkDeadline(uint256 deadline) {
        if(block.timestamp > deadline){
            revert DeadLineExpiredTransaction(deadline, block.timestamp);
        }
        _;
    }
    
}
