// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.36;

import "./ICoinBase.sol";

/// @title IGreatLottoCoin
/// @notice Contract interface for the GreatLottoCoin (GLC) prize-pool currency.
/// @dev    A marker interface that inherits the full surface of `ICoinBase` (plus ERC20 / ERC20Permit);
///         downstream contracts depend on this type without adding members of their own.
interface IGreatLottoCoin is ICoinBase {

}
