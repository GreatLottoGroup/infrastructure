## Context

`SalesVault`（[contracts/SalesVault.sol](../../../contracts/SalesVault.sol)）是销售利润 ERC4626 金库：底层资产 GLC，构造时 `_mint(owner_, MAX_SHARES)` 把 1 亿份额一次性铸满给 owner，`PrizePoolBase` 经 `safeTransfer` 把销售分润打入金库抬高 `totalAssets`，份额按比例增值。

现状有两条强约束彼此冲突：
1. 提分润的唯一途径是 ERC4626 `redeem`/`withdraw`——**烧份额**换 GLC。
2. 份额即销售分润股权比例。

结果：持有人每提一次收益就等比丧失未来股权，且构造已顶满 `MAX_SHARES`、被烧份额无合规补回途径。本变更在硬上限内引入一个 admin 增铸入口解此结。

约束：仅改 SalesVault 内部，下游（PrizePool 经 `salesVaultAddress` 引用）零打穿；保留全部既有 ERC4626 行为与硬上限。

## Goals / Non-Goals

**Goals:**
- 让 admin 在持有人 `redeem` 腾出的额度内增铸份额，把份额补回，实现「提收益不丧失股权」。
- 增铸严格受 `maxMint`（1 亿硬上限）约束，不引入任何突破硬上限的路径。
- 改动最小化：一个继承（`AccessControl`）、构造一行授权、一个 `adminMint` 函数；其余全不动。

**Non-Goals:**
- 不解耦「提收益」与「持股权」于合约层（不引入 MasterChef 式 `accRewardPerShare` claim 账本）；解耦靠 admin 行政增铸维持比例。
- 不新增 `adminBurn`/没收份额、不新增 `sweep`/`rescue` 资金后门、不新增 `pause`。
- 不显式关闭公众 `deposit`/`mint`（已由构造顶满机制天然封死，满额时 `maxMint == 0`）。
- 不调整 `MAX_SHARES`、不改构造铸造量、不改 `_decimalsOffset`。

## Decisions

### D1：权限用 `AccessControl` + `DEFAULT_ADMIN_ROLE`（而非 `Ownable`）

构造 `_grantRole(DEFAULT_ADMIN_ROLE, owner_)`，`adminMint` 加 `onlyRole(DEFAULT_ADMIN_ROLE)`。

- **Why over Ownable**：与工作区其他合约（`PrizePoolBase`、`AccessControlPartnerContract` 等）风格一致；未来若需多管理员或拆分角色无需重构。代价是引入 ERC165 `supportsInterface`（与 ERC4626/ERC20 无冲突，体积增加极小）。
- **不用 `AccessControlPartnerContract`**：那是「只授合约不授 EOA」的 PARTNER 角色，本场景管理员是 owner（EOA 或多签），语义不符。

### D2：`adminMint` 复用 `maxMint(to)` 上限校验，不绕过硬上限

```solidity
// 参数顺序对齐 ERC4626 mint(shares, receiver)
function adminMint(uint256 shares, address to) external onlyRole(DEFAULT_ADMIN_ROLE) {
    uint256 max = maxMint(to);
    if (shares > max) revert ERC4626ExceededMaxMint(to, shares, max);
    _mint(to, shares);
}
```

- **Why**：OZ 的内部 `_mint` 不走 public `mint`/`deposit` 的 `maxMint` 检查；若直接 `_mint` 会突破 1 亿硬上限。显式复用 `maxMint(to)` 让 admin 增铸与公众申购受同一上限，硬上限始终成立。
- **满额自然 revert 是预期**：部署后顶满时 `maxMint == 0`，`adminMint` revert——符合用户意图（只有 `redeem` 腾额后才需要、才能补回）。
- 复用 OZ 标准错误 `ERC4626ExceededMaxMint(receiver, shares, max)`，与公众申购报错一致。

### D3：免费铸（接受稀释），不收对价

`adminMint` 直接 `_mint(to, shares)`，不要求 `to` 转入 GLC。

- **Why**：本就用于「`redeem` 烧份额后补回」——补回的份额对应的资产已在持有人提走前属于该持有人，补回不是新增资本注入。
- **Trade-off**：若在金库尚有存量收益、`totalSupply` < `MAX_SHARES` 时给**新** `to` 免费铸，新持有人会立即按比例分走存量收益（稀释老持有人）。这是治理纪律问题（见 Risks），合约不强制——`adminMint` 的安全用法是仅在持有人 `redeem` 提空对应份额后用于补回同一持有人。

## Risks / Trade-offs

- **[admin 增铸稀释老持有人]** → admin 在金库有存量收益时给新地址免费铸份额 = 当场把老持有人既得 GLC 分一块给新人。Mitigation：合约层把增铸限死在 `maxMint` 硬上限内（不会无限稀释）；治理层在合约注释 + 部署 runbook 写明「仅在持有人 redeem 腾额后用于补回」，并强烈建议 `owner_` 用多签。
- **[admin 私钥被盗 → 在腾出额度内增铸给攻击者]** → 增铸上限受 `MAX_SHARES` 约束（最多铸到 1 亿），不能凭空无限增发；但满额前的额度仍可被滥用。Mitigation：`owner_` 用 Safe 多签；`adminMint` 触发链可被链下监控。
- **[语义破坏既有 spec]** → 原 spec「纯无特权」被 REMOVED。Mitigation：本变更 spec delta 显式 REMOVE 并给 Migration；过 `/security-review` 复核权限扩张。
- **[ERC165 接口变化]** → 继承 `AccessControl` 后 `supportsInterface` 返回值变化。Mitigation：SalesVault 无下游依赖其 ERC165；下游只 `safeTransfer` GLC，不查接口。
