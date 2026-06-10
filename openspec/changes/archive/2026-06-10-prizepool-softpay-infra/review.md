status: approved
reviewed: 2026-06-10
reviewer: independent spec reviewer (flow-review-spec)

# Review — prizepool-softpay-infra (CONTRACT-SOURCE of 2026Q2-prizepool-softpay)

Overall: **approved**. No FAIL on any of the 6 dimensions. Two non-blocking nits recorded under "Suggested (non-blocking)".

## D1 Scope single — PASS

The change does exactly one thing: sink the "frame-isolated soft-pay" capability (`_payoutTransfer` + `_softPay`) into `PrizePoolBase`, plus the supporting aggregate `pendingPayoutTotal()` and the `ErrorUnauthorizedSelfCall` declaration move. Non-Goals explicitly fence off downstream edits (ScratchCard/Core each own a separate aligned change) and refuse to add any new balance invariant to base itself (design Goals/Non-Goals, D-table D1/D6/D8). `pendingPayoutTotal` is not scope-creep — it is the minimal aggregate the soft-pay capability requires for the Core consumer's invariant, and design §2.2 justifies it as part of the same capability.

## D2 Breaking annotation — PASS

The "additive, non-BREAKING" claim is truthful. Verified against the real artifacts:

- `_payoutTransfer(address,uint256) external` and `pendingPayoutTotal() public view` are **new** symbols entering the ABI. New external/public functions are additive — no existing selector changes, no existing function is removed or re-typed. Confirmed against `contracts/base/PrizePoolBase.sol` and `contracts/interfaces/IPrizePoolBase.sol`: no signature in the current interface is touched.
- `_recordPendingPayout` / `claimPayout` / `pendingPayoutOf` keep identical signatures and identical events (`PayoutPending` / `PayoutClaimed`). The only edit is internal `+=`/`-=` aggregate maintenance — observable behavior unchanged.
- `ErrorUnauthorizedSelfCall` moving **into** `IPrizePoolBase` is purely additive at the infra layer: the current `IPrizePoolBase.sol` does not declare it, so adding an error declaration cannot break any existing consumer. The spec delta correctly lists this under MODIFIED Requirement "IPrizePoolBase 接口" (adding one error line to an existing requirement) rather than mislabeling it as a new capability.
- Could any consumer break? Checked downstream: `ScratchCard/contracts/PrizePool.sol` currently declares its **own local** `error ErrorUnauthorizedSelfCall;` (line 23). Inheriting the same-named error from `IPrizePoolBase` while also defining it locally is a Solidity duplicate-declaration compile error — but **only if the downstream both inherits and keeps the local copy in the same compilation**. That collision is owned and resolved by the downstream `prizepool-softpay-contract` change (which deletes the local copy). For the **infra change in isolation**, nothing breaks: ScratchCard/Core without their aligned changes still compile because they do not yet import the new error from base into a conflicting scope. The phased-rollout claim (design §7, coordination "non-BREAKING" checkbox) holds: base ships first, downstreams cut over independently. Annotation is honest.

## D3 Decisions covered by tasks — PASS

Every design decision maps to a task, and no task lands outside design:
- D1 (sink to base) → tasks §2 as a whole. D2 (`_payoutTransfer` external + self-call guard, never internal) → 2.1 (+ spec ADDED req with explicit MUST be external / MUST NOT internal). D3 (`ErrorUnauthorizedSelfCall` in IPrizePoolBase) → 1.1. D4 (no `onlyRole`, self-call guard suffices) → 2.1 (guard only, no role). D5 (`_pendingPayoutTotal` maintained by base + exposed) → 3.1–3.4. D6 (CEI contract documented in NatSpec + spec) → 2.2 NatSpec note + spec ADDED req "_softPay" CEI clause + scenario.
- Reverse check: tasks 4.1–4.7 (harness + unit tests) and 5.x (acceptance) are implementation/verification of the above, not new scope. No orphan task.

## D4 Cross-repo consistency — PASS

Signatures match across all three repos:
- `_softPay(address,uint256) internal` — infra design §2.1; consumed verbatim by ScratchCard delta ("`_softPay(to, amount)`") and Core delta ("`_softPay(winner, paid)`", "`_softPay(winner, topBonusAmount)`"). Match.
- `_payoutTransfer(address,uint256) external` — infra-only, downstreams do not call directly (coordination contract table row 2). Match.
- `pendingPayoutTotal() public view returns (uint256)` — infra; Core delta uses it verbatim in `_checkInvariant` as `_normalPool + _rollingPool + pendingPayoutTotal() == balanceOf`. ScratchCard delta explicitly does NOT consume it (D8 asymmetry). Match.
- `ErrorUnauthorizedSelfCall` — infra declares in `IPrizePoolBase`; ScratchCard deletes local copy. Match.
- Dependency order: `infrastructure → {ScratchCard, Core}` (parallel), interface untouched. Acyclic and sound — infra is leaf-upstream via pnpm symlink, no downstream symbol flows back into base. Coordination doc dependency graph and merge order agree.

## D5 Irreversible / fund risk — PASS (rigorous verification below)

The "debit once + record once" accounting is balanced and the reentrancy surface is adequately specified.

(a) **Does external `_payoutTransfer` genuinely create a separate frame so its revert does NOT roll back the caller's prior ledger debit?** — YES. `_softPay` invokes `this._payoutTransfer(...)`, i.e. an external `CALL` to the contract's own address. In the EVM an external self-call is a distinct message-call frame with its own revert boundary; `try/catch` around it catches the inner revert and resumes the outer frame with all prior state writes (the caller's `_debitPrizePool` / pool decrement done BEFORE `_softPay`) intact. Had `_payoutTransfer` been `internal`, it would share the caller's frame and its revert would unwind the whole outer frame including the debit — the design's D2 rationale is correct, and the spec encodes "MUST be external / MUST NOT internal" as a normative requirement plus a guard scenario. This is the load-bearing correctness property and it is correctly captured.

(b) **Does `_pendingPayoutTotal` always equal Σ per-user `_pendingPayouts`?** — YES, by construction. The aggregate is mutated in exactly the two places the per-user mapping is mutated, by the same `amount`: `_recordPendingPayout` does `_pendingPayouts[user] += amount; _pendingPayoutTotal += amount;` and `claimPayout` does `_pendingPayouts[msg.sender] = 0; _pendingPayoutTotal -= amount;` (where `amount` is the just-read per-user balance). No other write path exists (`private` field, no setter). Verified against current source: `claimPayout` reads `amount`, checks `!= 0`, zeroes the per-user slot, then transfers — the task inserts the `-= amount` between zeroing and transfer, preserving CEI. So the invariant `_pendingPayoutTotal == Σ pendingPayoutOf(user)` is maintained at O(1) with no double-count. Task 4.7 asserts exactly this. Good.

(c) **Any path where `_softPay` could revert and propagate?** — Effectively none for the documented usage. `_softPay`'s only statement is `try this._payoutTransfer(...) {} catch { _recordPendingPayout(...); }`. The success path returns; the catch path calls `_recordPendingPayout`, which is pure storage writes + event (cannot revert under normal gas). The one theoretical propagation path is out-of-gas inside the catch (no GLC reentrancy or arithmetic there) — bounded and equivalent to any storage write; acceptable. The `amount == 0` case is covered: `_payoutTransfer → _transferTo` early-returns at `amount==0`, so the try succeeds and no pending is recorded (spec scenario "amount == 0 视为成功不记兜底", task 4.5). No revert-propagation gap.

**Reentrancy:** `_payoutTransfer` routes through `_transferTo → SafeERC20.safeTransfer` on the trusted GLC stablecoin proxy (not an arbitrary ERC20), so the callee-controlled callback surface is the GLC proxy, not an attacker token. `claimPayout` retains `noDelegateCall`. The design (§7) and proposal Impact both flag the callback-in-`_softPay` path for `/security-review` rather than asserting it away — appropriate for a contract repo. CEI ordering (debit before `_softPay`) is encoded as a MUST in the spec and enforced as a caller contract, so even a reentrant callee re-entering during the (already-completed) push cannot observe an un-debited ledger. No under-specified double-count.

## D6 Alternatives — PASS

Design records rejected alternatives with rationale: §7 D5-备选 ① "treat soft-pay failure as refund to pool" (rejected: breaks "funds already belong to winner", conflicts with base `claimPayout`) and ② "Core maintains its own pending total" (rejected: duplicate accounting, drift-prone) — also restated in D-table D5. D8 records the rejected "ScratchCard also adds a global balance invariant" with a detailed force-feed-DoS rationale (§3.1). Naming deviation (`_payoutTransfer` external-with-underscore) is justified vs the conventional-naming alternative. Sufficient.

## Cross-repo consistency

Confirmed the three-repo contract is coherent and acyclic:
- Signatures `_softPay(address,uint256)`, `_payoutTransfer(address,uint256)`, `pendingPayoutTotal()`, and `ErrorUnauthorizedSelfCall` are identical in infra source/design and in both downstream deltas (Core consumes `_softPay`+`pendingPayoutTotal`; ScratchCard consumes `_softPay` and deletes local error/`_transferOnly`).
- Asymmetry is intentional and documented on both sides: Core adds `pendingPayoutTotal()` to `_checkInvariant`; ScratchCard's delta has an explicit ADDED requirement "不引入全局余额不变量" with the matching force-feed rationale (design D8). The two downstream specs do not contradict each other or the infra source.
- Verified downstream code state: `ScratchCard/contracts/PrizePool.sol` still has the local `error ErrorUnauthorizedSelfCall;` + `_transferOnly` (lines 23, 162) that its aligned change will remove — consistent with "infra first, then downstreams cut over."

## Suggested (non-blocking)

1. Spec "_softPay" ADDED requirement says push failure "资金留存合约内" and the scenario asserts `balanceOf` unchanged. This is true only because `_payoutTransfer`'s revert rolls back the inner-frame `safeTransfer` atomically. Consider adding one clause stating explicitly that the inner-frame revert guarantees no partial transfer (i.e. GLC cannot have partially moved), to make the "funds stay in contract" guarantee self-evident from the spec rather than implied. Not required — `_transferTo`'s strict post-check already makes partial-then-success impossible.
2. The Core-facing note that `claimPayout` does not itself call `_checkInvariant` lives only in the design/Core delta, not in the infra spec. Fine for an infra change (base has no invariant), but worth a one-line cross-reference so a future reader of the infra spec alone understands `claimPayout` keeps the aggregate and balance falling in lockstep. Cosmetic.

Neither nit blocks approval; both are documentation polish.

## 代码 review (2026-06-10)
status: approved

无 correctness bug；无必须修改项。

代码与 spec/design 完全对齐，已编译并跑通全部 47 个单测（含 Section 14 软付款 6 例）。逐项核验：

- **`_payoutTransfer`**（PrizePoolBase.sol:142-145）：external + `msg.sender != address(this)` 守卫 → `ErrorUnauthorizedSelfCall`，通过后 `_transferTo(_getCoin(), to, amount)`。符合 spec ADDED「自调用隔离转账」与 design D2/D4（external 制造独立 frame、不加 onlyRole）。
- **`_softPay`**（:152-158）：`try this._payoutTransfer {} catch { _recordPendingPayout }`，永不 revert。catch 仅命中纯 storage 写 + event，无传播路径。符合 spec ADDED「`_softPay` 软付款兜底」。
- **聚合 `_pendingPayoutTotal`**（:46）：private，无 setter。写入恰好落在与 per-user mapping 配对的两处——`_recordPendingPayout` 同步 `+= amount`（:132-133）、`claimPayout` 同步 `-= amount`（:165-166，amount 取自刚读出的 per-user 余额，置零后再减、最后转账，CEI 保持）。grep 全仓确认无第三处写路径，故 `_pendingPayoutTotal == Σ pendingPayoutOf(user)` 由构造恒成立。符合 spec ADDED「兜底欠款聚合」与 design D5。
- **NatSpec 准确**：`_payoutTransfer`/`_softPay` 的 frame 隔离、「MUST NOT 改 internal」、CEI 契约、amount==0 视为成功不记兜底等说明均与实现一致。
- **向后兼容**：`_recordPendingPayout`/`claimPayout`/`pendingPayoutOf` 签名与事件（PayoutPending/PayoutClaimed）未变，仅内部增量维护聚合，确为非 BREAKING。`ErrorUnauthorizedSelfCall` 进 IPrizePoolBase 纯增量。

测试断言到位：14.1 守卫 revert、14.2 push 成功（含聚合不变）、14.3 catch 兜底（含聚合自增 + emit）、14.4 amount==0、14.5 多用户 Σ 配平、14.6 claim 后聚合自减配平——catch 分支、守卫、聚合三条关键路径均被实际驱动。

观察（非阻塞、不要求修改）：
- 14.3 经「余额不足」触发 catch，是最简触发器，但未驱动 frame 隔离的核心承诺（调用方在 `_softPay` 之前写入的账本扣减能在内层 revert 后存活）。此属性需有业务账本的调用方才能验证，infra harness 无账本，故由下游 `prizepool-softpay-contract` / `prizepool-softpay-core` 对齐 change 覆盖即可，本仓不补。
- 无简化/复用机会遗漏：`_softPay`/`_payoutTransfer` 已最大化复用既有 `_transferTo`/`_recordPendingPayout`/`_getCoin`，无重复逻辑。
