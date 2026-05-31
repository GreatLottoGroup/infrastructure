# Phase 3 Implementation Plan — GreatLottoCore 适配 `EntropyConsumerBase`

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `GreatLotto.sol` 改为继承 `EntropyConsumerBase`，删除现有 `contracts/base/EntropyConsumer.sol`、`_seqToTokenId` mapping、`retryBlockGap` / `retryDraw` / `changeRetryBlockGap` 等冗余实现；把开奖结算迁移到 `_onRequestFulfilled` 钩子；retry 触发由"区块差"改为"时间戳 + CALLBACK_FAILED"；`entropyGasLimit` 由每次请求显式传参改为基类存储的 `callbackGasLimit`（ABI breaking）。

**Architecture:** 主合约继承链由 `is NoDelegateCall, Ownable, DeadLine, EntropyConsumer, IErrors, IGreatLotto` 改为 `is NoDelegateCall, Ownable, EntropyConsumerBase, IErrors, IGreatLotto`（基类自带 `IEntropyConsumer + AccessControl + DeadLine`）。Constructor 中 `_grantRole(DEFAULT_ADMIN_ROLE, owner_)` 让 owner 兼任治理 admin，复用 base 的三个 setter；`Ownable` 暂时保留以兼容外部 `owner()` 读取者。

**Tech Stack:** Solidity 0.8.35 / Cancun / viaIR / optimizer enabled（已就绪，无需升级）· `@greatlotto/infrastructure`（含 Phase 1 基类）· Hardhat 2.28.6

**Working directory:** `/Users/tongren/Documents/github/GreatLottoGroup/GreatLottoCore`

**Prerequisites:**
- Phase 1 PR 已 merge 并发布
- Phase 2 不是前置（Phase 2 / Phase 3 互相独立）

---

## File Structure

| 路径 | 操作 | 说明 |
|---|---|---|
| `package.json` | 修改 | bump `@greatlotto/infrastructure` |
| `contracts/GreatLotto.sol` | 重写 entropy 相关段 | 切基类、删冗余、改造 request/callback/retry、ABI 改动 |
| `contracts/base/EntropyConsumer.sol` | **删除** | 已被 infra 基类取代 |
| `contracts/interfaces/IGreatLotto.sol` | 修改 | 删除 `LottoDrawRetried` / `RetryBlockGapChanged` 事件、错误 `GreatLottoRetryTooEarly`，调整 `requestDraw` / `issueTicketAndDraw` ABI |
| `test/runTest/*.test.js` | 修改 | 适配 ABI / 事件 / 错误名变化 |

---

## Task 1: Bump infrastructure 依赖 + 编译基线

**Files:**
- Modify: `package.json`

- [ ] **Step 1: 升级 dep**

```bash
cd /Users/tongren/Documents/github/GreatLottoGroup/GreatLottoCore
npm install --save '@greatlotto/infrastructure@<phase1-version>'
```

- [ ] **Step 2: 验证可解析**

```bash
ls node_modules/@greatlotto/infrastructure/contracts/base/EntropyConsumerBase.sol
ls node_modules/@greatlotto/infrastructure/contracts/interfaces/IEntropyConsumerBase.sol
```

- [ ] **Step 3: 编译当前 GLC（应仍能 compile）**

```bash
npx hardhat compile
```

- [ ] **Step 4: Commit**

```bash
git add package.json package-lock.json
git commit -m "chore(deps): bump @greatlotto/infrastructure for EntropyConsumerBase"
```

---

## Task 2: 删除旧 `EntropyConsumer.sol` + 切基类继承 + 改 constructor

**Files:**
- Delete: `contracts/base/EntropyConsumer.sol`
- Modify: `contracts/GreatLotto.sol`

- [ ] **Step 1: 删除旧基类文件**

```bash
git rm contracts/base/EntropyConsumer.sol
```

- [ ] **Step 2: 改 imports（[GreatLotto.sol:1-19](../../GreatLottoCore/contracts/GreatLotto.sol#L1-L19)）**

把：

```solidity
import "@greatlotto/infrastructure/contracts/base/DeadLine.sol";
import "@greatlotto/infrastructure/contracts/base/NoDelegateCall.sol";
import "./base/EntropyConsumer.sol";
```

替换为：

```solidity
import "@greatlotto/infrastructure/contracts/base/NoDelegateCall.sol";
import "@greatlotto/infrastructure/contracts/base/EntropyConsumerBase.sol";
```

`DeadLine` 由 `EntropyConsumerBase` transitively 提供。

- [ ] **Step 3: 改继承声明（[GreatLotto.sol:19](../../GreatLottoCore/contracts/GreatLotto.sol#L19)）**

```solidity
contract GreatLotto is NoDelegateCall, Ownable, EntropyConsumerBase, IErrors, IGreatLotto {
```

> Note：`Ownable` 暂时保留——若外部合约 / 前端没有读 `owner()`，可在 follow-up PR 删除 `Ownable` 一统到 `AccessControl`。本次为最小变更。

- [ ] **Step 4: 删除冗余 storage（[GreatLotto.sol:25-29](../../GreatLottoCore/contracts/GreatLotto.sol#L25-L29)）**

删除：

```solidity
uint64 public retryBlockGap = 256;
mapping(uint64 => uint256) private _seqToTokenId;
```

- [ ] **Step 5: 改 constructor（[GreatLotto.sol:31-45](../../GreatLottoCore/contracts/GreatLotto.sol#L31-L45)）**

```solidity
constructor(
    address pool,
    address nft,
    address coin,
    address entropyAddress,
    address entropyProviderAddress,
    address _owner
)
    Ownable(_owner == address(0) ? _msgSender() : _owner)
    EntropyConsumerBase(entropyAddress, entropyProviderAddress)
{
    PrizePoolAddress = pool;
    NFTAddress = nft;
    GreatLottoCoinAddress = coin;
    // 让 owner 兼任 entropy 治理 admin（base 的 setEntropyProvider 等用 DEFAULT_ADMIN_ROLE 校验）
    _grantRole(DEFAULT_ADMIN_ROLE, _owner == address(0) ? _msgSender() : _owner);
}
```

- [ ] **Step 6: 编译（应有大量错误，预期）**

```bash
npx hardhat compile
```

Expected：报 `_seqToTokenId / retryBlockGap / _requestEntropy / _refundExcessFee / _onDrawFulfilled` 等未定义。Task 3-6 逐个修复。

- [ ] **Step 7: Commit**

```bash
git add contracts/GreatLotto.sol
git rm contracts/base/EntropyConsumer.sol
git commit -m "refactor(greatlotto): switch to EntropyConsumerBase, drop local EntropyConsumer (compile-broken)"
```

---

## Task 3: 改造 `_doRequestDraw` 调用基类

**Files:**
- Modify: `contracts/GreatLotto.sol`
- Modify: `contracts/interfaces/IGreatLotto.sol`（删 `entropyGasLimit` 参数 / 错误）

- [ ] **Step 1: 调整 `IGreatLotto.sol` 函数签名**

把：

```solidity
function requestDraw(uint256 tokenId, uint32 entropyGasLimit, bytes32 userRandomNumber)
    external payable returns (uint64 sequenceNumber);
function issueTicketAndDraw(IssueParam memory issueParam, uint32 entropyGasLimit, bytes32 userRandomNumber)
    external payable returns (uint256 tokenId, uint64 sequenceNumber);
function issueTicketAndDrawWithSign(IssueParam memory issueParam, uint8 v, bytes32 r, bytes32 s, uint32 entropyGasLimit, bytes32 userRandomNumber)
    external payable returns (uint256 tokenId, uint64 sequenceNumber);
```

改为去掉 `entropyGasLimit` 参数：

```solidity
function requestDraw(uint256 tokenId, bytes32 userRandomNumber)
    external payable returns (uint64 sequenceNumber);
function issueTicketAndDraw(IssueParam memory issueParam, bytes32 userRandomNumber)
    external payable returns (uint256 tokenId, uint64 sequenceNumber);
function issueTicketAndDrawWithSign(IssueParam memory issueParam, uint8 v, bytes32 r, bytes32 s, bytes32 userRandomNumber)
    external payable returns (uint256 tokenId, uint64 sequenceNumber);
```

`getEntropyFee(uint32)` 改为无参，使用基类 `entropyFee()`：

```solidity
function getEntropyFee() external view returns (uint128 fee);
```

- [ ] **Step 2: 删除冗余 events / errors**

`IGreatLotto.sol`（具体行号以仓内文件为准）删除：
- `event LottoDrawRetried(...)` → 用基类 `RequestRetried`
- `event RetryBlockGapChanged(uint64)` → 已无对应字段
- `error GreatLottoRetryTooEarly(...)` → 用基类 `ErrorRetryNotAllowed`

保留：`LottoTicketMinted` / `LottoDrawRequested` / `LottoDrawFulfilled` / `DebtClaimed` / `GreatLottoNotTokenOwner` / `GreatLottoInvalidDrawState`。

- [ ] **Step 3: 改 GreatLotto.sol 的 `requestDraw`（[GreatLotto.sol:178-195](../../GreatLottoCore/contracts/GreatLotto.sol#L178-L195)）**

```solidity
function requestDraw(uint256 tokenId, bytes32 userRandomNumber)
    external
    payable
    noDelegateCall
    returns (uint64 sequenceNumber)
{
    address owner = IGreatLottoNFT(NFTAddress).ownerOf(tokenId);
    if (msg.sender != owner) {
        revert GreatLottoNotTokenOwner(tokenId, msg.sender, owner);
    }

    IGreatLottoNFT.Ticket memory ticket = IGreatLottoNFT(NFTAddress).getTicket(tokenId);
    if (ticket.drawState != IGreatLottoNFT.DrawState.None) {
        revert GreatLottoInvalidDrawState(tokenId, uint8(ticket.drawState));
    }

    sequenceNumber = _doRequestDraw(tokenId, ticket.netAmount, userRandomNumber);
}
```

- [ ] **Step 4: 改 `issueTicketAndDraw` / `issueTicketAndDrawWithSign`（[GreatLotto.sol:131-174](../../GreatLottoCore/contracts/GreatLotto.sol#L131-L174)）**

把每处 `_doRequestDraw(tokenId, ticket.netAmount, entropyGasLimit, userRandomNumber)` 调用改为：

```solidity
sequenceNumber = _doRequestDraw(tokenId, ticket.netAmount, userRandomNumber);
```

并把外部入口签名中的 `uint32 entropyGasLimit` 参数删除。

- [ ] **Step 5: 重写 `_doRequestDraw` 利用基类 `_postRequest` hook（CEI-correct）**

GLC 需要 `lockPending` / `setDrawRequested` 在 base 退余款（让出控制权）**之前**完成。基类提供的 `_postRequest(uint64 seq, Request memory req)` virtual hook（已在 Phase 1 内置）位于 `emit RequestSubmitted` 之后、`_refundFee` 之前，正好满足。

由于 `_postRequest` 只能拿到 base `Request` struct（不含 GLC 的 `netAmount`），用 EIP-1153 transient storage 在 `_doRequestDraw` 中临时持有 `netAmount` 供 hook 读取。Solidity 0.8.24+ / Cancun 已支持。

```solidity
// state（contract 顶部加）
uint256 private transient _pendingNetAmount;

function _doRequestDraw(
    uint256 tokenId,
    uint256 netAmount,
    bytes32 userRandomNumber
) private returns (uint64 sequenceNumber) {
    _pendingNetAmount = netAmount;          // transient: 同 tx 内可读
    (sequenceNumber, ) = _requestRandomness(
        tokenId,
        msg.sender,
        1,                                  // itemCount = 1
        userRandomNumber,
        msg.value
    );
    // _pendingNetAmount transient，不需要 delete（tx 结束自动清零）

    emit LottoDrawRequested(tokenId, sequenceNumber, msg.sender);
}

function _postRequest(uint64 sequenceNumber, Request memory req) internal override {
    IPrizePool(PrizePoolAddress).lockPending(req.tokenId, _pendingNetAmount);
    IGreatLottoNFT(NFTAddress).setDrawRequested(req.tokenId, sequenceNumber, uint64(block.number));
}
```

> **CEI 检查**：
> 1. `_pendingNetAmount` 写入（transient，仅 tx 内有效）
> 2. base `_requestRandomness`：内部 `requestV2`（外部调用）→ 写 `_request[seq]` → emit → **`_postRequest` 调用**（lockPending + setDrawRequested 完成）→ refund（让出控制权）
> 3. GLC `emit LottoDrawRequested`（最后 emit；emit 不让出控制权，OK）
>
> 全部业务 storage 写入都在 base refund **之前**完成，CEI 满足。

- [ ] **Step 6（可选）：编译，确认其他报错收敛**

剩下应只有 `retryDraw / _onDrawFulfilled / changeRetryBlockGap / getEntropyFee` 相关报错。

- [ ] **Step 7: Commit**

```bash
git add contracts/GreatLotto.sol contracts/interfaces/IGreatLotto.sol
git commit -m "refactor(greatlotto): _doRequestDraw delegates to base _requestRandomness, drop entropyGasLimit param"
```

---

- [ ] **Step 6: 编译 + Commit**

```bash
npx hardhat compile
```

剩余报错应只与 `retryDraw / _onDrawFulfilled / changeRetryBlockGap / getEntropyFee` 有关。

```bash
git add contracts/GreatLotto.sol contracts/interfaces/IGreatLotto.sol
git commit -m "refactor(greatlotto): _doRequestDraw delegates to base via _postRequest hook"
```

---

## Task 4: `_onDrawFulfilled → _onRequestFulfilled` 改名 + 签名匹配

**Files:**
- Modify: `contracts/GreatLotto.sol`

- [ ] **Step 1: 重写回调（[GreatLotto.sol:258-313](../../GreatLottoCore/contracts/GreatLotto.sol#L258-L313)）**

```solidity
function _onRequestFulfilled(
    uint64 sequence,
    Request memory req,
    bytes32 randomNumber
) internal override {
    uint256 tokenId = req.tokenId;

    IGreatLottoNFT.Ticket memory ticket = IGreatLottoNFT(NFTAddress).getTicket(tokenId);
    if (ticket.sequenceNumber != sequence || ticket.drawState != IGreatLottoNFT.DrawState.Requested) {
        // 过期回调或状态不匹配 → no-op（防御深度，base 已经做了 _request[seq].exists 检查）
        return;
    }

    address winner = IGreatLottoNFT(NFTAddress).ownerOf(tokenId);

    uint8[7] memory drawNumber = DrawUtils.getDrawNumberByEntropy(randomNumber);

    (uint bonus, uint topBonus) = DrawUtils.getRewardByList(ticket.numbers, drawNumber);
    if (ticket.multiple > 1) {
        bonus = bonus * ticket.multiple;
        topBonus = topBonus * ticket.multiple;
    }

    IPrizePool.SingleDrawParam memory param = IPrizePool.SingleDrawParam({
        tokenId: tokenId,
        winner: winner,
        drawNumber: drawNumber,
        normalAward: bonus,
        topBonusMultiples: topBonus,
        netAmount: ticket.netAmount
    });

    (uint256 normalAwardPaid, uint256 normalAwardDebt, uint256 topBonusAmount) =
        IPrizePool(PrizePoolAddress).fulfillDraw(param);

    IGreatLottoNFT(NFTAddress).setDrawFulfilled(
        tokenId, drawNumber, bonus, topBonus, topBonusAmount
    );

    emit LottoDrawFulfilled(
        tokenId, sequence, winner, drawNumber, bonus,
        normalAwardPaid, normalAwardDebt, topBonus, topBonusAmount
    );
}
```

要点：
- `_seqToTokenId[sequence]` 查询删除（基类已提供 `req.tokenId`）
- `delete _seqToTokenId[sequence]` 删除（基类已 `delete _request[sequence]`）
- 防御性的 ticket state 检查保留（base 不替代业务侧防御）

- [ ] **Step 2: 编译**

剩下应只有 `retryDraw / changeRetryBlockGap / getEntropyFee` 相关报错。

- [ ] **Step 3: Commit**

```bash
git add contracts/GreatLotto.sol
git commit -m "refactor(greatlotto): replace _onDrawFulfilled with base _onRequestFulfilled hook"
```

---

## Task 5: 删除 `retryDraw / changeRetryBlockGap` + 改 `getEntropyFee`

**Files:**
- Modify: `contracts/GreatLotto.sol`

- [ ] **Step 1: 删除 `retryDraw` 整个函数（[GreatLotto.sol:197-232](../../GreatLottoCore/contracts/GreatLotto.sol#L197-L232)）**

整段删掉。基类提供的 `retryRequest(uint64 oldSeq, bytes32 newRandom, uint256 deadline)` 直接对外暴露。

> **前端必读 ABI 变化**：原 `retryDraw(tokenId, gasLimit, random)` → 新 `retryRequest(oldSeq, random, deadline)`。前端从用 `tokenId` 触发 retry 改为：
> 1. 监听 `LottoDrawRequested` 事件拿到 `(tokenId, sequenceNumber)`
> 2. retry 时调 `retryRequest(sequenceNumber, newRandom, deadline)`
>
> 或者前端从 `IGreatLottoNFT.getTicket(tokenId).sequenceNumber` 读取 in-flight seq。

- [ ] **Step 2: 删除 `changeRetryBlockGap`（[GreatLotto.sol:342-346](../../GreatLottoCore/contracts/GreatLotto.sol#L342-L346)）**

整段删掉。owner 改用基类 `setEntropyTimeout(uint64)` 调整超时。

- [ ] **Step 3: 改 `getEntropyFee`（[GreatLotto.sol:338-340](../../GreatLottoCore/contracts/GreatLotto.sol#L338-L340)）**

改为：

```solidity
function getEntropyFee() external view returns (uint128) {
    return uint128(entropyFee());
}
```

或者直接删除（前端改用基类 `entropyFee()` public read）。如果前端代码已大量使用，保留 wrapper。

- [ ] **Step 4: 是否需要 `_beforeRetry` override**

GLC 当前 `retryDraw` 检查了 `ticket.drawState == Requested`。新基类 `retryRequest` 不会做这个检查——但因为 retryDraw 走通的前提就是某个 sequenceNumber 已经被 `_request[seq]` 记下，等价于 `ticket.drawState == Requested`，所以**默认无需 override**。

如果生产环境出现过 ticket state 与 `_request[seq]` 不一致的情形（理论上不该有），可以 override：

```solidity
function _beforeRetry(uint64 oldSeq, Request memory old) internal override {
    IGreatLottoNFT.Ticket memory ticket = IGreatLottoNFT(NFTAddress).getTicket(old.tokenId);
    if (ticket.sequenceNumber != oldSeq || ticket.drawState != IGreatLottoNFT.DrawState.Requested) {
        revert GreatLottoInvalidDrawState(old.tokenId, uint8(ticket.drawState));
    }
}
```

但 retry 成功后 base 会写 `_request[newSeq]`，业务侧还需要 `IGreatLottoNFT(NFTAddress).setDrawRequested(tokenId, newSeq, ...)` 同步 NFT 状态。**这个状态同步必须在 retry 路径里完成**。

- [ ] **Step 5: override base `_postRetry` 同步 NFT 状态**

retry 后必须把 NFT 上记录的 `sequenceNumber` 切换到 newSeq，否则 `_onRequestFulfilled` 内的防御性检查（`ticket.sequenceNumber != sequence` no-op）会让正确回调被吞掉。

利用基类 `_postRetry(oldSeq, newSeq, updated)` hook（已在 Phase 1 内置；位于 `emit RequestRetried` 之后、`_refundFee` 之前），在 contract 末尾添加：

```solidity
function _postRetry(
    uint64 /*oldSequenceNumber*/,
    uint64 newSequenceNumber,
    Request memory updated
) internal override {
    IGreatLottoNFT(NFTAddress).setDrawRequested(updated.tokenId, newSequenceNumber, uint64(block.number));
}
```

**CEI 检查**：base 内部顺序为 `requestV2` → 写 `_request[newSeq]` → emit `RequestRetried` → **`_postRetry`（NFT 状态同步）** → refund → 返回。NFT 状态写入在让出控制权之前完成。

- [ ] **Step 6: 编译**

```bash
npx hardhat compile
```

Expected：编译通过。

- [ ] **Step 7: Commit**

```bash
git add contracts/GreatLotto.sol
git commit -m "refactor(greatlotto): drop retryDraw + changeRetryBlockGap, override _postRetry for NFT state sync"
```

---

## Task 6: 适配测试套件

**Files:**
- Modify: `test/runTest/*.test.js`（GLC 现有测试）
- Modify: `test/utils/*.js`（如有共享 fixture）

- [ ] **Step 1: 跑测试列出失败用例**

```bash
cd /Users/tongren/Documents/github/GreatLottoGroup/GreatLottoCore
npx hardhat test 2>&1 | tee /tmp/glc-test-fails.log
```

- [ ] **Step 2: 全局替换映射表**

| 原 | 新 |
|---|---|
| `requestDraw(tokenId, gasLimit, random)` | `requestDraw(tokenId, random)` |
| `issueTicketAndDraw(param, gasLimit, random)` | `issueTicketAndDraw(param, random)` |
| `issueTicketAndDrawWithSign(param, v, r, s, gasLimit, random)` | `issueTicketAndDrawWithSign(param, v, r, s, random)` |
| `retryDraw(tokenId, gasLimit, random)` | `retryRequest(seq, random, deadline)` — 注意参数语义彻底变化，需要从 NFT 查 seq |
| `getEntropyFee(gasLimit)` | `getEntropyFee()` |
| `changeRetryBlockGap(gap)` | `setEntropyTimeout(seconds)` |
| `LottoDrawRetried` 事件 | `RequestRetried` (参数列：`oldSeq, newSeq, requester, oldFee, newFee`) |
| `RetryBlockGapChanged` 事件 | `EntropyTimeoutChanged(oldTimeout, newTimeout)` |
| `GreatLottoRetryTooEarly` 错误 | `ErrorRetryNotAllowed` |
| `EntropyInsufficientFee` 错误 | `ErrorInsufficientEntropyFee` |

- [ ] **Step 3: 重写 retry 用例的"等到可重试"逻辑**

原："`mine 256 blocks` 然后 `retryDraw(tokenId, ...)`"。
新："`evm_increaseTime(3601)` + `evm_mine` 然后从 NFT 查 seq + `retryRequest(seq, random, deadline)`"。

```javascript
// 旧
for (let i = 0; i < 256; i++) await ethers.provider.send("evm_mine");
await greatLotto.connect(alice).retryDraw(tokenId, gasLimit, newRandom, { value: fee });

// 新
await ethers.provider.send("evm_increaseTime", [3601]);
await ethers.provider.send("evm_mine");
const ticket = await greatLottoNFT.getTicket(tokenId);
const oldSeq = ticket.sequenceNumber;
const deadline = (await ethers.provider.getBlock("latest")).timestamp + 600;
await greatLotto.connect(alice).retryRequest(oldSeq, newRandom, deadline, { value: fee });
```

- [ ] **Step 4: 跑测试到 PASS**

```bash
npx hardhat test
```

Expected：全部用例 PASS。

- [ ] **Step 5: Commit**

```bash
git add test/
git commit -m "test(greatlotto): adapt to EntropyConsumerBase API"
```

---

## Task 7: Coverage / Size / 文档 + PR

- [ ] **Step 1: 编译大小**

```bash
npx hardhat clean && npx hardhat compile
```

Expected：`GreatLotto` < 24KiB；删除 `_seqToTokenId` 与 `retryDraw` 应让合约更小。

- [ ] **Step 2: 覆盖率**

```bash
npx hardhat coverage --testfiles "test/runTest/*.js"
```

Expected：覆盖率不降。

- [ ] **Step 3: 更新 CLAUDE.md（如果有）**

如 GLC 仓库内有 CLAUDE.md，更新「随机数」段落，把 `EntropyConsumer.sol` 引用改为 `@greatlotto/infrastructure/contracts/base/EntropyConsumerBase.sol`，retry 模型从"区块差"改为"时间戳 + CALLBACK_FAILED"。

- [ ] **Step 4: 修订记录**

修改 `infrastructure/doc/entropy-consumer-base-design.md`：

```markdown
| v1.3 | <实施日期> | Phase 3 实施完成；GreatLotto 切换至 EntropyConsumerBase；新增 `_postRequest` / `_postRetry` hook |
```

- [ ] **Step 5: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(greatlotto): update after EntropyConsumerBase migration"
```

- [ ] **Step 6: Push + PR**

```bash
git push -u origin <branch-name>
gh pr create --title "refactor(greatlotto): migrate to EntropyConsumerBase" --body "$(cat <<'EOF'
## Summary
- GreatLotto 主合约改为继承 `EntropyConsumerBase`
- 删除本地 `contracts/base/EntropyConsumer.sol` / `_seqToTokenId` / `retryBlockGap` / `retryDraw` / `changeRetryBlockGap`
- 开奖结算迁移到 `_onRequestFulfilled`；新 `_postRequest` / `_postRetry` hook 完成 NFT 状态同步
- retry 模型由「区块差 256 blocks」改为「时间戳 + CALLBACK_FAILED」

## Breaking changes (前端必读)
- `requestDraw / issueTicketAndDraw[WithSign]` 删除 `entropyGasLimit` 参数（合约用存储的 `callbackGasLimit`，由 owner 通过 `setCallbackGasLimit` 调整）
- `retryDraw(tokenId, ...)` → `retryRequest(oldSeq, random, deadline)`，前端需要从 NFT 状态或 LottoDrawRequested 事件取 sequenceNumber
- `getEntropyFee(gasLimit)` → `getEntropyFee()`
- `changeRetryBlockGap` 删除；改用 `setEntropyTimeout`
- `LottoDrawRetried` 事件 → `RequestRetried`
- `RetryBlockGapChanged` 事件 → `EntropyTimeoutChanged`

## Test plan
- [x] 全部 hardhat 测试 PASS
- [x] 合约大小 < 24KiB
- [x] 覆盖率不降

## Follow-up
- GLC 前端同步 ABI / 事件订阅
- 后续可考虑删除 `Ownable`，统一到 `AccessControl`
EOF
)"
```

---

## Self-Review Checklist

- [ ] `contracts/base/EntropyConsumer.sol` 已被 `git rm`
- [ ] `GreatLotto.sol` 不再 import `@pythnetwork/...sol`
- [ ] `GreatLotto.sol` 不再有 `_seqToTokenId` / `retryBlockGap` / `_requestEntropy` / `_refundExcessFee` 引用
- [ ] `GreatLotto.sol` 不再有 `retryDraw` / `changeRetryBlockGap` / `_onDrawFulfilled` 函数
- [ ] `_onRequestFulfilled` 签名匹配基类：`(uint64, Request memory, bytes32) internal override`
- [ ] `_postRequest` / `_postRetry` override 完成 NFT 状态同步
- [ ] Constructor 中 `_grantRole(DEFAULT_ADMIN_ROLE, owner_)` 已生效，owner 可调 base 的 setEntropyProvider 等
- [ ] ABI 变更已在 PR description 明确列出
- [ ] 测试套件全部 PASS
