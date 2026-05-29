// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol';
import '../interfaces/ISelfPermit.sol';

//import "hardhat/console.sol";

/// @title Self Permit
/// @notice Functionality to call permit on any EIP-2612-compliant token for use in the route
/// @dev These functions are expected to be embedded in multicalls to allow EOAs to approve a contract and call a function
/// that requires an approval in a single transaction.
abstract contract SelfPermit is ISelfPermit {

    /// @inheritdoc ISelfPermit
    function selfPermit(
        address owner,
        address token,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public payable override {
        IERC20Permit(token).permit(owner, address(this), value, deadline, v, r, s);
    }

    /// @inheritdoc ISelfPermit
    function selfPermitIfNecessary(
        address owner,
        address token,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public payable override {
        if (IERC20(token).allowance(owner, address(this)) < value) {
            selfPermit(owner, token, value, deadline, v, r, s);
        }
    }
}
