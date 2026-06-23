## Context

`SalesChannel`（[contracts/SalesChannel.sol](../../../contracts/SalesChannel.sol)）当前是纯注册表：渠道方 `registerChannel` 登记拿到自增 `chnId`，购买流里 `PrizePoolBase._channelBenefitTransfer`（[contracts/base/PrizePoolBase.sol:178](../../../contracts/base/PrizePoolBase.sol)）按 `channelBenefitRate` 把渠道分润**直接 `safeTransfer` 打给渠道地址（EOA）**，并带一个 owner 可干预的 `bool status` 字段（`disableChannel` / `enableChannel`）。

约束：
- `PrizePoolBase` 构造已持有 `SalesChannelAddress`（immutable）与 `GreatLottoCoinAddress`，分润基数以 GLC 计价。
- 下游 ScratchCard / GreatLottoCore 的 `PrizePool` 经 `_distributeChannelAndSalesBenefits` → `_channelBenefitTransfer` 间接消费，源码无需改但须重编译重测。
- 工作区当前部署为 Test 版、未上主网（见仓库 MEMORY），可全新部署、不做历史迁移。

完整设计依据见 [doc/sales-channel-optimization-design.md](../../../doc/sales-channel-optimization-design.md)。

## Goals / Non-Goals

**Goals:**
- 去掉 owner 对渠道状态的干预（删 `disableChannel` / `enableChannel`）与 `status` 字段，收窄治理面。
- 新增渠道分页遍历，单页上限 20。
- 渠道分润改为「SalesChannel 合约托管 + 按 `chnId` 记账 + 渠道自提」的 pull-payment 模型。
- 暴露单渠道（`accruedOf` / `withdrawnOf` / `pendingOf`）与全局（`totalAccrued` / `totalWithdrawn`）账本，支撑偿付能力不变量。

**Non-Goals:**
- 不迁移旧合约历史链上数据（全新部署）。
- 不改 `channelBenefitRate` / `sellBenefitRate` 的计算逻辑与 `_distributeChannelAndSalesBenefits` 的 channelId 分支结构。
- 不改 SalesVault 销售档分润路径。
- 不在 base 强制 `channelRate + sellRate <= 1000` 的 cap（沿用既有 governance footgun 约定）。

## Decisions

### D1 — `SalesChannel` 权限模型用 `AccessControlPartnerContract`
`SalesChannel` 从 `Ownable` 迁到 `AccessControlPartnerContract`，记账入口 `creditChannel` 锁 `PARTNER_CONTRACT_ROLE`，部署后 owner（`DEFAULT_ADMIN_ROLE`）给两个 PrizePool 各授一次。
- **Why**：复用工作区 PrizePool / NFT 既有 PARTNER 模式，只授权合约非 EOA。
- **Alt**：保留 `Ownable` + 自建 `mapping crediter` 白名单 setter——拒绝，重复造轮子、与工作区不一致。
- owner 语义随之从 `owner()` 迁为 `DEFAULT_ADMIN_ROLE`。

### D2 — 部署后补授 PARTNER + 本地部署文件补充
`SalesChannel` 构造需 GLC 地址；PrizePool 构造已需 SalesChannel 地址——无环（GLC → SalesChannel → PrizePool）。部署后**必须**给两个 PrizePool 补授 SalesChannel 的 `PARTNER_CONTRACT_ROLE`，否则分润记账因缺角色 revert。各仓本地部署模块（ScratchCard `ScratchCardLocal.js` / GreatLottoCore 本地模块）+ `ignition/parameters/localhost.json` 须补 SalesChannel 部署、grantRole、GLC/SalesChannel 地址参数。

### D3 — 全新部署，不迁历史
新合约 id 从 1 起，旧 EOA 收款数据不继承。

### D4 — `withdraw` 强制提到自己
`withdraw()` 强制 `msg.sender == _channel[chnId].chn`（取调用方注册的 chnId），全额提到调用方自己，**不接受任意 `to`**，规避钓鱼授权。待提为 0 时 revert `SalesChannelNothingToWithdraw(chnId)`。

### D5 — `benefit == 0` 早退不记账
`_channelBenefitTransfer` 在 `benefit == 0`（极小额或费率调 0）时早退，不做空转账 + 空记账 + 空事件。

### D6 — 存在性判据从 `status` 改 `chn == address(0)`
`status` 移除后，`_channelBenefitTransfer` 与视图 getter 的存在性判据从 `status==false && chn==address(0)` 改为 `chn == address(0)`，语义等价（注册必写 chn，未注册读零地址）。

### D7 — 账本双口径，全局聚合两项
- 单渠道：`_accrued[chnId]`（含已提）/ `_withdrawn[chnId]`；`pendingOf = accrued - withdrawn`。
- 全局：`_totalAccrued`（仅 `creditChannel` 自增）/ `_totalWithdrawn`（仅 `withdraw` 自增）；全局待提 = `totalAccrued - totalWithdrawn`。
- 偿付能力：`coin.balanceOf(SalesChannel) >= _totalAccrued - _totalWithdrawn`；恒等式 `_totalAccrued == Σ accruedOf`、`_totalWithdrawn == Σ withdrawnOf`。

### D8 — 分页语义
`getChannelsPaged(startId, count)`：`count > 20` revert `SalesChannelPageTooLarge(count)`；`startId == 0` 规整为 1；`end = min(startId+count-1, _nextId-1)`；`startId > end` 返回空数组；否则按 id 升序填充 `ChannelInfo[]`（实际长度可能 < count）。上限常量 `MAX_CHANNEL_PAGE = 20`，与 ScratchCard `getCardOverviewBatch` ≤20 一致。

## Risks / Trade-offs

- [漏授 PARTNER 角色导致分润记账 revert，购买交易整体回滚] → 部署清单 + 检查脚本强制校验；本地部署模块内置 grantRole（D2）。
- [SalesChannel 现在托管 GLC，提款逻辑出错可锁死渠道资金] → 偿付能力 invariant 测试 + `withdraw` CEI（先记账后转账）+ `noDelegateCall`；`/security-review` 必跑。
- [上游接口打穿，下游 ABI / 测试漂移] → 跨仓清单覆盖 ScratchCard / GreatLottoCore 重编译重测 + interface ABI 重同步 + 渠道页改造；`/flow-review-spec` 把关。
- [`withdraw` 收款方限制 msg.sender==注册地址，渠道私钥丢失则资金不可达] → 可接受（与 EOA 直收同等风险面）；如需代提，留作后续治理增强，不在本次范围。
- [push→pull 改变下游 PrizePool 偿付能力假设：渠道分润 GLC 不再立即离开 PrizePool，而是先转入 SalesChannel] → 下游 PrizePool 偿付能力检查只看自身余额，渠道分润转出后即不计入，行为与 push 等价（资金都离开 PrizePool）；下游 invariant 测试复核。**实证（方案 review 核实）**：GreatLottoCore `PrizePool._checkInvariant`（约 L549）与 ScratchCard `PrizePool`（约 L104）的偿付能力左侧本就不含渠道分润——两个模型下渠道 benefit 都在 `_distributeChannelAndSalesBenefits` 内离开 PrizePool（push 给 EOA vs 转入 SalesChannel），离开后均不计入下游 invariant，故收款方变更对下游偿付能力**严格等价**，无需改下游 invariant 公式（仅断言收款地址变更）。

## Migration Plan

1. infrastructure：实现 `SalesChannel` / `ISalesChannel` / `PrizePoolBase._channelBenefitTransfer`，`forge test` + `forge coverage` 全绿。
2. 下游 ScratchCard / GreatLottoCore：重编译 + `forge test` 全绿；改 `PrizePool.t.sol` 分润断言。
3. 部署：GLC → SalesChannel → 各 PrizePool；部署后给两个 PrizePool 补授 SalesChannel 的 `PARTNER_CONTRACT_ROLE`（本地模块内置，主网走部署清单）。
4. interface：ABI 重同步 + hooks/渠道页改造。
5. Review 三道门：`/flow-review-spec` → `requesting-code-review` → `/security-review`。
- **Rollback**：全新部署、未上主网，回滚即不部署新合约 / 继续用旧版；无链上数据迁移负担（D3）。
