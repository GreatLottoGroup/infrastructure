# Phase 2 Implementation Plan — ScratchCard 适配 `EntropyConsumerBase`

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 `ScratchCard.sol` 改为继承 `EntropyConsumerBase`，删除内联的 entropy storage / setter / `retryDraw` 等冗余实现，把业务结算逻辑收敛到 `_onRequestFulfilled` 钩子；现有功能 / 测试套件全部回归。

**Architecture:** 主合约继承链由 `is PrizePool, NoDelegateCall, DeadLine, IEntropyConsumer, IScratchCard` 改为 `is PrizePool, NoDelegateCall, EntropyConsumerBase, IScratchCard`（`EntropyConsumerBase` 自带 `IEntropyConsumer + AccessControl + DeadLine`）。原 `_pending` / `PendingDraw` / `entropyAddressImmutable` / `entropyProvider` / `callbackGasLimit` / `entropyTimeout` / 三个 setter / 两个 setter 事件 / `retryDraw` 全部删除，改用基类提供的等价物。`_requestDraw` 改为调 `_requestRandomness`；`entropyCallback` 内联逻辑搬到 `_onRequestFulfilled` 实现。

**Tech Stack:** Solidity 0.8.35 / Cancun / viaIR · `@greatlotto/infrastructure`（新版本，含 Phase 1 基类）· Hardhat 2.28.6

**Working directory:** `/Users/tongren/Documents/github/GreatLottoGroup/ScratchCard`

**Prerequisites:**
- Phase 1 PR 已 merge 到 infrastructure main
- `@greatlotto/infrastructure` 新版本已 release（npm 或 git tag）
- ScratchCard 仓库的 `package.json` 已可解析新版 infra dep

---

## File Structure

| 路径 | 操作 | 说明 |
|---|---|---|
| `package.json` | 修改 | bump `@greatlotto/infrastructure` 到 Phase 1 release 版本 |
| `contracts/ScratchCard.sol` | 重写 entropy 相关段 | 继承基类、删冗余、改造 `_requestDraw` / `entropyCallback` / `retryDraw` |
| `contracts/base/PrizePool.sol` 及链上其他文件 | 不动 | |
| `test/runTest/ScratchCard.test.js` | 修改 | 适配事件 / 函数签名变化 |
| `test/runTest/M2Features.test.js` | 修改 | 同上 |
| `test/utils/deployFixture.js` | 检查 / 微调 | 部署参数顺序未变 |

---

## Task 1: Bump infrastructure 依赖 + 编译基线

**Files:**
- Modify: `package.json`

- [ ] **Step 1: 升级 dep**

```bash
cd /Users/tongren/Documents/github/GreatLottoGroup/ScratchCard
npm install --save '@greatlotto/infrastructure@<phase1-version>'
# <phase1-version> 替换为 Phase 1 PR 合并后发布的版本号或 git+ssh 引用
```

- [ ] **Step 2: 验证 infra 新基类可被解析**

```bash
ls node_modules/@greatlotto/infrastructure/contracts/base/EntropyConsumerBase.sol
ls node_modules/@greatlotto/infrastructure/contracts/interfaces/IEntropyConsumerBase.sol
```

Expected：两个文件都存在。

- [ ] **Step 3: 编译当前 ScratchCard（应仍能 compile，因为还没改源码）**

```bash
npx hardhat compile
```

Expected：编译通过，无新警告。

- [ ] **Step 4: Commit**

```bash
git add package.json package-lock.json
git commit -m "chore(deps): bump @greatlotto/infrastructure for EntropyConsumerBase"
```

---

## Task 2: 切换继承链 + 删除冗余 storage / 事件 / 错误

**Files:**
- Modify: `contracts/ScratchCard.sol`

- [ ] **Step 1: 替换 imports（[ScratchCard.sol:10-13](../../ScratchCard/contracts/ScratchCard.sol#L10-L13) 区段）**

把以下 import 删除：

```solidity
import "@pythnetwork/entropy-sdk-solidity/IEntropyV2.sol";
import "@pythnetwork/entropy-sdk-solidity/IEntropyConsumer.sol";
import "@pythnetwork/entropy-sdk-solidity/EntropyStructsV2.sol";
import "@pythnetwork/entropy-sdk-solidity/EntropyStatusConstants.sol";
```

替换为：

```solidity
import "@greatlotto/infrastructure/contracts/base/EntropyConsumerBase.sol";
```

注意：`@greatlotto/infrastructure/contracts/base/DeadLine.sol` 的 import 也可以删除——`EntropyConsumerBase` 已 transitively 提供 `DeadLine`。

- [ ] **Step 2: 改继承声明（[ScratchCard.sol:24](../../ScratchCard/contracts/ScratchCard.sol#L24)）**

把：

```solidity
contract ScratchCard is PrizePool, NoDelegateCall, DeadLine, IEntropyConsumer, IScratchCard {
```

改为：

```solidity
contract ScratchCard is PrizePool, NoDelegateCall, EntropyConsumerBase, IScratchCard {
```

- [ ] **Step 3: 删除冗余 storage（[ScratchCard.sol:29-52](../../ScratchCard/contracts/ScratchCard.sol#L29-L52) 区段）**

删除整个 `// ============ Pyth Entropy ============` 段中的：

```solidity
IEntropyV2 public immutable entropy;
address private immutable entropyAddressImmutable;
address public entropyProvider;
uint32 public callbackGasLimit = 500_000;
uint64 public entropyTimeout = 1 hours;
uint64 internal constant ENTROPY_TIMEOUT_MIN = 60;
uint64 internal constant ENTROPY_TIMEOUT_MAX = 24 hours;

struct PendingDraw { ... }
mapping(uint64 sequenceNumber => PendingDraw) private _pending;
```

**保留**：

```solidity
uint32 public constant MAX_DRAW_QUANTITY = 10;
uint256 public constant MAX_OVERVIEW_BATCH = 32;

mapping(uint256 cardTokenId => uint256[] awardRemaining) private _awardRemaining;
mapping(uint256 cardTokenId => uint256 remainingCards) private _remainingCards;
mapping(uint256 cardTokenId => uint256 pendingCount) private _pendingCount;
mapping(address user => uint256) private _pendingPayouts;
```

- [ ] **Step 4: 删除冗余事件（[ScratchCard.sol:67-77](../../ScratchCard/contracts/ScratchCard.sol#L67-L77)）**

删除：

```solidity
event ScratchCardDrawRetried(...);            // 用基类 RequestRetried 替代
event EntropyProviderChanged(address indexed newProvider);
event CallbackGasLimitChanged(uint32 newLimit);
event EntropyTimeoutChanged(uint64 newTimeout);
```

**保留**：`ScratchCardDrawRequested` / `PayoutPending` / `PayoutClaimed`。

- [ ] **Step 5: 删除冗余错误（[ScratchCard.sol:83-91](../../ScratchCard/contracts/ScratchCard.sol#L83-L91)）**

删除（已在基类 `IEntropyConsumerBase` 定义）：

```solidity
error ErrorZeroUserRandomNumber();         // 用 ErrorInvalidUserRandom
error ErrorInsufficientFee(...);            // 用 ErrorInsufficientEntropyFee
error ErrorUnknownSequence(...);            // 用 ErrorRequestNotFound
error ErrorNotPendingOwner(...);            // 用 ErrorNotRequester
error ErrorRetryNotAllowed(...);            // 用 ErrorRetryNotAllowed
error ErrorTimeoutOutOfRange(...);          // 用 ErrorInvalidEntropyTimeout
```

**保留**：`ErrorInvalidQuantity` / `ErrorCardHasPendingDraws` / `ErrorNoPendingPayout`（业务错误）。

- [ ] **Step 6: 改 constructor（[ScratchCard.sol:95-119](../../ScratchCard/contracts/ScratchCard.sol#L95-L119)）**

新写法：

```solidity
constructor(
    address scratchCardNFTAddress_,
    address greatLottoCoinAddress_,
    address daoCoinAddress_,
    address daoBenefitPoolAddress_,
    address salesChannelAddress_,
    address entropyAddress_,
    address entropyProvider_,
    address owner_
)
    AccessControlPartnerContract(owner_)
    EntropyConsumerBase(entropyAddress_, entropyProvider_)
{
    if (scratchCardNFTAddress_ == address(0)) revert ErrorZeroAddress();
    ScratchCardNFTAddress = scratchCardNFTAddress_;
    GreatLottoCoinAddress = greatLottoCoinAddress_;
    DaoCoinAddress = daoCoinAddress_;
    DaoBenefitPoolAddress = daoBenefitPoolAddress_;
    SalesChannelAddress = salesChannelAddress_;
}
```

zero-address 检查中 `entropyAddress_` / `entropyProvider_` 已由基类 constructor 处理，移除重复检查。

- [ ] **Step 7: 删除 `getEntropy` override（[ScratchCard.sol:123-125](../../ScratchCard/contracts/ScratchCard.sol#L123-L125)）**

整段删掉，基类已实现。

- [ ] **Step 8: 删除 `_entropyFee` 私有函数（[ScratchCard.sol:255-257](../../ScratchCard/contracts/ScratchCard.sol#L255-L257)）**

整段删掉，基类提供 `entropyFee()` public。原 `_requestDraw` 内对它的调用 Task 3 一并修改。

- [ ] **Step 9: 删除三个 setter（[ScratchCard.sol:443-460](../../ScratchCard/contracts/ScratchCard.sol#L443-L460)）**

整段 `// ============ Governance ============` 下的三个 `setEntropyProvider / setCallbackGasLimit / setEntropyTimeout` 删除。基类已提供。

- [ ] **Step 10: 编译，确认前后不一致都被发现**

```bash
npx hardhat compile
```

Expected：会报多处错误（`_pending` 未定义、`_entropyFee` 未定义、`entropyTimeout` 未定义等）——这些错都将在 Task 3 / 4 / 5 修复。

- [ ] **Step 11: Commit（"break the build" 中间提交）**

```bash
git add contracts/ScratchCard.sol
git commit -m "refactor(scratchcard): switch to EntropyConsumerBase inheritance, drop duplicates (compile-broken)"
```

---

## Task 3: 改造 `_requestDraw` 调用基类

**Files:**
- Modify: `contracts/ScratchCard.sol`

- [ ] **Step 1: 重写 `_requestDraw` + override `_postRequest`（[ScratchCard.sol:259-313](../../ScratchCard/contracts/ScratchCard.sol#L259-L313)）**

`_pendingCount += 1` 是 base 调用之后的 storage 写入；base 末尾会通过 `_refundFee` 让出控制权。为保持 CEI，把 `_pendingCount += 1` 与业务 emit 都移到基类 `_postRequest` 钩子内（基类调度位置：`emit RequestSubmitted` 之后、`_refundFee` 之前）。

```solidity
function _requestDraw(
    address owner,
    uint256 tokenId,
    uint256 quantity,
    bytes32 userRandomNumber,
    bool burnExistingCards,
    uint256 feeBudget
) private returns (uint64 sequenceNumber) {
    if (quantity == 0 || quantity > MAX_DRAW_QUANTITY) {
        revert ErrorInvalidQuantity(quantity);
    }
    // userRandomNumber == 0 由基类 _requestRandomness 校验

    IScratchCardNFT scratchCardNFT = IScratchCardNFT(ScratchCardNFTAddress);

    if (!burnExistingCards) {
        IScratchCardNFT.Card memory card = scratchCardNFT.getCard(tokenId);
        if (card.isPaused) revert IScratchCardNFT.ErrorCardPaused(tokenId);
        if (card.isStopped) revert IScratchCardNFT.ErrorCardStopped(tokenId);
    }

    if (burnExistingCards) {
        scratchCardNFT.burnCardForDraw(owner, tokenId, quantity);
    }

    // 槽位预扣
    uint256 remaining = _remainingCards[tokenId];
    if (remaining < quantity) {
        revert ErrorInvalidQuantity(quantity);
    }
    _remainingCards[tokenId] = remaining - quantity;

    (sequenceNumber, ) = _requestRandomness(
        tokenId,
        owner,
        uint32(quantity),
        userRandomNumber,
        feeBudget
    );
    // _pendingCount += 1 与 ScratchCardDrawRequested emit 都在 _postRequest 钩子内完成（CEI）
}

function _postRequest(uint64 sequenceNumber, Request memory req) internal override {
    _pendingCount[req.tokenId] += 1;
    emit ScratchCardDrawRequested(req.tokenId, req.requester, sequenceNumber, req.itemCount);
}
```

要点：
- `userRandom == 0` 校验删除（基类做）
- `_entropyFee()` / `entropy.requestV2{value: fee}(...)` / `_pending[seq] = ...` 全部删除（基类做）
- `_pendingCount += 1` 与 `ScratchCardDrawRequested` emit 移到 `_postRequest`，保持 CEI
- 业务保留：`MAX_DRAW_QUANTITY` 检查、burn / pause check / 槽位预扣

- [ ] **Step 2: 编译**

```bash
npx hardhat compile
```

Expected：剩下的报错应只与 `entropyCallback` / `retryDraw` 有关。

- [ ] **Step 3: Commit**

```bash
git add contracts/ScratchCard.sol
git commit -m "refactor(scratchcard): _requestDraw delegates to base _requestRandomness"
```

---

## Task 4: 把 `entropyCallback` 改造为 `_onRequestFulfilled`

**Files:**
- Modify: `contracts/ScratchCard.sol`

- [ ] **Step 1: 删除原 `entropyCallback`（[ScratchCard.sol:317-355](../../ScratchCard/contracts/ScratchCard.sol#L317-L355)）**

整段 `function entropyCallback(...) internal override` 删掉。基类是 final，不可再 override。

- [ ] **Step 2: 新增 `_onRequestFulfilled`**

在原 `entropyCallback` 位置插入：

```solidity
function _onRequestFulfilled(
    uint64 /*sequenceNumber*/,
    Request memory req,
    bytes32 randomNumber
) internal override {
    if (_pendingCount[req.tokenId] > 0) {
        _pendingCount[req.tokenId] -= 1;
    }

    IScratchCardNFT scratchCardNFT = IScratchCardNFT(ScratchCardNFTAddress);
    IScratchCardNFT.Card memory card = scratchCardNFT.getCard(req.tokenId);

    uint256 totalBonus;
    uint32 quantity = req.itemCount;
    for (uint256 i = 0; i < quantity; i++) {
        uint256 r = uint256(keccak256(abi.encode(randomNumber, i)));
        uint256 batchRemaining = uint256(quantity) - i;
        uint256 bonus = _drawOne(req.tokenId, card.awards, r, batchRemaining);
        totalBonus += bonus;
        scratchCardNFT.mintTicket(req.requester, bonus, req.tokenId);
    }

    if (totalBonus > 0) {
        try this._payBonusExternal(req.tokenId, req.requester, totalBonus) {
            // success
        } catch {
            _recordPendingPayout(req.requester, totalBonus);
        }
    }

    emit ScratchCardDrawn(req.tokenId, req.requester, quantity, totalBonus);
}
```

要点：
- 不再读 `_pending[seq]`（基类已提供 `req`）
- 不再 `delete _pending[seq]`（基类已做）
- `req.requester` 替换原 `p.owner`，`req.itemCount` 替换原 `p.quantity`，`req.tokenId` 替换原 `p.tokenId`
- 其余业务逻辑（`for loop` / `_drawOne` / `mintTicket` / try-catch payout / 业务 `ScratchCardDrawn`）原样搬移

- [ ] **Step 3: 编译**

```bash
npx hardhat compile
```

Expected：仅剩 `retryDraw` 相关报错。

- [ ] **Step 4: Commit**

```bash
git add contracts/ScratchCard.sol
git commit -m "refactor(scratchcard): replace entropyCallback with _onRequestFulfilled hook"
```

---

## Task 5: 删除 `retryDraw` 改用基类 `retryRequest`

**Files:**
- Modify: `contracts/ScratchCard.sol`

- [ ] **Step 1: 删除整个 `retryDraw` 函数（[ScratchCard.sol:374-416](../../ScratchCard/contracts/ScratchCard.sol#L374-L416)）**

整段删除（注释也删）。基类 `retryRequest(uint64, bytes32, uint256)` 直接对外暴露，前端从 `retryDraw` 改调 `retryRequest`。

- [ ] **Step 2: 决定是否需要 `_beforeRetry` override**

ScratchCard 当前 `retryDraw` 没有任何业务前置（除 `requester` 校验，已在基类做）。**不需要 override。** 留空即可。

> 如果将来要加"retry 时重新校验 isPaused"等规则，在此处覆盖：
> ```solidity
> function _beforeRetry(uint64 oldSeq, Request memory old) internal override { ... }
> ```

- [ ] **Step 3: 编译**

```bash
npx hardhat compile
```

Expected：编译通过，contract sizer 输出 ScratchCard 大小（应略小于改造前 ≈ 16.5 KiB，因为删除了重复实现）。

- [ ] **Step 4: Commit**

```bash
git add contracts/ScratchCard.sol
git commit -m "refactor(scratchcard): drop retryDraw, use base retryRequest"
```

---

## Task 6: 适配 ScratchCard.test.js

**Files:**
- Modify: `test/runTest/ScratchCard.test.js`
- Modify: `test/utils/deployFixture.js`（如有）

- [ ] **Step 1: 跑测试，列出所有失败用例**

```bash
npx hardhat test test/runTest/ScratchCard.test.js 2>&1 | tee /tmp/sc-test-fails.log
```

预期失败原因：
1. `expect(...).to.emit(scratchCard, "ScratchCardDrawRetried")` → 改成 `"RequestRetried"`，参数列也变了（`(oldSeq, newSeq, requester, oldFee, newFee)`，丢掉 `tokenId`）
2. `expect(...).to.emit(scratchCard, "EntropyProviderChanged")` 等三个治理事件参数从 `(newProvider)` 变成 `(oldProvider, newProvider)`、`CallbackGasLimitChanged(oldLimit, newLimit)`、`EntropyTimeoutChanged(oldTimeout, newTimeout)`
3. `scratchCard.retryDraw(...)` → 改成 `scratchCard.retryRequest(...)`（参数同 `(oldSeq, newRandom, deadline)`）
4. `expect(...).to.be.revertedWithCustomError(scratchCard, "ErrorZeroUserRandomNumber")` → `"ErrorInvalidUserRandom"`
5. `"ErrorInsufficientFee"` → `"ErrorInsufficientEntropyFee"`
6. `"ErrorUnknownSequence"` → `"ErrorRequestNotFound"`
7. `"ErrorNotPendingOwner"` → `"ErrorNotRequester"`
8. `"ErrorTimeoutOutOfRange"` → `"ErrorInvalidEntropyTimeout"`

- [ ] **Step 2: 全局替换函数 / 错误名**

用 sed 或 IDE 全局替换以下映射，仅在 `test/runTest/*.test.js`：

| 原 | 新 |
|---|---|
| `retryDraw` | `retryRequest` |
| `ErrorZeroUserRandomNumber` | `ErrorInvalidUserRandom` |
| `ErrorInsufficientFee` | `ErrorInsufficientEntropyFee` |
| `ErrorUnknownSequence` | `ErrorRequestNotFound` |
| `ErrorNotPendingOwner` | `ErrorNotRequester` |
| `ErrorTimeoutOutOfRange` | `ErrorInvalidEntropyTimeout` |
| `ScratchCardDrawRetried` | `RequestRetried` |

注意 `ScratchCardDrawRetried` 的参数列改变：原 `(oldSeq, newSeq, tokenId, owner, oldFee, newFee)` → 新基类事件 `(oldSeq, newSeq, requester, oldFee, newFee)`。涉及该事件断言的 `withArgs(...)` 需要逐个检查并去掉 `tokenId` / 改 `owner` 为 `requester`。

如果某些用例需要断言 tokenId，可以在 `_onRequestFulfilled` 内额外 emit 一个业务版的 retry 事件作为补充——但当前设计未提供，不要随意新增。如有用例确实强依赖 tokenId，标记 `it.skip` 并在 follow-up issue 跟踪。

- [ ] **Step 3: 修治理事件断言**

`EntropyProviderChanged(newProvider)` → `EntropyProviderChanged(oldProvider, newProvider)`。
`CallbackGasLimitChanged(newLimit)` → `CallbackGasLimitChanged(oldLimit, newLimit)`。
`EntropyTimeoutChanged(newTimeout)` → `EntropyTimeoutChanged(oldTimeout, newTimeout)`。

逐个 grep `withArgs` 并补全 oldXxx 参数。

- [ ] **Step 4: 跑测试直到 PASS**

```bash
npx hardhat test test/runTest/ScratchCard.test.js
```

Expected：26 个用例全部 PASS。

- [ ] **Step 5: M2Features.test.js 同步**

```bash
npx hardhat test test/runTest/M2Features.test.js
```

如有失败按上述映射修复。

- [ ] **Step 6: 全套测试**

```bash
npx hardhat test
```

Expected：63 个用例（13 + 26 + 24）全部 PASS。

- [ ] **Step 7: Commit**

```bash
git add test/runTest/ScratchCard.test.js test/runTest/M2Features.test.js
git commit -m "test(scratchcard): adapt to EntropyConsumerBase API"
```

---

## Task 7: Gas / Size / Coverage 终验 + PR

**Files:**
- 仅核验 + 文档更新

- [ ] **Step 1: 合约大小检查**

```bash
npx hardhat clean && npx hardhat compile
```

Expected：`ScratchCard` < 24KiB（EIP-170 上限）；与改造前相比应**变小或不变**（删了 ≈ 80 行 entropy 相关代码）。

- [ ] **Step 2: Gas reporter 对比**

```bash
REPORT_GAS=true npx hardhat test test/runTest/ScratchCard.test.js
```

记录 `draw / buyAndDraw / retryRequest / entropyCallback` 的 gas 消耗。新基类引入了 `Request.tokenId` 相比原 `PendingDraw.tokenId` 是同一个 slot，理论 gas 持平。如果出现 > 5% 回归需要排查。

- [ ] **Step 3: 覆盖率**

```bash
npx hardhat coverage --testfiles "test/runTest/ScratchCard.test.js test/runTest/M2Features.test.js"
```

Expected：`ScratchCard.sol` 覆盖率不低于改造前。

- [ ] **Step 4: 更新 CLAUDE.md 与 design 文档**

修改 `CLAUDE.md`：

- 在「合约架构」段把 `IEntropyConsumer (Pyth)` 替换为 `EntropyConsumerBase (infrastructure)`。
- 在「注意事项」段把 `retryDraw` 改为 `retryRequest`。

修改 `infrastructure/doc/entropy-consumer-base-design.md` 的「修订记录」表追加：

```markdown
| v1.2 | <实施日期> | Phase 2 实施完成；ScratchCard 切换至 EntropyConsumerBase |
```

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(scratchcard): update CLAUDE.md after EntropyConsumerBase migration"
```

- [ ] **Step 6: Push + PR**

```bash
git push -u origin <branch-name>
gh pr create --title "refactor(scratchcard): migrate to EntropyConsumerBase" --body "$(cat <<'EOF'
## Summary
- ScratchCard 主合约改为继承 `@greatlotto/infrastructure/contracts/base/EntropyConsumerBase`
- 删除冗余的 entropy storage / setter / `retryDraw` / 三个治理事件
- `entropyCallback` 内联逻辑收敛到 `_onRequestFulfilled` 钩子
- 业务事件 `ScratchCardDrawRequested` / `ScratchCardDrawn` / `PayoutPending` / `PayoutClaimed` 保留
- 63 个测试用例全部 PASS

## Breaking changes (前端必读)
- 函数：`retryDraw → retryRequest`（参数不变）
- 事件：`ScratchCardDrawRetried → RequestRetried`（参数列变化：去 tokenId、owner→requester）
- 事件：`EntropyProviderChanged / CallbackGasLimitChanged / EntropyTimeoutChanged` 都新增 oldXxx 参数
- 错误：`ErrorZeroUserRandomNumber / ErrorInsufficientFee / ErrorUnknownSequence / ErrorNotPendingOwner / ErrorTimeoutOutOfRange` 改名为基类等价物

## Test plan
- [x] 63 个 hardhat 测试用例 PASS
- [x] 合约大小 < 24KiB
- [x] Gas 无 > 5% 回归
- [x] 覆盖率不降

## Follow-up
- interface 仓前端同步（`retryDraw → retryRequest`、事件订阅）
EOF
)"
```

---

## Self-Review Checklist

- [ ] `ScratchCard.sol` 已无 `import "@pythnetwork/...sol"`
- [ ] `ScratchCard.sol` 已无 `_pending` mapping / `PendingDraw` struct
- [ ] `ScratchCard.sol` 已无 `entropyAddressImmutable` / `entropyProvider` 状态变量声明
- [ ] `ScratchCard.sol` 已无 `setEntropyProvider` / `setCallbackGasLimit` / `setEntropyTimeout` 函数
- [ ] `ScratchCard.sol` 已无 `retryDraw` / `_entropyFee` / `getEntropy` 函数
- [ ] `ScratchCard.sol` 已无 `entropyCallback` override（基类是 final）
- [ ] `_onRequestFulfilled` 函数签名匹配基类：`(uint64, Request memory, bytes32) internal override`
- [ ] 业务字段（`_remainingCards / _pendingCount / _awardRemaining / _pendingPayouts`）未被误删
- [ ] 业务事件 `ScratchCardDrawRequested / ScratchCardDrawn / PayoutPending / PayoutClaimed` 保留
- [ ] 测试套件全部 PASS（63/63）
