// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/// @title SalesVault
/// @notice 销售利润金库——继承 OZ ERC4626，资产币为 GLC。份额硬上限 1 亿，部署时全部铸给 owner。
///         销售分润由各 PrizePool 直接 `safeTransfer` GLC 进本合约 —— 抬高 totalAssets、不动
///         totalSupply，使每份额按比例增值。份额持有人凭 ERC4626 `redeem`/`withdraw` 按比例提走 GLC。
/// @dev    **纯无特权 ERC4626**：deposit/mint/redeem/withdraw 全公开、无 owner 后门（无 topUp/sweep/pause）。
///         deposit/mint 受 1 亿硬上限约束：`maxMint` 返回 `MAX_SHARES - totalSupply()`、`maxDeposit`
///         由其换算，顶满（含部署后初始状态）即 0，OZ 标准上限校验会 revert
///         `ERC4626ExceededMaxDeposit`/`ERC4626ExceededMaxMint`。
///         `_decimalsOffset()=6` 提供 virtual shares 防 inflation attack（开放申购的强制安全前提）。
///         owner 仅在部署时获得全部初始份额，运行期与任意持有人等权。金库账本以底层 wei 级 GLC 计量，
///         与 PrizePoolBase 转入侧单位贯通——不在金库内再做 getAmount 放大。
contract SalesVault is ERC4626 {

    /// @notice 份额硬上限：1 亿份（18 位小数，与 GLC 底层小数一致）
    uint256 public constant MAX_SHARES = 100_000_000 * 1e18;

    /// @param asset_ GLC 资产币地址
    /// @param owner_ 初始全部份额的持有人
    constructor(address asset_, address owner_)
        ERC20("GreatLotto Sales Vault", "GLSV")
        ERC4626(IERC20(asset_))
    {
        _mint(owner_, MAX_SHARES);
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
