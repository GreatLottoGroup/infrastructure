> **进度（2026-06-10）**：实现 + 单测全部完成并跑通（`PrizePoolBase.test.js` **47 passing**）；strict validate 通过；方案 review approved。仅剩 `/security-review` 未跑。

## 1. IPrizePoolBase 接口

- [x] 1.1 在 `contracts/interfaces/IPrizePoolBase.sol` 新增 `error ErrorUnauthorizedSelfCall;`（与既有 `ErrorNoPendingPayout` 并列）

## 2. PrizePoolBase 软付款能力

- [x] 2.1 新增 `_payoutTransfer(address to, uint256 amount) external`：守卫 `if (msg.sender != address(this)) revert ErrorUnauthorizedSelfCall();`，通过后 `_transferTo(_getCoin(), to, amount)`；NatSpec 注明「仅供 `this.` 自调用、禁止改 internal、禁止外部直调」
- [x] 2.2 新增 `_softPay(address to, uint256 amount) internal`：`try this._payoutTransfer(to, amount) {} catch { _recordPendingPayout(to, amount); }`；NatSpec 注明「调用方须先扣自身账本（CEI）、本函数永不 revert」

## 3. 兜底欠款聚合

- [x] 3.1 新增私有状态 `uint256 private _pendingPayoutTotal;`
- [x] 3.2 在 `_recordPendingPayout` 内追加 `_pendingPayoutTotal += amount;`（事件与既有逻辑不变）
- [x] 3.3 在 `claimPayout` 内、清零 per-user 之后追加 `_pendingPayoutTotal -= amount;`
- [x] 3.4 新增 `function pendingPayoutTotal() public view returns (uint256) { return _pendingPayoutTotal; }`

## 4. 测试 harness 与单测

- [x] 4.1 `contracts/test/PrizePoolBaseHarness.sol` 暴露 `softPay` 调用入口（`_payoutTransfer` 已是 base external，直调即可测守卫）
- [x] 4.2 单测 14.2：`_softPay` push 成功 → 不记兜底、`pendingPayoutOf` 不变、`pendingPayoutTotal` 不变
- [x] 4.3 单测 14.3：`_softPay` 转账失败 → 不 revert、`pendingPayoutOf` 与 `pendingPayoutTotal` 各增 `amount`、合约余额不变、emit `PayoutPending`。（注：infra 侧用「余额不足」触发 catch；「拒收合约」触发 + 资金留存的更完整路径在下游 Core 的 `MockBlockableCoin` 用例覆盖）
- [x] 4.4 单测 14.1：直接外部调用 `_payoutTransfer` → revert `ErrorUnauthorizedSelfCall`
- [x] 4.5 单测 14.4：`_softPay(to, 0)` → 不 revert、不记兜底
- [x] 4.6 单测 14.6：`claimPayout` 后 `pendingPayoutTotal` 与 `pendingPayoutOf` 同步归减、配平
- [x] 4.7 单测 14.5：多用户多次 record + 部分 claim 后，`pendingPayoutTotal == Σ pendingPayoutOf(user)`

## 5. 验收

- [x] 5.1 `npx hardhat compile` 通过（合约体积无异常增长）
- [x] 5.2 `npx hardhat test test/runTest/PrizePoolBase.test.js` 全绿（47 passing，含 Section 14 新增 + 既有回归）
- [x] 5.3 `openspec validate prizepool-softpay-infra --strict` 通过
- [x] 5.4 方案 review（`/flow-review-spec`）✅ **approved**；`/security-review` ✅ **无高置信发现**（确认 GLC 无 transfer hook→`_softPay` 不可重入；frame 隔离无重复计账；`_pendingPayoutTotal`==Σ per-user；自调用守卫无新特权面）
