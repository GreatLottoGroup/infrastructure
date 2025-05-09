// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

/// @title Prevents delegatecall to a contract
/// @notice Base contract that provides a modifier for preventing delegatecall to methods in a child contract
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
