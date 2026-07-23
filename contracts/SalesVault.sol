// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.36;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/// @title SalesVault
/// @notice Sales-profit vault — an OZ ERC4626 whose asset is GLC. Shares are hard-capped at 100 million, all
///         minted to the owner at deployment. Sales benefit is pushed in by each PrizePool via a direct
///         `safeTransfer` of GLC — raising `totalAssets` without touching `totalSupply`, so every share
///         appreciates proportionally. Share holders redeem GLC pro rata via ERC4626 `redeem` / `withdraw`.
/// @dev    deposit/mint/redeem/withdraw are all public; public deposit/mint are bounded by the 100M hard cap:
///         `maxMint` returns `MAX_SHARES - totalSupply()` and `maxDeposit` is derived from it, so at the cap
///         (including the post-deploy initial state) both are 0 and OZ's standard limit checks revert
///         `ERC4626ExceededMaxDeposit` / `ERC4626ExceededMaxMint` — i.e. the public cannot subscribe while the
///         vault is at the cap (naturally sealed).
///         `_decimalsOffset() = 6` provides virtual shares against inflation attacks (a hard prerequisite for
///         opening subscription). The vault ledger is denominated in base-unit (wei) GLC, consistent with the
///         PrizePoolBase transfer-in side — no further `getAmount` scaling happens inside the vault.
///
///         **The only privileged entry is `adminMint`**: the owner (holding `DEFAULT_ADMIN_ROLE`) can mint
///         shares for FREE within the `maxMint` cap. Design intent — a share is equity in sales profit, and the
///         only way to draw profit is `redeem` (burning shares); after a holder draws earnings their stake
///         shrinks, so the admin uses `adminMint` to top the shares back up within the room freed by `redeem`,
///         realizing "draw earnings without losing equity". `adminMint` reuses the `maxMint` check and does NOT
///         bypass the 100M hard cap (reverts naturally at the cap).
///         ⚠️ Safe usage: only use it to top up after a holder has `redeem`ed and freed room; do NOT free-mint
///         to a new address while the vault still holds accrued earnings (that would dilute existing holders'
///         earned profit pro rata); strongly recommend a multisig for `owner_`.
///         The vault still has NO `adminBurn` / confiscation, NO `sweep` / `rescue` fund backdoor, and NO
///         `pause` — the admin's only privilege is minting shares within the hard cap.
contract SalesVault is ERC4626, AccessControl {

    /// @notice Share hard cap: 100 million shares (18 decimals, matching GLC's base decimals).
    uint256 public constant MAX_SHARES = 100_000_000 * 1e18;

    /// @param asset_ The GLC asset-token address.
    /// @param owner_ Holder of all initial shares, also granted `DEFAULT_ADMIN_ROLE`.
    constructor(address asset_, address owner_)
        ERC20("GreatLotto Sales Vault", "GLSV")
        ERC4626(IERC20(asset_))
    {
        _mint(owner_, MAX_SHARES);
        _grantRole(DEFAULT_ADMIN_ROLE, owner_);
    }

    /// @notice Admin free-mints shares to `receiver` within the 100M hard cap (to restore equity after a holder
    ///         has `redeem`ed and freed room).
    /// @dev    Reuses the `maxMint(receiver)` cap check: `shares > maxMint(receiver)` reverts
    ///         `ERC4626ExceededMaxMint` (at the cap `maxMint == 0`, so any mint reverts). Post-mint `totalSupply`
    ///         never exceeds `MAX_SHARES`. Free mint (no consideration taken from `receiver`) — see the
    ///         contract-level @dev for safe usage. Parameter order matches ERC4626 `mint(shares, receiver)`.
    /// @param  shares   Number of shares to mint.
    /// @param  receiver Address that receives the shares.
    function adminMint(uint256 shares, address receiver) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 maxShares = maxMint(receiver);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxMint(receiver, shares, maxShares);
        }
        _mint(receiver, shares);
    }

    /// @dev virtual shares against inflation attacks — a hard prerequisite for opening public subscription.
    function _decimalsOffset() internal pure override returns (uint8) {
        return 6;
    }

    /// @notice The remaining shares that can still be minted (= 100M − current `totalSupply`; 0 at the cap).
    /// @dev    At the cap, OZ `mint` reverts `ERC4626ExceededMaxMint` because `shares > maxMint`.
    /// @return The mintable share headroom.
    function maxMint(address) public view override returns (uint256) {
        uint256 supply = totalSupply();
        return supply >= MAX_SHARES ? 0 : MAX_SHARES - supply;
    }

    /// @notice The remaining assets that can still be deposited (derived from `maxMint` at the current price, floored).
    /// @dev    Floor rounding is conservative (rather under-mint than exceed the cap) and preserves the 100M hard
    ///         cap; 0 at the cap → OZ `deposit` reverts `ERC4626ExceededMaxDeposit`.
    /// @return The depositable asset headroom in wei (GLC).
    function maxDeposit(address) public view override returns (uint256) {
        return _convertToAssets(maxMint(address(0)), Math.Rounding.Floor);
    }

    // redeem / withdraw keep the default ERC4626 implementation (share holders redeem GLC pro rata, no gate).
}
