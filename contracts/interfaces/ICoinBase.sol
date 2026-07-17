// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";


/// @title ICoinBase
/// @notice Contract interface for GreatLottoCoin (GLC): a stablecoin-backed wrapper token. Callers deposit a
///         whitelisted underlying stablecoin to mint GLC (18 decimals) and burn GLC to withdraw the underlying.
/// @dev    `amount` in mint/withdraw/getAmount is expressed in WHOLE tokens (not base units): minted GLC =
///         `amount * 10**18`, and the underlying pulled/paid = `amount * 10**underlyingDecimals`.
interface ICoinBase is IERC20, IERC20Permit {
    /// @dev Reverts when `recover()` finds no surplus underlying balance beyond `totalSupply` (nothing to recover).
    error GreatLottoCoinBaseNoNeedRecover(uint totalBalance, uint totalSupply);

    /// @notice Emitted when a holder burns GLC and withdraws the corresponding amount of an underlying token.
    event GreatLottoCoinBaseWithdrawn(address indexed recipient, address indexed token, uint256 amount);
    /// @notice Emitted when the owner recovers surplus underlying balance by minting GLC to itself.
    event GreatLottoCoinBaseRecovered(uint256 value, uint256 totalSupply);


    /// @notice Mint GLC by pulling a whitelisted underlying stablecoin from `payer`.
    /// @dev    Restricted to holders of `PARTNER_CONTRACT_ROLE` (only the prize pool contract). Pulls
    ///         `amount * 10**underlyingDecimals` of `token` via `safeTransferFrom` and mints `amount * 10**18`
    ///         GLC to the caller. Reverts `ErrorUnsupportedToken` if `token` is not whitelisted.
    /// @param  token  Underlying stablecoin address (must be whitelisted).
    /// @param  amount Whole-token amount to mint (GLC minted = `amount * 10**18`).
    /// @param  payer  Address the underlying token is pulled from.
    /// @return True on success.
    function mint(address token, uint256 amount, address payer) external returns (bool);
    /// @notice Mint GLC by pulling a whitelisted underlying stablecoin from `payer` using an EIP-2612 permit.
    /// @dev    Restricted to holders of `PARTNER_CONTRACT_ROLE`. Applies the signed permit (if allowance is
    ///         insufficient) before pulling the underlying, so `payer` needs no prior approval.
    /// @param  token    Underlying stablecoin address (must be whitelisted).
    /// @param  amount   Whole-token amount to mint (GLC minted = `amount * 10**18`).
    /// @param  payer    Address the underlying token is pulled from and that signed the permit.
    /// @param  deadline Permit expiry, a unix timestamp in seconds.
    /// @param  v        secp256k1 signature component of the permit.
    /// @param  r        secp256k1 signature component of the permit.
    /// @param  s        secp256k1 signature component of the permit.
    /// @return True on success.
    function mint(address token, uint256 amount, address payer, uint deadline, uint8 v, bytes32 r, bytes32 s) external returns (bool);

    /// @notice Burn the caller's GLC and withdraw the corresponding amount of an underlying token to the caller.
    /// @dev    Burns `amount * 10**18` GLC from the caller and transfers `amount * 10**underlyingDecimals` of
    ///         `token` back. Reverts `ErrorUnsupportedToken` / `ErrorInsufficientBalance` on failure.
    /// @param  token  Underlying stablecoin address to withdraw (must be whitelisted).
    /// @param  amount Whole-token amount to withdraw.
    /// @return True on success.
    function withdraw(address token, uint256 amount) external returns (bool);

    /// @notice The EIP-712 domain version string of this token.
    /// @return The version string.
    function version() external view returns (string memory);

    /// @notice Whether `token` is in the supported underlying-stablecoin whitelist.
    /// @param  token  The token address to check.
    /// @return result True if `token` is whitelisted.
    function checkToken(address token) external view returns (bool result);

    /// @notice Convert a whole-token amount to GLC base units.
    /// @param  amount Whole-token amount.
    /// @return The value in GLC base units (`amount * 10**decimals`, i.e. `amount * 10**18`).
    function getAmount(uint amount) external view returns (uint);

    /// @notice Recover surplus underlying balance (beyond `totalSupply`) by minting the difference as GLC to the owner.
    /// @dev    Restricted to `DEFAULT_ADMIN_ROLE` (owner). Reverts `GreatLottoCoinBaseNoNeedRecover` when there
    ///         is no surplus.
    /// @return value The amount of GLC minted to the owner (the recovered surplus).
    function recover() external returns (uint256 value);

}
