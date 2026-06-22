## Why

`SalesVault` 当前是「纯无特权 ERC4626 + 构造铸满 1 亿份额给 owner」。这带来一个治理痛点：份额 = 销售分润股权，而提取分润的唯一方式是 ERC4626 `redeem`/`withdraw`——**烧掉份额**。于是持有人每提一次收益就丧失等比例的未来分润股权，「提收益」与「持股权」被标准 ERC4626 强行绑定，无法分离。又因构造已顶满 `MAX_SHARES`，被烧掉的份额无任何合规途径补回。

新增一个受 `maxMint` 上限约束的 admin 增铸入口，即可在持有人 `redeem` 腾出额度后把份额补回，实现「提收益不丧失股权」，且增铸总量永远受 1 亿硬上限约束。

## What Changes

- `SalesVault` 继承 OpenZeppelin `AccessControl`；构造时给 `owner_` 授 `DEFAULT_ADMIN_ROLE`（构造仍 `_mint(owner_, MAX_SHARES)`，`MAX_SHARES` 不变）。
- 新增 `adminMint(uint256 shares, address to)`（参数顺序对齐 ERC4626 `mint(shares, receiver)`）：`onlyRole(DEFAULT_ADMIN_ROLE)`，复用 `maxMint(to)` 上限校验后 `_mint(to, shares)`。满额时（`maxMint == 0`）自然 revert `ERC4626ExceededMaxMint`，仅当 `redeem` 腾出额度时可铸。
- **BREAKING（语义）**：`SalesVault` 不再是「纯无特权、无任何 owner 后门」合约——新增 admin 专属增铸入口。原 spec 的「纯无特权」要求被本变更显式取代。
- 不动：`deposit` / `mint` / `redeem` / `withdraw` / `maxMint` / `maxDeposit` / `_decimalsOffset` / `MAX_SHARES` 全部保留现状。公众 `deposit`/`mint` 仍由构造顶满机制天然封死（满额时 `maxMint` 恒 0）。

## Capabilities

### New Capabilities
<!-- 无新增独立能力，沿用现有 sales-vault spec -->

### Modified Capabilities
- `sales-vault`: 取消「纯无特权——无 owner 后门」要求；新增「admin 受上限约束增铸份额」要求（构造授 `DEFAULT_ADMIN_ROLE` + `adminMint` 复用 `maxMint` 校验）。`redeem`/`withdraw`/公众申购/virtual shares/硬上限等其余要求不变。

## Impact

- **代码**：仅 `contracts/SalesVault.sol`（infrastructure 仓）。新增 `AccessControl` 继承、构造一行授权、一个 `adminMint` 函数。引入 ERC165 `supportsInterface`（与 ERC4626/ERC20 无冲突）。
- **下游**：零打穿。`PrizePoolBase` 仍只 `safeTransfer` GLC 进金库；ScratchCard / GreatLottoCore 的 `PrizePool` 构造引用的是 `salesVaultAddress`，不依赖 SalesVault 内部接口。`adminMint` 是 SalesVault 自身新增入口，无人调用即无影响。
- **部署**：`SalesVault` 独立部署，构造参数 `(asset_, owner_)` 不变；部署后 `owner_` 自动持有 `DEFAULT_ADMIN_ROLE`。
- **审计**：新增 admin 增铸权属生产合约权限扩张，须过 `/security-review`（重点核查：增铸是否能突破 1 亿硬上限、对现有持有人的稀释语义、角色授予是否仅 owner）。
- **测试**：infrastructure 仓 Foundry（`test/foundry/`）须新增 `adminMint` 用例：满额 revert、redeem 腾额后可铸、超额 revert、非 admin revert、铸后不破 `MAX_SHARES`。
