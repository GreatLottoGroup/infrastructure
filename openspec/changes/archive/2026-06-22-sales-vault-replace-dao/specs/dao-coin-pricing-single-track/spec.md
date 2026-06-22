# dao-coin-pricing-single-track Specification

## REMOVED Requirements

### Requirement: DaoCoin 单一定价

**Reason**: `DaoCoin`（GLDC 治理币）合约整体删除——购买不再给买家增发治理币份额，治理不再使用 GLDC（用户决策 2026-06-22）。

**Migration**: `PrizePoolBase._mintDaoCoinToPayer` 删除（见 `prize-pool-base`），下游购买路径不再调用 `mintToUser`。销售收益权改由 `SalesVault` 的 ERC4626 份额承载。

### Requirement: 旧 isEth 签名不再可用

**Reason**: `DaoCoin` 合约整体删除，其接口 `IDaoCoin`（含 `mintToUser` / `changePrice` 的任何签名）随之移除。

**Migration**: 任何 import `IDaoCoin` 或引用 `DaoCoin` 的下游合约 / 前端 ABI 必须清除（infrastructure 部署模块删 `DaoCoin` 部署与其 `PARTNER_CONTRACT_ROLE` 授权接线；interface 删 GLDC 相关 hook 与 `DaoCoin.json`）。
