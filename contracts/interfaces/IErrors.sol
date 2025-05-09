// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

/// @title Callback for IUniswapV3PoolActions#mint
/// @notice Any contract that calls IUniswapV3PoolActions#mint must implement this interface
interface IErrors {

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
    error ErrorInsufficientBalanceEth(address account, uint balance, uint amount);

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
