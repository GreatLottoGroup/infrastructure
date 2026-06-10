# 软付款（_softPay）下沉到 PrizePoolBase — 跨仓方案

> **Status — 草案（待 `/flow-review-spec`）**。本方案为跨仓改动：在 `@greatlotto/infrastructure` 的 `PrizePoolBase` 中新增「frame 隔离软付款」能力，ScratchCard 与 GreatLottoCore 两个下游奖池合约同时复用。属 **infrastructure 对外接口打穿**，须走工作区跨仓流程（propose → `/flow-review-spec` → 实现 → 代码 review → `/security-review` → archive）。

> **目标**：把 ScratchCard `PrizePool.sol` 里那段「经 `this.` 自调用制造独立 message-call frame、try/catch 兜底、永不 revert」的软付款封装上移到 `PrizePoolBase`，使其成为奖池基类的标准能力；同时让 GreatLottoCore 的开奖回调付奖（`fulfillDraw`）复用同一能力，消除「push 付款失败会 brick entropy 回调」的隐患。

**Tech Stack:** Solidity ^0.8.24 · `@greatlotto/infrastructure` · Hardhat · OpenZeppelin v5 · Pyth Entropy V2

**Working directories:**
- 主体改动：`/Users/tongren/Documents/github/GreatLottoGroup/infrastructure`
- 下游适配 1：`/Users/tongren/Documents/github/GreatLottoGroup/ScratchCard`
- 下游适配 2：`/Users/tongren/Documents/github/GreatLottoGroup/GreatLottoCore`

**Prerequisites:**
- 工作区已用 pnpm 软链 `@greatlotto/infrastructure`（无需发版即可被两个下游消费）
- 三仓 Solidity / OZ / Hardhat 版本一致
- 前序 `add-prize-pool-base` / `migrate-to-prize-pool-base` 已落地（两个下游均已 `is PrizePoolBase`）

---

## 1. 背景与动机

### 1.1 ScratchCard 现状（已有完整实现）

`ScratchCard/contracts/PrizePool.sol` 在回调付奖路径上自己实现了一套软付款：

```solidity
error ErrorUnauthorizedSelfCall();          // 本地定义

function payBonus(uint256 tokenId, address to, uint256 amount)
    external onlyRole(PARTNER_CONTRACT_ROLE)
{
    _debitPrizePool(tokenId, amount);       // CEI：先扣单卡奖池
    try this._transferOnly(to, amount) {    // 经独立 frame 转账
        // 已付
    } catch {
        _recordPendingPayout(to, amount);   // 失败转 pull 兜底
    }
}

function _transferOnly(address to, uint256 amount) external {
    if (msg.sender != address(this)) revert ErrorUnauthorizedSelfCall();
    _transferTo(_getCoin(), to, amount);
}
```

要点：`payBonus` 在 entropy 回调内被调用，付奖失败若直接 revert 会让整批 sequence 被标 `CALLBACK_FAILED`。`this._transferOnly(...)` 走**独立 message-call frame**——其 revert 只回滚该 frame 的转账，不回滚外层已写的 `_prizePool` 扣减。`catch` 分支把欠款转入 `_recordPendingPayout`（基类已有），保证「池扣一次 + pending 记一次」无重复计账，且回调永不因付奖失败而 revert。`payBonusStrict`（stopCard 路径）则直接 `_transferTo`，失败即整笔回滚、不兜底。

### 1.2 PrizePoolBase 现状（原料齐全，缺封装）

`PrizePoolBase` 已具备软付款所需的全部原料：

| 原料 | 可见性 | 作用 |
|---|---|---|
| `_transferTo(coin, to, amount)` | internal | 严格不变量转账（amount==0 早退、余额检查、`!=` 后置校验） |
| `_getCoin()` | internal view | 取 GLC `ICoinBase` 引用 |
| `_recordPendingPayout(user, amount)` | internal | push 失败转 pull 记账，emit `PayoutPending` |
| `claimPayout()` / `pendingPayoutOf(user)` | external | 用户提取兜底欠款 / 查询 |
| `_pendingPayouts[user]` | private mapping | 兜底账本 |

唯独缺的，就是 §1.1 那层「frame 隔离 + try/catch」的软付款封装。它**不依赖任何下游业务字段**，是纯粹的基础设施。

### 1.3 GreatLottoCore 现状（有「余额不足」兜底，缺「push 失败」兜底）

`GreatLottoCore/contracts/PrizePool.sol` 的 `fulfillDraw` 同样在 entropy 回调（`GreatLotto._onRequestFulfilled`）内被调用，内部对中奖者执行 **push 转账**：

```solidity
// _fulfillNormalAward
if (paid > 0) _transferTo(_getCoin(), param.winner, paid);   // ← 回调内 push

// _fulfillTopBonus
if (topBonusAmount > 0) _transferTo(coin, param.winner, topBonusAmount); // ← 回调内 push
```

Core 现有的「兜底」只覆盖**奖池余额不足**（shortfall → `_debt` 债务账本，用户后续 `claimDebt`）。但它**没有**覆盖**push 失败**（中奖者是会 revert 的合约 / 被代币列入黑名单 / receive 抛错）——一旦 `_transferTo(winner)` revert，整个 entropy 回调 revert → `CALLBACK_FAILED`，与 ScratchCard 改造前同病。这正是任务 #2 要解决的：让 Core 的开奖付奖复用 base 的软付款能力。

> **两类失败彼此正交，不可混淆：**
> - **余额不足**（池里没钱）→ Core 既有 `_debt` 债务账本（钱不在合约里，是未来义务，**不计入余额不变量**）。**保持不变。**
> - **push 失败**（钱在合约里，但收款方拒收）→ 本方案的 `_softPay`（钱**留在**合约里，转 `_pendingPayouts` 账本）。**本次新增。**

---

## 2. 设计：PrizePoolBase 新增软付款能力

### 2.1 新增的 internal/external API

```solidity
// IPrizePoolBase.sol —— 错误上移到接口（与既有 ErrorNoPendingPayout 并列）
error ErrorUnauthorizedSelfCall();

// PrizePoolBase.sol
/// @dev 仅供 `_softPay` 经 `this._payoutTransfer(...)` 自调用，制造独立 message-call frame，
///      隔离 catch 的回滚边界。MUST NOT 被外部 / 内部直调；不得改为 internal，否则 frame
///      隔离失效、外层账本扣减会随 catch 一并回滚，重复计账修正不成立。
function _payoutTransfer(address to, uint256 amount) external {
    if (msg.sender != address(this)) revert ErrorUnauthorizedSelfCall();
    _transferTo(_getCoin(), to, amount);
}

/// @notice 软付款：push 转账失败转 pendingPayout 兜底，永不 revert（回调安全）。
/// @dev    调用方应在调用本 helper **之前**完成自己的账本扣减（CEI），使「扣一次 + 兜底记一次」
///         在 push 失败时仍配平。amount==0 时 `_transferTo` 早退、视为成功、不记兜底。
function _softPay(address to, uint256 amount) internal {
    try this._payoutTransfer(to, amount) {} catch {
        _recordPendingPayout(to, amount);
    }
}
```

**命名说明**：`_payoutTransfer` 是 `external` 却带下划线前缀，刻意偏离「下划线=内部」惯例——因为它在语义上「仅供内部经 `this.` 自调用」，下划线标记其「禁止当作公共 API 直调」的内部用途。沿用 ScratchCard `_transferOnly` 既有先例。

### 2.2 配套：暴露兜底欠款聚合（为 Core 不变量服务）

GreatLottoCore 的余额不变量 `normalPool + rollingPool == coin.balanceOf(this)` 在引入软付款后会被打破（详见 §4），需要把「滞留在合约里的兜底欠款总额」纳入等式。`_pendingPayouts` 当前只有 per-user mapping、无聚合值，故 base 增设：

```solidity
// PrizePoolBase.sol
uint256 private _pendingPayoutTotal;   // 兜底欠款聚合（滞留在合约内、尚未被 claim 的总额）

function _recordPendingPayout(address user, uint256 amount) internal {
    _pendingPayouts[user] += amount;
    _pendingPayoutTotal += amount;          // ← 新增
    emit PayoutPending(user, GreatLottoCoinAddress, amount);
}

function claimPayout() external noDelegateCall {
    uint256 amount = _pendingPayouts[msg.sender];
    if (amount == 0) revert ErrorNoPendingPayout();
    _pendingPayouts[msg.sender] = 0;
    _pendingPayoutTotal -= amount;          // ← 新增
    _transferTo(_getCoin(), msg.sender, amount);
    emit PayoutClaimed(msg.sender, GreatLottoCoinAddress, amount);
}

/// @notice 当前滞留在合约内、尚未被 claim 的兜底欠款总额（供下游不变量校验复用）。
function pendingPayoutTotal() public view returns (uint256) {
    return _pendingPayoutTotal;
}
```

> 该聚合对 ScratchCard 是**无害的纯增量**（ScratchCard 无余额不变量，不读它）；对 Core 是不变量配平的必要项。`claimPayout` 自身配平（P 与 B 同减），无需下游介入。

---

## 3. 下游适配 1 — ScratchCard

纯收敛，无行为变化：

1. 删除本地 `_transferOnly(...)` 函数。
2. 删除本地 `error ErrorUnauthorizedSelfCall;`（改由 `IPrizePoolBase` 提供）。
3. `payBonus` 收缩为：

```solidity
function payBonus(uint256 tokenId, address to, uint256 amount)
    external onlyRole(PARTNER_CONTRACT_ROLE)
{
    _debitPrizePool(tokenId, amount);
    _softPay(to, amount);
}
```

4. `payBonusStrict` **保持本地不动**（它直接 `_transferTo`，stopCard 失败应整笔回滚，无需软封装）。
5. 既有 `PrizePool.test.js` 的付奖双路径用例语义不变，应继续通过（行为等价回归）。

合约体积：ScratchCard `PrizePool` 略微缩小。

### 3.1 评估：ScratchCard 是否也加 Core 那种全局余额不变量？（结论：**不加**）

ScratchCard 引入 `_softPay` 后，是否也该像 Core 那样补一条 `sum(_prizePool) + pendingPayoutTotal == balanceOf` 的全局不变量？**评估结论：不加**，且不对称是刻意的——

1. **会把不存在的 force-feed DoS 引入最敏感的回调路径。** GLC 是 ERC20，任何人可直接 `transfer` 到 PrizePool 使 `balanceOf > 账本和`；Core 式严格相等遇 force-feed 即 revert。而 ScratchCard `payBonus` 在 entropy 回调内、且**刻意不包 try/catch**（设计契约是「`payBonus` 永不 revert」，见 `ScratchCard.sol` `_onRequestFulfilled`）。一旦不变量在回调内 revert → `payBonus` revert → `CALLBACK_FAILED` → 该卡开奖**永久 brick**（retry 每次都失败）。等于拿最关键路径换一个当前并不存在的攻击面。
2. **账本模型让收益极低。** ScratchCard 是 **per-card 独立账本**，`_debitPrizePool` 的单卡 `balance < amount` 检查本身就是比全局等式**更强的局部约束**；卡间资金不流动，没有 Core 的双账本滚动 / `_debt` / ERC4626 存赎这类「多账本搬运」，全局不变量额外能抓的 bug 面极小。
3. **成本不匹配。** ScratchCard 无现成聚合，需新增 `_totalPrizePool` 并在 `collectForIssue` / `payBonus` / `payBonusStrict` 多处维护，增状态与出错面，换 1/2 两点的低收益高风险。

**若确需健全性保障的折中**：`balanceOf >= sum(_prizePool) + pendingPayoutTotal` 的 **`>=` 软断言 + 只读对账 view**（仅链下监控调用、绝不入写路径），但仍需新增聚合，收益有限。默认推荐**依赖既有 per-card 检查、不加任何全局不变量**。

> **旁注（Core 已在 `prizepool-softpay-core` change 内一并修复）**：Core 既有 `_checkInvariant` 用严格相等，注释仅排除 raw ETH，未排除 **ERC20 直转**——GLC force-feed（任意地址直接 transfer 1 wei）能让 `sum < balanceOf` 而永久 brick `collect` / `fulfillDraw` / `investmentRedeem` / `payDebt`，是 Core 既有 DoS。由于 softpay 改动本就在改 `_checkInvariant` 同一行，已将其由严格 `==` 放宽为**偿付能力 `<=`**（`_normalPool + _rollingPool + pendingPayoutTotal() <= balanceOf`，仅 `>` 时 revert）：保留对资不抵债的关键保护，对 force-feed / dust 盈余免疫。详见 `GreatLottoCore/openspec/changes/prizepool-softpay-core`。

---

## 4. 下游适配 2 — GreatLottoCore（核心难点：余额不变量）

### 4.1 把回调内的两处 winner push 改为软付款

```solidity
// _fulfillNormalAward
if (paid > 0) _softPay(param.winner, paid);          // 原 _transferTo(_getCoin(), winner, paid)

// _fulfillTopBonus
if (topBonusAmount > 0) _softPay(coin? , ...);       // 原 _transferTo(coin, winner, topBonusAmount)
//                       → 改为 _softPay(param.winner, topBonusAmount)
```

> 仅这两处（都在 `fulfillDraw` → entropy 回调路径内）改软付款。**`payDebt` / `investmentRedeem` / `_collect` 的各路转账保持严格 `_transferTo`**——它们都在用户自己的交易里、收款方多为 `msg.sender`，失败即 revert 是正确语义（类比 ScratchCard `payBonusStrict` 与 base `claimPayout` 的 pull 模型）。

### 4.2 不变量必须纳入兜底欠款（**关键决策 D5，见 §5**）

软付款失败时钱**留在合约里**，但 `_normalPool` / `_rollingPool` 已在 `_drawFromPools` 中先扣减 → 旧不变量 `normalPool + rollingPool == balanceOf` 的左边会比右边少 `paid`。必须改为：

```solidity
function _checkInvariant() private view {
    ICoinBase coin = _getCoin();
    uint256 sum = _normalPoolView() + _rollingPoolView() + pendingPayoutTotal(); // ← 加聚合
    if (sum != coin.balanceOf(address(this))) revert PrizePoolInvariantViolated();
}
```

配平推演（push 失败时）：池子 −`paid`、`pendingPayoutTotal` +`paid`、`balanceOf` 不变 → 等式两边同步，不变量守恒。后续中奖者 `claimPayout()`：`pendingPayoutTotal` −`paid`、`balanceOf` −`paid` → 仍守恒（`claimPayout` 不触发 `_checkInvariant`，但逻辑上恒等，无需校验）。

> **债务 vs 兜底——为何一个不进不变量、一个进**：`_debt` 是「池里本就没钱」的未来义务，合约余额里**没有**对应资金，故不进等式；`_pendingPayouts` 是「钱已在合约里、只是没推出去」，资金**滞留在余额内**，故必须进等式。二者可叠加发生（同一次开奖：`paid` 部分 push 失败 → 兜底；`shortfall` 部分 → 债务），中奖者分别经 `claimPayout()` 与 `claimDebt()` 两条路径回收。

### 4.3 Core 测试需新增

- 回调内 winner 为「拒收合约」→ 付奖转 `pendingPayout`、回调不 revert、不变量含兜底项仍成立。
- 中奖者随后 `claimPayout()` 成功提取、不变量回到无兜底态。
- 「同一次开奖 push 失败 + 余额不足」叠加：`pendingPayout` 与 `_debt` 并存且各自可独立回收。

---

## 5. 决策表

| # | 决策点 | 决策 | 理由 |
|---|---|---|---|
| D1 | 软付款封装放在哪 | **下沉到 `PrizePoolBase`** | 不依赖任何下游业务字段，纯基础设施；两个下游同构复用，消除重复与漂移 |
| D2 | `_payoutTransfer` 可见性 | **`external` + 自调用守卫**，**不得改 internal** | 必须制造独立 message-call frame 才能隔离 catch 回滚边界；internal 调用共用同一 frame，frame 隔离失效 |
| D3 | `ErrorUnauthorizedSelfCall` 放哪 | **上移到 `IPrizePoolBase`**，下游删本地副本 | 与既有 `ErrorNoPendingPayout` 并列；防接口漂移 |
| D4 | `_payoutTransfer` 是否加 `onlyRole` | **不加**，仅 `msg.sender == address(this)` 守卫 | 唯一调用者是 `this`（经 `_softPay`），而 `_softPay` 由各自的 role-gated 函数内部触发；外部直调一律 revert |
| D5 | Core 余额不变量如何处理软付款滞留资金 | **base 暴露 `pendingPayoutTotal()`；Core `_checkInvariant` 改为 `normal+rolling+pendingPayoutTotal == balanceOf`** | 软付款失败资金留存合约内，必须纳入等式才守恒；聚合值由 base 维护，下游只读复用（备选方案见 §7） |
| D6 | Core 哪些转账改软付款 | **仅 `fulfillDraw` 路径内两处 winner push**；`payDebt`/`investmentRedeem`/`_collect` 保持严格 | 只有回调内 push 失败会 brick 回调；用户自交易里的转账失败即回滚是正确语义 |
| D7 | ScratchCard `payBonusStrict` 是否也走软付款 | **不动，保持严格** | stopCard 由创建者直调，失败应整笔回滚让其重试，不应兜底 |
| D8 | ScratchCard 是否也加 Core 式全局余额不变量 | **不加**（不对称是刻意的） | per-card `_debitPrizePool` 已是更强局部约束；全局严格等式会引入 GLC force-feed DoS，且 `payBonus` 在回调内刻意无 try/catch → revert 即永久 brick 开奖。详见 §3.1 |

---

## 6. 故意不上移 / 不改动的

- ScratchCard 的 `_prizePool[tokenId]` 单卡账本、`collectForIssue/Buy`、`_debitPrizePool`、`payBonusStrict` → 业务专属，留本地。
- GreatLottoCore 的 `_normalPool` / `_rollingPool` / `_debt` / `_totalDebt` / `_drawFromPools` / `fulfillDraw` / `payDebt` / 投资存赎 → 业务专属，留本地（仅 `_checkInvariant` 公式与两处 push 改动）。
- `_recordPendingPayout` / `claimPayout` / `pendingPayoutOf` 的既有签名与事件 → 不变（仅内部增量维护聚合）。

---

## 7. 风险与备选

- **重入**：`_payoutTransfer` 经 SafeERC20 向受信白名单 GLC（稳定币代理）转账，风险面与现状一致；`claimPayout` 仍 `noDelegateCall`。建议安全 review 复核 `_softPay` 在回调内的重入路径（中奖者合约在 receive 中回调本合约的可能性）。
- **D5 备选方案（劣）**：① Core 不改不变量、改为「软付款失败时把资金视作退回池子」——但 push 已扣池，需反向补回池子并放弃 pendingPayout 语义，破坏「钱已属于中奖者」的事实，且与 base `claimPayout` 冲突。② Core 自维护一份 pending 总额——与 base 重复记账、易漂移。故选 base 暴露聚合。
- **回滚**：base 新增 API 为纯增量，下游未切换前不受影响；可分阶段落地（先 base + harness 测试，再 ScratchCard 收敛，最后 Core 适配）。

---

## 8. 落地阶段

1. **infrastructure**：`PrizePoolBase` 新增 `_payoutTransfer` / `_softPay` / `_pendingPayoutTotal` / `pendingPayoutTotal()`；`IPrizePoolBase` 增 `ErrorUnauthorizedSelfCall`；`PrizePoolBaseHarness` + 单测覆盖软付款成功 / 失败 / 自调用守卫 / 聚合增减。
2. **ScratchCard**：删 `_transferOnly` 与本地 error，`payBonus` 收敛为 `_debitPrizePool + _softPay`；回归 `PrizePool.test.js`。
3. **GreatLottoCore**：两处 winner push 改 `_softPay`，`_checkInvariant` 纳入 `pendingPayoutTotal()`；新增 §4.3 用例。
4. 每仓 `npx hardhat compile`（核对合约体积）+ 全量测试 + `/security-review`（合约仓必跑）。

> 跨仓 change-id 建议：`2026Q2-prizepoolbase-softpay`（infrastructure 主提案 + 两个下游适配 change，经协调文档串联）。
