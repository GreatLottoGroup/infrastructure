// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

/// @title SalesVault
/// @notice 销售利润金库——继承 OZ ERC4626，资产币为 GLC。份额硬上限 1 亿，部署时全部铸给 owner。
///         销售分润由各 PrizePool 直接 `safeTransfer` GLC 进本合约 —— 抬高 totalAssets、不动
///         totalSupply，使每份额按比例增值。份额持有人凭 ERC4626 `redeem`/`withdraw` 按比例提走 GLC。
/// @dev    deposit/mint/redeem/withdraw 全公开；公众 deposit/mint 受 1 亿硬上限约束：`maxMint` 返回
///         `MAX_SHARES - totalSupply()`、`maxDeposit` 由其换算，顶满（含部署后初始状态）即 0，OZ 标准
///         上限校验会 revert `ERC4626ExceededMaxDeposit`/`ERC4626ExceededMaxMint`——故部署即满额状态下
///         公众无从申购（天然封死）。
///         `_decimalsOffset()=6` 提供 virtual shares 防 inflation attack（开放申购的强制安全前提）。
///         金库账本以底层 wei 级 GLC 计量，与 PrizePoolBase 转入侧单位贯通——不在金库内再做 getAmount 放大。
///
///         **唯一特权入口 `adminMint`**：owner 持 `DEFAULT_ADMIN_ROLE`，可在 `maxMint` 上限内**免费**增铸
///         份额。设计意图——份额即销售分润股权，而提分润的唯一方式是 `redeem`（烧份额）；持有人提收益后
///         占比下降，admin 经 `adminMint` 在 `redeem` 腾出的额度内把份额补回，实现「提收益不丧失股权」。
///         `adminMint` 复用 `maxMint` 校验，**不绕过 1 亿硬上限**（满额时自然 revert）。
///         ⚠️ 安全用法：仅在持有人 `redeem` 腾出额度后用于补回，**不要**在金库尚有存量收益时给新地址
///         免费铸（会按比例分走老持有人既得收益）；强烈建议 `owner_` 使用多签。
///         金库仍 **无** `adminBurn`/没收、**无** `sweep`/`rescue` 资金后门、**无** `pause`——admin 的唯一
///         特权是在硬上限内增铸份额。
contract SalesVault is ERC4626, AccessControl {

    /// @notice 份额硬上限：1 亿份（18 位小数，与 GLC 底层小数一致）
    uint256 public constant MAX_SHARES = 100_000_000 * 1e18;

    /// @param asset_ GLC 资产币地址
    /// @param owner_ 初始全部份额的持有人，同时获得 `DEFAULT_ADMIN_ROLE`
    constructor(address asset_, address owner_)
        ERC20("GreatLotto Sales Vault", "GLSV")
        ERC4626(IERC20(asset_))
    {
        _mint(owner_, MAX_SHARES);
        _grantRole(DEFAULT_ADMIN_ROLE, owner_);
    }

    /// @notice admin 在 1 亿硬上限内免费增铸份额给 `receiver`（用于持有人 `redeem` 腾额后补回股权）。
    /// @dev    复用 `maxMint(receiver)` 校验上限：`shares > maxMint(receiver)` 即 revert `ERC4626ExceededMaxMint`
    ///         （满额时 `maxMint == 0`，故满额状态下任何增铸均 revert）。铸后 totalSupply 不超 `MAX_SHARES`。
    ///         免费铸（不收 `receiver` 任何对价）——见合约级 @dev 的安全用法说明。
    ///         参数顺序对齐 ERC4626 `mint(shares, receiver)`。
    /// @param shares 增铸份额数量
    /// @param receiver     接收份额的地址
    function adminMint(uint256 shares, address receiver) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 maxShares = maxMint(receiver);
        if (shares > maxShares) {
            revert ERC4626ExceededMaxMint(receiver, shares, maxShares);
        }
        _mint(receiver, shares);
    }

    /// @dev virtual shares 防 inflation attack —— 开放公众申购的强制安全前提。
    function _decimalsOffset() internal pure override returns (uint8) {
        return 6;
    }

    /// @notice 还能再铸的份额额度（= 1 亿 − 当前 totalSupply；顶满返回 0）。
    /// @dev    顶满时 OZ `mint` 因 `shares > maxMint` revert `ERC4626ExceededMaxMint`。
    function maxMint(address) public view override returns (uint256) {
        uint256 supply = totalSupply();
        return supply >= MAX_SHARES ? 0 : MAX_SHARES - supply;
    }

    /// @notice 还能再存的资产额度（由 `maxMint` 经现价 floor 换算）。
    /// @dev    floor 取整偏保守（宁少铸不超限），不破坏 1 亿硬上限；顶满返回 0 → OZ `deposit` revert
    ///         `ERC4626ExceededMaxDeposit`。
    function maxDeposit(address) public view override returns (uint256) {
        return _convertToAssets(maxMint(address(0)), Math.Rounding.Floor);
    }

    // redeem / withdraw 保留 ERC4626 默认实现（份额持有人按比例提走 GLC，无门槛）。
}
