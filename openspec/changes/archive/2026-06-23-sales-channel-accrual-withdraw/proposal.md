## Why

当前 `SalesChannel` 是纯注册表，渠道分润由 `PrizePoolBase._channelBenefitTransfer` **直接 push 给渠道 EOA**，且带一个 owner 可干预的 `status` 启用/禁用字段。push 模式在渠道地址无法收款（合约 revert / 代币黑名单）时会让整笔购买交易回滚；`status` 干预增加治理面与攻击面却无实际用途。改为「合约托管 + 渠道自提」的 pull-payment，与工作区 SalesVault / PrizePool 兜底（`claimPayout`）范式对齐，去掉 status 收窄治理面，并补齐渠道批量遍历能力。

设计依据：[doc/sales-channel-optimization-design.md](../../../doc/sales-channel-optimization-design.md)。

## What Changes

- **BREAKING** 删除 `SalesChannel.disableChannel` / `enableChannel`（owner 状态干预下线）及对应 error（`SalesChannelAlreadyDisabled` / `SalesChannelAlreadyEnabled`）/ event（`SalesChannelDisabled` / `SalesChannelEnabled`）。
- **BREAKING** 删除 `ChannelInfo.status` 字段；视图 getter `getChannelByAddr` / `getChannelById` 返回值去掉 `bool status`。
- **BREAKING** 渠道分润不再直接打给渠道 EOA：`SalesChannel` 改为持有 GLC 并按 `chnId` 记账，新增 `creditChannel`（仅 `PARTNER_CONTRACT_ROLE`）/ `withdraw`（渠道自提，强制 `msg.sender == 注册地址`）。
- **BREAKING** `SalesChannel` 权限模型从 `Ownable` 迁到 `AccessControlPartnerContract`；构造新增 GLC 资产币地址参数。
- 新增分页遍历 `getChannelsPaged(startId, count)`，单页上限常量 `MAX_CHANNEL_PAGE = 20`。
- 新增账本查询：单渠道 `accruedOf` / `withdrawnOf` / `pendingOf`；全局聚合 `totalAccrued` / `totalWithdrawn`。
- **BREAKING** `PrizePoolBase._channelBenefitTransfer` 收款方从渠道 EOA 改为 SalesChannel 合约：`_transferTo(coin, SalesChannelAddress, benefit)` 后调 `creditChannel(chnId, benefit)`；存在性判据从 `status==false && chn==address(0)` 改为 `chn == address(0)`；`benefit == 0` 早退不记账。

## Capabilities

### New Capabilities
- `sales-channel`: 销售渠道注册表 + 渠道分润托管账本（注册/改名/分页遍历/PARTNER 记账/渠道自提/累计与待提查询/偿付能力不变量）。

### Modified Capabilities
- `prize-pool-base`: `_channelBenefitTransfer` 渠道分润打款语义变更——收款方由渠道 EOA 改为 SalesChannel 合约并触发 `creditChannel` 记账；去 `status` 判据。`_distributeChannelAndSalesBenefits` 调用点不变、被调函数内部行为改变。

## Impact

- **infrastructure**：`contracts/SalesChannel.sol`（重构主体）、`contracts/interfaces/ISalesChannel.sol`（接口收窄+扩展）、`contracts/base/PrizePoolBase.sol`（`_channelBenefitTransfer`）；测试 `test/foundry/SalesChannel.t.sol` 重写、`PrizePoolBase.t.sol` + harness 断言改写、新增 SalesChannel 偿付能力 invariant。
- **ScratchCard / GreatLottoCore**（下游，无源码改动）：经 `_distributeChannelAndSalesBenefits` 间接调用，须重编译 + `forge test` 全绿；`PrizePool.t.sol` 分润断言改写（渠道收款方→SalesChannel + `pendingOf` 增长）；部署后给各自 `PrizePool` 补授 SalesChannel 的 `PARTNER_CONTRACT_ROLE`，本地部署模块 + `localhost.json` 补 SalesChannel/GLC 地址与 grantRole。
- **interface**：`abi/SalesChannel.json` 重同步；`hooks/contracts/SalesChannel.js` 删 disable/enable/statusEl、加 `getChannelsPaged`/`withdraw`/`pendingOf` 等；渠道页改分页列表 + 待提收益 + 提取按钮、移除启用/禁用 UI。
- 跨仓性质：上游接口打穿 → 须走跨仓流程 + `/flow-review-spec`；合约仓必跑 `/security-review`。
