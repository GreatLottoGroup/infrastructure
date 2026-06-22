## Context

完整设计与决策推演见 [doc/sales-vault-redesign-design.md](../../../doc/sales-vault-redesign-design.md)（本文件是其 OpenSpec 对齐版，保留决策与取舍，省略行级实现）。

现状：销售利润经 DAO 分红下发——`PrizePoolBase._mintDaoCoinToPayer` 给买家增发 GLDC（`DaoCoin`，ERC20Votes），销售分润打入 `DaoBenefitPool`，`executeBenefit` 遍历「持 ≥10k GLDC 的受益人列表」按 `balance/totalSupply` O(n) 分发。约束：

- 这是 **infrastructure 上游打穿**的破坏性变更——`PrizePoolBase` 是 ScratchCard / GreatLottoCore 两仓 `PrizePool.sol` 的基类，构造签名 + helper 改动会让两下游编译失败，必须配套下游 change 原子推进。
- 资产币为 GLC（多稳定币白名单经 `getAmount` 统一放大为 18 位）；金库收的是 **wei 级 GLC**。
- 用户已锁定 6 项决策（见下 Decisions），无 Open Questions。

## Goals / Non-Goals

**Goals:**
- 用 `SalesVault is ERC4626` 替换 `DaoBenefitPool`，销售分润转入即按份额比例自动增值（O(1)，无主动分发）。
- 份额硬上限 1 亿、owner 初始全持、开放公众现价申购（offset=6 防 inflation attack）。
- 彻底移除 DAO 治理币 + 分红链路（`DaoCoin` / `DaoBenefitPool` / `BenefitPoolBase` / `BeneficiaryBase` + 接口）。
- 保持 `PrizePoolBase` 的收款 / 转账 / 渠道分润 / softpay 兜底等正交能力**完全不变**。

**Non-Goals:**
- 不改渠道分润（channel 档）语义、不改 softpay/claimPayout 兜底、不改 `_colletWithCoin`/`_transferTo`。
- 不改 GreatLottoCore 的 INVESTOR 68% 投资分润档（独立机制，正交）。
- 不引入金库治理（无 owner sweep/pause/topUp 后门）。
- 本 change 只覆盖 infrastructure；下游 ScratchCard / Core / interface 适配各自单独 change（本 change 的 Impact 列明依赖顺序）。

## Decisions

### D1：分润语义——转入即增值，删除主动分发
销售分润 = 直接 `safeTransfer` GLC 进金库 → 抬 `totalAssets`、不动 `totalSupply` → 每份额按 `convertToAssets` 自动增值。份额持有人随时 `redeem` 取走。**替代方案**：保留 `executeBenefit` 式主动分发（被否——O(n) gas、列表维护、≥10k 门槛，正是要消除的复杂度）。

### D2：删除整条 DAO 链路（激进方案）
删 `DaoCoin` / `DaoBenefitPool` / `BenefitPoolBase` / `BeneficiaryBase` + 接口。**替代方案**：保守（保留 `DaoCoin` 供治理投票，仅断增发路径）——被否，用户确认治理不再用 GLDC。**取舍**：删合约不可逆；若未来需链上治理须重新引入治理币（已确认不需要）。

### D3：开放公众现价申购 + 1 亿硬上限 + offset=6
`deposit`/`mint` 公开，按 ERC4626 现价给份额（稳态无套利、不稀释现有持有人）；`maxMint = MAX_SHARES - totalSupply`、`maxDeposit` 由其换算，顶满走 OZ 原生 `ERC4626ExceededMaxDeposit` revert；`_decimalsOffset()=6` 防 inflation attack。**替代方案 A**：永久禁用 deposit/mint（被否——用户要「赎回后可再入金」的活动盘子）。**替代方案 B**：owner-only 无偿 `topUp` 补铸（被否——已累积分润时无偿补铸稀释其他持有人；现价 deposit 无此问题）。

### D4：标准 redeem/withdraw 对所有份额持有人开放，纯无特权
金库无 Ownable/AccessControl，owner 仅初始拿全部份额，运行期与任意持有人等权。份额经 ERC20 自由二级流转。**替代方案**：禁用 redeem 只留 owner sweep（被否——放弃 ERC4626「份额=可流转收益权」的核心价值）。

### D5：`PrizePoolBase` 改造（破坏性，正交保持）
构造 `(coin, daoCoinAddr, daoBenefitPoolAddr, salesChannelAddr, owner, chRate, sellRate)` → `(coin, salesVaultAddr, salesChannelAddr, owner, chRate, sellRate)`。删 `DaoCoinAddress` / `_mintDaoCoinToPayer` / `import IDaoCoin`；`DaoBenefitPoolAddress`→`SalesVaultAddress`、`_daoBenefitTransfer`→`_salesVaultTransfer`、`_distributeChannelAndDaoBenefits`→`_distributeChannelAndSalesBenefits`（计算逻辑与渠道档行为**逐字不变**，仅 sell 档目标地址语义从 DAO 池改为金库）。**替代方案**：保留旧 helper/immutable 名减少下游 churn（被否——名字含「Dao」会误导，下游本就要改构造，顺手改干净）。

### D6：单位贯通
金库 `asset` 必须是同一 GLC 地址；PrizePool 转入的是 `getAmount` 放大后的 wei 级 GLC，金库内**不再二次 getAmount**。`MAX_SHARES = 1e8 * 1e18` 与 GLC 18 位对齐。

## Risks / Trade-offs

- **构造签名破坏性变更** → 跨仓原子推进：infrastructure 先发包/更新 symlink，再改 ScratchCard+Core 构造，CI 全绿门；协调文档锁依赖顺序。
- **ERC4626 inflation attack**（开放 deposit 后 supply 被赎到极低时抢首存+捐赠抬价吞本金）→ `_decimalsOffset()=6`（OZ 推荐）+ 初始 supply 1 亿（须先大额 redeem 才逼近 0）；测试**必须**覆盖「大额 redeem→supply 极低→恶意 deposit+捐赠」序列验证防护生效。
- **初始即满致 deposit 总 revert**（`maxDeposit==0`）→ 属硬上限预期行为；前端/文档明示「须先有人 redeem 腾出额度」，避免误判为 bug。
- **上限换算取整**（`maxDeposit` 由 `maxMint` floor 换算）→ 锚定 shares 精确，assets 侧 floor 偏保守（宁少铸不超限），不破坏硬上限；fuzz 测试覆盖极限附近。
- **GLDC 语义残留** → 删 `DaoCoin` 后任何读 GLDC 余额做权限的下游/前端必须清除（interface 见记忆 `interface-abi-drift-dao-benefit.md`，这些 hook 已多次 ABI 漂移）。
- **单位贯通错误**（金库内误做 getAmount）→ 测试断言金库余额 == 转入 wei。
- **已部署网络迁移** → 旧 DAO 部署作废、重新部署整套（与既往一致）。

## Migration Plan

1. infrastructure：新增 `SalesVault.sol` + 改 `PrizePoolBase` + 删 DAO 链路 + 测试 → `forge test` 全绿。
2. 发包 / 更新下游 symlink（ScratchCard、Core 消费新 `PrizePoolBase`）。
3. ScratchCard + GreatLottoCore：各自 change 对齐构造、删 `_mintDaoCoinToPayer`、改部署模块、改测试 → 各仓测试绿。
4. interface：删 DAO hook、同步 ABI、加金库视图（如 `convertToAssets(balanceOf(owner))` 展示累积分润）。
5. 三道 review 门：`/flow-review-spec` → `requesting-code-review` → `/security-review`（合约仓必跑，本 change 触及资金路径 + ERC4626 攻击面）。
- **回滚**：本 change 未合并 main 前于 feature 分支隔离；删合约是不可逆语义收窄，回滚 = 还原分支（已部署测试网作废重部）。

## Open Questions

无。6 项决策（DAO 去留 / 提取模型 / redeem 开放对象 / 份额可转让 / 上限语义 / 开放申购安全前提）已于 2026-06-22 全部锁定，见 doc 设计文档 §6。
