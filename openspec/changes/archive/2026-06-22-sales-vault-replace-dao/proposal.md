## Why

现行「销售利润」通过一套 DAO 分红机制下发：购买时给买家增发 GLDC 治理币份额，销售分润打入 `DaoBenefitPool`，再由 `executeBenefit` 遍历「持 ≥10k GLDC 的受益人列表」按比例 O(n) 分发。该机制状态多、gas 随受益人数增长、且把「销售收益权」与「治理投票币」耦合在一起。本次将其替换为一个继承 OZ ERC4626 的销售金库（vault）：销售分润直接转入金库即按份额比例自动增值，O(1) 账本、收益权可作为 ERC20 份额自由流转。

## What Changes

- **新增 `SalesVault`**：`is ERC4626`，资产币为 GLC，份额硬上限 1 亿，部署时全部铸给 owner。销售分润由各 PrizePool 直接 `safeTransfer` GLC 进金库（抬 `totalAssets`、不动 `totalSupply` → 每份额增值）；份额持有人凭标准 `redeem`/`withdraw` 按比例提走 GLC。
- **开放公众现价申购 + 硬上限**：`deposit`/`mint` 公开，受 `maxDeposit`/`maxMint` 卡在 1 亿份额上限（初始即满 → 须先 redeem 才能 deposit）；`_decimalsOffset() = 6` 提供 virtual shares 防 ERC4626 inflation attack。无 owner 后门 / 无 topUp / 无 sweep。
- **BREAKING — `PrizePoolBase` 构造签名变更**：去掉 `daoCoinAddr` 参数；`daoBenefitPoolAddr` → `salesVaultAddr`。`DaoCoinAddress` immutable 删除，`DaoBenefitPoolAddress` → `SalesVaultAddress`。
- **BREAKING — 删除 `PrizePoolBase._mintDaoCoinToPayer`**：购买不再给买家增发 GLDC。`_daoBenefitTransfer` → `_salesVaultTransfer`，`_distributeChannelAndDaoBenefits` → `_distributeChannelAndSalesBenefits`（语义化改名）。
- **BREAKING — 删除整条 DAO 治理币 + 分红链路**：删除合约 `DaoCoin.sol` / `DaoBenefitPool.sol` 与基类 `BenefitPoolBase.sol` / `BeneficiaryBase.sol`，及接口 `IDaoCoin` / `IBeneficiaryBase` / `IBenefitPoolBase`。（用户决策：治理不再使用 GLDC。）
- **部署模块**：`ignition/modules/infrastructure.js` 删 `DaoCoin` / `DaoBenefitPool` 部署，新增 `SalesVault`（构造传 GLC + owner）。

## Capabilities

### New Capabilities
- `sales-vault`: ERC4626 销售利润金库——固定 1 亿份额、owner 初始全持、开放现价申购（硬上限 + offset=6 防护）、标准 redeem/withdraw、销售分润经 transfer 入库自动增值。

### Modified Capabilities
- `prize-pool-base`: 构造签名去 `daoCoinAddr`、`daoBenefitPool`→`salesVault`；删 `_mintDaoCoinToPayer` 与 `DaoCoinAddress`；`_daoBenefitTransfer`→`_salesVaultTransfer`、`_distributeChannelAndDaoBenefits`→`_distributeChannelAndSalesBenefits`（行为不变，仅分润目标地址语义从 DAO 池改为金库）。
- `dao-benefit-pool-single-track`: **REMOVED**——`DaoBenefitPool` 合约删除，分润不再经此池。
- `dao-coin-pricing-single-track`: **REMOVED**——`DaoCoin` 合约删除，不再增发治理币份额。

## Impact

- **infrastructure（本仓）**：新增 `SalesVault.sol`；改 `PrizePoolBase.sol` + `IPrizePoolBase`（若涉及）；删 4 个合约/基类 + 3 个接口；改部署模块；改 Foundry 测试（删 DAO 测试、加 SalesVault 测试含 inflation-attack 序列）。
- **下游 ScratchCard（跨仓 BREAKING）**：`contracts/PrizePool.sol` 构造对齐新签名、删 `_mintDaoCoinToPayer` 调用、helper 改名；部署模块去 DaoCoin 接线；测试断言改动。需配套下游 change。
- **下游 GreatLottoCore（跨仓 BREAKING）**：同 ScratchCard。其 `_collect` 的 INVESTOR 68% 档**正交不受影响**。需配套下游 change。
- **下游 interface（跨仓）**：删 DAO 分红 hook（`executeBenefit`/GLDC 余额/受益人列表）；同步 ABI（新增 `SalesVault.json`、删 `DaoCoin.json`/`DaoBenefitPool.json`、更新 `PrizePool.json`）；`address.json` 加 `SalesVault`。
- **协调文档**：`.claude-workspace/coordination/2026Q2-sales-vault-replace-dao.md` 记录依赖顺序（infrastructure → 发包/symlink → ScratchCard+Core → interface）。
- **已部署网络**：旧 `DaoCoin`/`DaoBenefitPool` 部署作废，本套合约重新部署（与既往 feature 分支重部署一致）。
