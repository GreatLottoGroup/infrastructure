// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.36;

/// @title IErrorsBase
/// @notice Shared custom errors reused across GreatLotto infrastructure contracts and their downstreams.
/// @dev    Contracts inherit this interface (`is IErrorsBase`) so they revert with a common error vocabulary
///         (invalid amount / address, unsuccessful payment, insufficient balance, zero / unsupported token).
interface IErrorsBase {

    /**
     * @dev Invalid Amount
     */
    error ErrorInvalidAmount(uint amount);

    /**
     * @dev Errors: The payment was unsuccessful
     */
    error ErrorPaymentUnsuccessful();

    /**
     * @dev Errors: Insufficient balance
     */
    error ErrorInsufficientBalance(address token, address account, uint balance, uint amount);

    /**
     * @dev Errors: The address is 0
     */
    error ErrorZeroAddress();

    /**
     * @dev Errors: There is an unsupported token
     */
    error ErrorUnsupportedToken(address token);

    /**
     * @dev Errors: There is an Invalid Address
     */
    error ErrorInvalidAddress(address addr);


}
