## Why

ScratchCard 的 `PrizePool` 已自实现一套「经 `this.` 自调用制造独立 frame、try/catch 兜底、永不 revert」的软付款（`_transferOnly` + `payBonus`），用于回调内付奖失败时转 pull 兜底而不 brick entropy 回调。GreatLottoCore 的 `fulfillDraw` 同样在回调内对中奖者 push 转账，却**没有**这层保护——push 失败即 revert 整个回调 → `CALLBACK_FAILED`。这层封装不依赖任何下游业务字段，应下沉到 `PrizePoolBase` 成为奖池基类标准能力，两个下游同构复用、消除重复与漂移。

本 change 是跨仓主题 `2026Q2-prizepool-softpay` 的**上游契约源**，先行定稿；下游 ScratchCard（`prizepool-softpay-contract`）与 GreatLottoCore（`prizepool-softpay-core`）各起一份对齐 change。设计依据：`infrastructure/doc/prizepoolbase-softpay-design.md`。

## What Changes

- `PrizePoolBase` 新增 `_payoutTransfer(address to, uint256 amount) external`：仅 `msg.sender == address(this)` 自调用守卫，内部 `_transferTo(_getCoin(), to, amount)`；制造独立 message-call frame 以隔离 catch 回滚边界。**MUST NOT** 改为 internal。
- `PrizePoolBase` 新增 `_softPay(address to, uint256 amount) internal`：`try this._payoutTransfer(to, amount) {} catch { _recordPendingPayout(to, amount); }`，push 失败转兜底、永不 revert。
- `PrizePoolBase` 新增私有聚合 `_pendingPayoutTotal`：在 `_recordPendingPayout` 自增、`claimPayout` 自减；新增 `pendingPayoutTotal() public view returns (uint256)`，供下游（GreatLottoCore）把滞留兜底资金纳入余额不变量。
- `IPrizePoolBase` 新增 `error ErrorUnauthorizedSelfCall;`（下游删除本地副本，统一来源）。
- `_recordPendingPayout` / `claimPayout` / `pendingPayoutOf` 既有签名与事件**不变**，仅内部增量维护聚合——纯增量、向后兼容，**非 BREAKING**。
- `PrizePoolBaseHarness` 暴露 `_softPay` 测试入口；新增单测覆盖软付款成功 / push 失败转兜底 / 自调用守卫 revert / 聚合随 record+claim 增减配平。

## Capabilities

### New Capabilities
（无）

### Modified Capabilities
- `prize-pool-base`: 新增「软付款（frame 隔离 + try/catch 兜底）」与「兜底欠款聚合 `pendingPayoutTotal`」两组 requirement；`IPrizePoolBase` 接口新增 `ErrorUnauthorizedSelfCall` 声明。既有 requirement 不变。

## Impact

- 代码：`contracts/base/PrizePoolBase.sol`、`contracts/interfaces/IPrizePoolBase.sol`、`contracts/test/PrizePoolBaseHarness.sol`、`test/**` 单测。
- 下游：ScratchCard / GreatLottoCore 经 pnpm symlink 立即可见新 API（无需发版）；各自起对齐 change 后切换。
- ABI：`PrizePoolBase` 新增 `_payoutTransfer` / `pendingPayoutTotal` 进 ABI（增量）；既有函数/事件签名不变。interface 仓暂不需对齐（前端未消费这些）。
- 安全：`_softPay` 在回调内的重入路径需 `/security-review` 复核；`pendingPayoutTotal` 是只读监控量。
