# dao-benefit-pool-single-track Specification

## REMOVED Requirements

### Requirement: 分润合约仅支持稳定币（GLC）

**Reason**: `DaoBenefitPool` 合约整体删除——销售分润不再经「遍历受益人列表逐个打款」的 DAO 利润池，改由 `SalesVault`（ERC4626）经转入自动按份额比例增值。

**Migration**: 销售分润目标地址从 `DaoBenefitPoolAddress` 改为 `SalesVaultAddress`（见 `prize-pool-base` 的 `_salesVaultTransfer`）。原 `executeBenefit(deadline)` 主动分发入口取消；份额持有人改用 `SalesVault.redeem`/`withdraw` 按比例提取（见 `sales-vault` 能力）。

### Requirement: 构造参数收敛

**Reason**: `DaoBenefitPool` 合约整体删除，其构造函数随之移除。

**Migration**: 部署模块（`ignition/modules/infrastructure.js` 及下游）删除 `new DaoBenefitPool(...)`，改为部署 `SalesVault(asset_=GLC, owner_)`。
