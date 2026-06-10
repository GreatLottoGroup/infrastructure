## Context

完整设计依据见 `infrastructure/doc/prizepoolbase-softpay-design.md`（§1–§2 与决策表）。要点：

- ScratchCard `PrizePool` 已自实现 `_transferOnly`（external 自调用）+ `payBonus`（CEI 扣减后 try/catch 软付款）。`PrizePoolBase` 现已具备 `_transferTo` / `_getCoin` / `_recordPendingPayout` / `claimPayout` / `pendingPayoutOf`，唯独缺「frame 隔离 + try/catch」这层封装。
- GreatLottoCore `fulfillDraw`（entropy 回调内）对中奖者 push 转账，无 push-失败保护。
- 本 change 只动 infrastructure；把封装下沉为基类标准能力，并暴露兜底欠款聚合供下游不变量复用。

## Goals / Non-Goals

**Goals:**
- 在 `PrizePoolBase` 提供可复用的 `_softPay`（永不 revert 的软付款）与 `_payoutTransfer`（frame 隔离原语）。
- 暴露 `pendingPayoutTotal()` 聚合，使 GreatLottoCore 能把「软付款失败而滞留合约内的资金」纳入余额不变量。
- 纯增量、向后兼容：既有 `_recordPendingPayout` / `claimPayout` / `pendingPayoutOf` 签名与事件不变。

**Non-Goals:**
- 不在本 change 改任何下游（ScratchCard / GreatLottoCore 各起对齐 change）。
- 不引入新的余额不变量到 `PrizePoolBase` 自身（base 不持有业务账本；不变量是下游 Core 的事）。
- 不改分润 / 收款 / 治理 setter 等既有能力。

## Decisions

- **D1：软付款下沉到 base。** 不依赖任何下游字段，纯基础设施；两个下游同构复用，消除重复与漂移。
- **D2：`_payoutTransfer` 为 external + `msg.sender==address(this)` 守卫，禁止改 internal。** 必须经 `this._payoutTransfer(...)` 制造独立 message-call frame，才能让其 revert 只回滚该 frame、不回滚调用方在 `_softPay` 之前写入的账本扣减。改 internal 则共用同一 frame，frame 隔离失效、重复计账修正不成立。
- **D3：`ErrorUnauthorizedSelfCall` 放 `IPrizePoolBase`。** 与既有 `ErrorNoPendingPayout` 并列；下游删本地副本，防接口漂移。
- **D4：`_payoutTransfer` 不加 `onlyRole`。** 唯一调用者是 `this`（经 `_softPay`），而 `_softPay` 由各下游 role-gated 函数内部触发；自调用守卫已足够，外部直调一律 revert。
- **D5：聚合 `_pendingPayoutTotal` 由 base 维护并经 `pendingPayoutTotal()` 暴露。** 在既有 `_recordPendingPayout` 自增、`claimPayout` 自减，O(1) 配平。对无余额不变量的 ScratchCard 是无害纯增量；对 Core 是不变量配平的必要项。备选「Core 自维护一份总额」会重复记账、易漂移，劣。
- **D6：CEI 契约写入 `_softPay` 文档与 spec。** 调用方必须先扣自身账本再 `_softPay`，否则 push 失败时配平不成立——这是 base 对调用方的约束，spec 以 scenario 固化。

## Risks / Trade-offs

- **重入**：`_payoutTransfer` 经 SafeERC20 向受信白名单 GLC（稳定币代理）转账，风险面与现状一致；`claimPayout` 仍 `noDelegateCall`。`_softPay` 在回调内被调用时，收款方合约可能在 receive 中回调本合约——须在 `/security-review` 复核（GLC 为稳定币代理、非任意 ERC20，回调面有限，但需确认）。
- **下划线 external 命名**：`_payoutTransfer` 带下划线却 external，刻意偏离惯例以标记「仅供 `this.` 自调用、禁止当公共 API」，沿用 ScratchCard `_transferOnly` 先例；在 NatSpec 明确说明。
- **聚合可信度**：`pendingPayoutTotal` 只由 base 内部两处增减维护，无外部写入口，与 per-user mapping 总和恒等；下游只读复用，不得另设写路径。
- **向后兼容**：新增函数进 ABI 但不改既有签名；两个下游在未起对齐 change 前不受影响，可分阶段落地。
