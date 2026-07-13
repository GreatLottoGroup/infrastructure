# EntropyConsumerBase 设计文档

> **状态**：Draft v1 · 2026-05-31
> **提案人**：协作设计（Claude + 项目维护者）
> **影响仓库**：`infrastructure`（新增基类）、`ScratchCard`（适配）、`GreatLottoCore`（适配）

## 1. 背景与目标

`GreatLottoCore`（GLC）与 `ScratchCard`（SC）两个合约都依赖 Pyth Entropy V2 完成异步随机数请求 + 回调结算 + 失败/超时重试。两边目前各自实现了一套 request → callback → retry 流水：

- **GLC** 已经把"请求 + fee 退还 + 回调派发"抽到了 `contracts/base/EntropyConsumer.sol`，但 retry / 治理 setter 仍在 `GreatLotto.sol` 主合约。
- **SC** 整套流水（含 retry、治理 setter）都内联在 `contracts/ScratchCard.sol`。

两边业务层差异不小（GLC 单票一次开奖、SC 一次最多 10 张），但**随机数请求骨架完全一致**。本提案的目标：

1. 把通用的 entropy 请求 / 回调 / 重试 / 治理逻辑上提到 `infrastructure/contracts/base/EntropyConsumerBase.sol`；
2. SC 与 GLC 都改为继承 `EntropyConsumerBase`，业务子类只关心 `_onRequestFulfilled` 这一个钩子；
3. 为未来第三个随机数消费方提供一致接口。

非目标：

- ❌ 不抽象业务层结算（DrawAlgo / 奖池 / 分润 / payout 兜底）；
- ❌ 不引入 treasury 垫付池或 fee 自动补贴（与 ScratchCard v3.2 review 决议保持一致：fee 不退还，类比 L2 gas）；
- ❌ 不在基类做 in-flight sequence 取消 / 撤回（设计上 retry 是唯一推进手段）。

## 2. 现状对比

### 2.1 GreatLottoCore

- 文件：[GreatLottoCore/contracts/base/EntropyConsumer.sol](../../GreatLottoCore/contracts/base/EntropyConsumer.sol)、[GreatLottoCore/contracts/GreatLotto.sol](../../GreatLottoCore/contracts/GreatLotto.sol)
- Pending 存储：`mapping(uint64 => uint256) _seqToTokenId`（仅 tokenId，业务上下文回 NFT 合约查）
- 重试触发：**区块差** `retryBlockGap = 256`
- Fee 退款：每次 request 都退多余 `msg.value`（`_refundExcessFee`）
- 多结果派生：在 `DrawUtils.getDrawNumberByEntropy` 内部从单个随机数派生多个开奖号码（`itemCount` 概念隐含在业务层）
- 回调派发：`entropyCallback → _onDrawFulfilled(seq, randomNumber)` virtual hook

### 2.2 ScratchCard

- 文件：[ScratchCard/contracts/ScratchCard.sol](../../ScratchCard/contracts/ScratchCard.sol)
- Pending 存储：`mapping(uint64 => PendingDraw) _pending`，struct 含 `{tokenId, owner, quantity, paidFee, requestedAt, exists}`
- 重试触发：**时间戳** `entropyTimeout = 1h`，且支持主动查 `CALLBACK_FAILED` 以提前重试
- Fee 退款：无自动 refund
- 多结果派生：回调里 `for (i = 0; i < quantity; i++)` 用 `keccak256(randomNumber, i)` 派生
- 回调派发：`entropyCallback` 全部内联（无 virtual hook）

### 2.3 共有 vs 业务专属

| 维度 | 共有（可抽象） | 业务专属（留子类） |
|---|---|---|
| 请求骨架 `getFeeV2` → `requestV2{value: fee}` → 写 pending | ✅ | — |
| 多余 fee 退还（CEI 模式） | ✅（统一）| — |
| 回调入口 `entropyCallback` + `exists` 软删除 | ✅ | — |
| 重试触发判断（超时 OR `CALLBACK_FAILED`） | ✅ | — |
| 治理 setter（provider / gasLimit / timeout） | ✅ | — |
| `userRandomNumber != bytes32(0)` 校验 | ✅ | — |
| `_onRequestFulfilled` 内的结算逻辑 | — | ✅（GLC：更新 NFT；SC：DrawAlgo + payout） |
| 多结果派生的具体方式 | — | ✅（GLC：业务库内部；SC：keccak 循环） |
| Pending struct 业务字段 | — | ✅ via 基类 `tokenId/itemCount` 通用槽 |
| Pause / 状态门控（SC `isPaused/isStopped`） | — | ✅ |
| Payout 兜底 / `_pendingPayouts` | — | ✅（仅 SC 关心） |

## 3. 抽象边界

### 3.1 基类持有的状态

```solidity
// 不可变
IEntropyV2 public immutable entropy;

// 可变（治理）
address public entropyProvider;          // 默认部署时传入
uint32  public callbackGasLimit;         // 默认 2_500_000
uint64  public entropyTimeout;           // 默认 1 hours

// Pending（3 storage slot / 条目）
struct Request {
    uint256 tokenId;       // slot 1：业务侧 token 标识（NFT id 等，子类自定义语义）
    address requester;     // slot 2: 20 bytes
    uint64  requestedAt;   //         8 bytes
    uint32  itemCount;     //         4 bytes ← 32 bytes 槽满
    uint128 paidFee;       // slot 3: 16 bytes
    bool    exists;        //         1 byte（软删除标记）
}
mapping(uint64 sequenceNumber => Request) internal _request;
```

**关于字段选择的说明**：

- `tokenId`、`itemCount` 是把通用程度最高的两个业务字段提到基类，让子类完全不用维护并行 `seq → BizContext` mapping。`itemCount` 作为"从这一份 Pyth 随机数里派生几个独立结果"的通用概念，GLC 默认填 1，SC 填 quantity。
- 其余业务字段（如 SC 的 awards、GLC 的 DrawState）由子类通过 `tokenId` 反查自身 storage 拿到。
- `paidFee` 仅作记录（供事件 / 审计 / 未来扩展），基类不基于它做退款判断。
- `exists` 是软删除标记，用于回调阶段判断 sequence 是否已被 retry 替换（防止晚到回调误处理）。

### 3.2 边界常量

```solidity
uint64 public constant MIN_ENTROPY_TIMEOUT = 60;        // 60s
uint64 public constant MAX_ENTROPY_TIMEOUT = 24 hours;
uint32 public constant MIN_CALLBACK_GAS    = 100_000;
uint32 public constant MAX_CALLBACK_GAS    = 5_000_000;
```

## 4. 架构与放置

### 4.1 文件结构

```
infrastructure/
├─ contracts/
│  ├─ base/
│  │  └─ EntropyConsumerBase.sol         ← 新增：抽象基类
│  ├─ interfaces/
│  │  └─ IEntropyConsumerBase.sol        ← 新增：事件 / 错误 / 公共读 ABI
│  └─ test/
│     └─ MockEntropyConsumer.sol         ← 新增：测试用最小子类
├─ doc/
│  └─ entropy-consumer-base-design.md    ← 本文档
├─ test/
│  └─ runTest/
│     └─ EntropyConsumerBase.test.js     ← 新增：基类单元测试
└─ package.json                           ← 新增依赖
```

### 4.2 继承链

```
EntropyConsumerBase is IEntropyConsumer, AccessControl, DeadLine
```

- `IEntropyConsumer`：来自 `@pythnetwork/entropy-sdk-solidity`，是 abstract 类，提供 `entropyCallback` 派发（强制 sender == entropy 合约）；
- `AccessControl`：治理 setter 用 `DEFAULT_ADMIN_ROLE`；
- `DeadLine`：来自 infra，给 `retryRequest` 提供 deadline 校验，与 SC / GLC 现有 deadline 模式一致。

子类继续 `is EntropyConsumerBase`，可叠加 `AccessControlPartnerContract`、`NoDelegateCall` 等业务约束（Solidity 多继承去重，重复 `AccessControl` 无问题）。

### 4.3 依赖

`infrastructure/package.json` 新增：

```jsonc
{
  "dependencies": {
    "@openzeppelin/contracts": "5.6.1",
    "@pythnetwork/entropy-sdk-solidity": "^2.2.0"
  }
}
```

## 5. 基类详细设计

### 5.1 公开接口

| 成员 | 类型 | 说明 |
|---|---|---|
| `entropy()` | `IEntropyV2` view | 已 immutable |
| `entropyProvider()` | `address` view | 治理可改 |
| `callbackGasLimit()` | `uint32` view | 治理可改 |
| `entropyTimeout()` | `uint64` view | 治理可改 |
| `entropyFee() returns (uint256)` | view | `entropy.getFeeV2(provider, callbackGasLimit)` |
| `getRequest(uint64 seq) returns (Request)` | view | 暴露 pending（前端轮询/调试用）|
| `retryRequest(uint64 oldSeq, bytes32 newUserRandom, uint256 deadline) returns (uint64 newSeq, uint128 paidFee)` | external payable | 统一 retry 入口；返回新 seq + 本次实付 entropy fee |
| `setEntropyProvider(address)` | external, `DEFAULT_ADMIN_ROLE` | provider 热切 |
| `setCallbackGasLimit(uint32)` | external, `DEFAULT_ADMIN_ROLE` | 边界 `[100_000, 5_000_000]` |
| `setEntropyTimeout(uint64)` | external, `DEFAULT_ADMIN_ROLE` | 边界 `[60s, 24h]` |

### 5.2 事件

```solidity
event RequestSubmitted(
    uint64 indexed sequenceNumber,
    address indexed requester,
    uint256 indexed tokenId,
    uint32 itemCount,
    uint128 paidFee
);

event RequestFulfilled(
    uint64 indexed sequenceNumber,
    address indexed requester,
    uint256 indexed tokenId
);

event RequestRetried(
    uint64 indexed oldSequenceNumber,
    uint64 indexed newSequenceNumber,
    address indexed requester,
    uint128 oldFee,
    uint128 newFee
);

event EntropyProviderChanged(address oldProvider, address newProvider);
event CallbackGasLimitChanged(uint32 oldLimit, uint32 newLimit);
event EntropyTimeoutChanged(uint64 oldTimeout, uint64 newTimeout);
```

子类如需附加业务字段（quantity、awards、bonus 等），可在 `_onRequestFulfilled` 内额外 emit 自己的业务事件——基类事件 + 业务事件双发是预期模式。

### 5.3 自定义错误

```solidity
error ErrorInvalidUserRandom();                          // userRandom == bytes32(0)
error ErrorInsufficientEntropyFee(uint256 needed, uint256 paid);
error ErrorRequestNotFound();                            // _request[seq].exists == false
error ErrorNotRequester();                               // retry caller != original requester
error ErrorRetryNotAllowed();                            // 未超时且未 CALLBACK_FAILED
error ErrorInvalidEntropyTimeout();
error ErrorInvalidCallbackGasLimit();
error ErrorRefundFailed();
error ErrorZeroAddress();
```

### 5.4 子类钩子

```solidity
/// 必须由子类实现：业务结算逻辑
function _onRequestFulfilled(
    uint64 sequenceNumber,
    Request memory req,
    bytes32 randomNumber
) internal virtual;

/// 可选：在 base 退余款（让出控制权）前继续写业务 storage / emit 业务事件
function _postRequest(
    uint64 sequenceNumber,
    Request memory req
) internal virtual {}

/// 可选：retry 前业务校验（默认空）
function _beforeRetry(
    uint64 oldSequenceNumber,
    Request memory old
) internal virtual {}

/// 可选：retry 后在 base 退余款前同步业务状态
function _postRetry(
    uint64 oldSequenceNumber,
    uint64 newSequenceNumber,
    Request memory updated
) internal virtual {}
```

**为什么需要 post hook：** 基类 `_requestRandomness` / `retryRequest` 在写完 `_request[seq]` + emit 之后会调 `_refundFee` 退还多余 `msg.value`。`call{value: ...}("")` 让出控制权给可能是合约的 caller，构成外部调用。子类若在 `_requestRandomness` 返回**之后**才写自己的 storage（例如 SC 的 `_pendingCount += 1`、GLC 的 `lockPending` / `setDrawRequested`），就违反 CEI；攻击者可在 fallback 中重入读到陈旧 state。`_postRequest` / `_postRetry` 给子类一个在 refund **之前**继续写 effects 的位置，使整体路径 CEI-correct。

### 5.5 子类调用的 internal API

```solidity
/// 子类业务入口（draw / requestDraw / buyAndDraw 等）调用
function _requestRandomness(
    uint256 tokenId,
    address requester,
    uint32 itemCount,
    bytes32 userRandomNumber,
    uint256 paid                  // 子类传 msg.value 或扣除业务收款后的 entropy 预算
) internal returns (uint64 sequenceNumber, uint128 paidFee);
```

内部完成：

1. 校验 `userRandomNumber != bytes32(0)`；
2. 校验 `paid >= entropyFee()`；
3. 调 `entropy.requestV2{value: fee}(provider, userRandom, callbackGasLimit)`；
4. 写入 `_request[sequenceNumber]`；
5. emit `RequestSubmitted`；
6. 调 `_postRequest(seq, req)` 让子类在让出控制权前继续写业务 effects；
7. **退还 `paid - fee` 给 `requester`**（CEI 模式：所有状态/hook 写完再退）。

## 6. 关键流程

### 6.1 请求

```
Subclass entry (draw / requestDraw / buyAndDraw / ...)
  ├─ 业务校验（owner / 余额 / 状态 / pause 等）
  ├─ 业务收款 / burn / 槽位预扣等
  ├─ _requestRandomness(tokenId, requester, itemCount, userRandom, paid)
  │    ├─ 校验 userRandom != 0
  │    ├─ 校验 paid >= fee
  │    ├─ requestV2{value: fee}(...)
  │    ├─ _request[seq] = {...}
  │    ├─ emit RequestSubmitted
  │    ├─ _postRequest(seq, req)        ← 子类同步业务 effects
  │    └─ refund(paid - fee, requester) ← 让出控制权
  └─ [子类可选额外 emit 业务事件]
```

### 6.2 回调（基类 final，子类不可覆盖）

```
entropyCallback(seq, _, randomNumber)         ← Pyth 已校验来源
  ├─ if (!_request[seq].exists) return;       ← 晚到回调静默
  ├─ Request memory req = _request[seq];
  ├─ delete _request[seq];                    ← 先删后调（防重入）
  ├─ _onRequestFulfilled(seq, req, randomNumber);  ← 子类业务结算
  └─ emit RequestFulfilled(seq, req.requester, req.tokenId)
```

设计要点：

- `entropyCallback` 标记为 `final`（通过不声明 virtual 实现），子类只能改 `_onRequestFulfilled`，不能绕过软删除 / 事件；
- 软删除 (`delete _request[seq]`) 在 hook 调用前完成，避免子类内部重入读到陈旧数据；
- `_onRequestFulfilled` 抛出会回滚整个回调，导致 Pyth 标记为 `CALLBACK_FAILED`，触发 retry 路径。

### 6.3 重试

```
retryRequest(oldSeq, newUserRandom, deadline)
  ├─ checkDeadline(deadline)
  ├─ Request memory old = _request[oldSeq];
  ├─ require(old.exists, ErrorRequestNotFound)
  ├─ require(old.requester == msg.sender, ErrorNotRequester)
  ├─ require(newUserRandom != 0, ErrorInvalidUserRandom)
  │
  ├─ bool timedOut = block.timestamp >= old.requestedAt + entropyTimeout;
  ├─ bool callbackFailed = false;
  ├─ if (!timedOut) {
  │     EntropyStructsV2.Request memory pythReq = entropy.getRequestV2(entropyProvider, oldSeq);
  │     callbackFailed = (pythReq.callbackStatus == EntropyStatusConstants.CALLBACK_FAILED);
  │   }
  ├─ require(timedOut || callbackFailed, ErrorRetryNotAllowed)
  │
  ├─ _beforeRetry(oldSeq, old);                ← 子类可加业务校验
  │
  ├─ uint256 fee = entropyFee();
  ├─ require(msg.value >= fee, ErrorInsufficientEntropyFee)
  ├─ uint64 newSeq = entropy.requestV2{value: fee}(provider, newUserRandom, callbackGasLimit);
  │
  ├─ delete _request[oldSeq];
  ├─ _request[newSeq] = Request({
  │     tokenId:     old.tokenId,
  │     requester:   old.requester,
  │     itemCount:   old.itemCount,
  │     paidFee:     uint128(fee),
  │     requestedAt: uint64(block.timestamp),
  │     exists:      true
  │   });
  │
  ├─ emit RequestRetried(oldSeq, newSeq, old.requester, old.paidFee, uint128(fee));
  ├─ _postRetry(oldSeq, newSeq, _request[newSeq]);   ← 子类同步业务状态（如 NFT setDrawRequested）
  ├─ refund(msg.value - fee, msg.sender);            ← 让出控制权
  └─ return newSeq;
```

设计要点：

- `_beforeRetry` 默认空；GLC 可在此覆盖检查 `DrawState.Requested` 等业务前置条件；SC 当前无需覆盖；
- `_postRetry` 默认空；GLC 可在此覆盖把 NFT 状态从老 seq 切换到新 seq；与 `_postRequest` 同样位于 refund 前以保持 CEI；
- 老 fee **不退还**（与 v3.2 review 决议一致，类比 L2 gas）；
- retry 不重新跑业务前置（如 `isPaused/isStopped` 检查）——这是 SC 现行设计 D6：retry 仅推进已 in-flight 的请求，不阻塞；
- pending 净增减为 0：`delete oldSeq + write newSeq`，外部观察的"在飞数量"保持稳定。

## 7. 子类适应性改造

### 7.1 ScratchCard

**删除**：

- `PendingDraw` struct + `_pending` mapping → 用基类 `Request` + `_request`
- `entropyAddressImmutable` / `entropyProvider` / `callbackGasLimit` / `entropyTimeout` 状态变量 → 全在基类
- `setEntropyProvider` / `setCallbackGasLimit` / `setEntropyTimeout` setter → 全在基类
- `EntropyProviderChanged` / `CallbackGasLimitChanged` / `EntropyTimeoutChanged` 事件 → 全在基类
- `retryDraw` 函数 → 用基类 `retryRequest`
- `ScratchCardDrawRetried` 事件 → 用基类 `RequestRetried`
- `ScratchCardDrawRequested` 中的 `sequenceNumber` 字段 → 用基类 `RequestSubmitted`（业务事件可保留 quantity 等业务字段）

**保留 / 改造**：

- `draw / buyAndDraw / buyAndDrawWithSign` 入口保留，内部 `_requestDraw` 改为：
  - 业务侧扣槽位（`_remainingCards -= quantity`）、burn card、收款、`_pendingCount++` 仍在子类完成；
  - 调 `_requestRandomness(tokenId, buyer, quantity, userRandom, entropyBudget)`；
  - 子类可选 emit `ScratchCardDrawRequested(tokenId, owner, sequenceNumber, quantity)`，与基类 `RequestSubmitted` 并发。
- `entropyCallback` → 拆出 `_onRequestFulfilled`：循环 `for (i = 0; i < req.itemCount; i++)`、DrawAlgo 抽奖、`mintTicket`、try/catch `_payBonus` 兜底 `_pendingPayouts`、emit 业务事件 `ScratchCardDrawn`。
- `pauseCard / unpauseCard / stopCard` 不变。
- `claimPayout` / `_pendingPayouts` 不变（业务兜底，与本提案正交）。

**前端影响**：

- `retryDraw → retryRequest`（参数同：oldSeq, newUserRandom, deadline）
- 旧 `ScratchCardDrawRetried` 事件改为基类 `RequestRetried`
- 其他事件 ABI 兼容（业务事件保留）

### 7.2 GreatLottoCore

**删除**：

- `contracts/base/EntropyConsumer.sol`（已上提到 infra 改名）
- `_seqToTokenId` mapping（用基类 `_request[seq].tokenId`）
- `retryBlockGap` 状态变量 + `changeRetryBlockGap` 治理函数（语义切换为 `entropyTimeout` + `setEntropyTimeout`）
- `retryDraw` 函数 → 用基类 `retryRequest`
- `LottoDrawRetried` 事件 → 用基类 `RequestRetried`
- `RetryBlockGapChanged` 事件（已无对应字段）

**保留 / 改造**：

- `requestDraw / issueTicketAndDraw` 入口保留，内部 `_doRequestDraw` 改为调 `_requestRandomness(tokenId, requester, 1, userRandom, msg.value)`（itemCount = 1）；
- `_onDrawFulfilled` 改名 `_onRequestFulfilled`，签名匹配基类（`(uint64, Request memory, bytes32)`），内部从 `req.tokenId` 拿 tokenId；
- 如有 DrawState 前置校验需要在 retry 时跑，覆盖 `_beforeRetry` 实现。

**重要语义变化**：

- 重试触发从"区块差"变为"时间戳 + CALLBACK_FAILED"。前端从 `retryBlockGap` / `requestBlockNumber` 改读 `entropyTimeout` / `requestedAt`。

### 7.3 Solidity 版本对齐

- infra：0.8.35 / Cancun（已就绪）
- ScratchCard：0.8.35（已 bump，commit 7af3690）
- GreatLottoCore：当前需升级到 0.8.35（与 infra 对齐）

## 8. 测试策略

### 8.1 基类单元测试（infra 仓库内）

文件：`infrastructure/test/runTest/EntropyConsumerBase.test.js`

辅助合约：`contracts/test/MockEntropyConsumer.sol`（最小子类，`_onRequestFulfilled` 把 randomNumber 写入 mapping 供断言；可选实现 `_beforeRetry` revert 测试钩子串接）。

测试用例（覆盖路径）：

| 场景 | 期望 |
|---|---|
| 成功 request | sequenceNumber 返回，`_request[seq].exists == true`，emit `RequestSubmitted`，`paid - fee` 退给 requester |
| `userRandom == bytes32(0)` | revert `ErrorInvalidUserRandom` |
| `paid < fee` | revert `ErrorInsufficientEntropyFee(fee, paid)` |
| 正常 callback | `_onRequestFulfilled` 被调用一次，`_request[seq]` 已删除，emit `RequestFulfilled` |
| callback 时 `exists == false`（晚到回调） | 静默 return，不抛错、不 emit |
| `_onRequestFulfilled` revert | 整个 callback 回滚（验证可触发 Pyth `CALLBACK_FAILED` 路径） |
| retry 已超时 | 成功；老 seq 删、新 seq 写、emit `RequestRetried`、退多余 fee |
| retry 未超时但 `CALLBACK_FAILED` | 成功 |
| retry 未超时且未 failed | revert `ErrorRetryNotAllowed` |
| retry 非 requester 调用 | revert `ErrorNotRequester` |
| retry 不存在的 seq | revert `ErrorRequestNotFound` |
| retry `msg.value < fee` | revert `ErrorInsufficientEntropyFee` |
| `_beforeRetry` revert | retry 整体回滚（钩子串接验证） |
| governance setter 边界 | `setCallbackGasLimit` < 100k / > 5M revert；`setEntropyTimeout` < 60s / > 24h revert |
| governance setter 非 admin 调用 | revert AccessControl |
| provider 切换不影响 in-flight | retry 用新 provider，老 seq 仍可在原 provider 完成回调 |

Mock entropy 用 Pyth 官方 `MockEntropy`（SC 已经在 `contracts/test/MockEntropyHarness.sol` 中使用，可参照该模式）。

### 8.2 SC / GLC 集成测试

- SC：保留现有 `test/runTest/ScratchCard.test.js` / `M2Features.test.js`，仅适配新接口（`retryDraw → retryRequest`、事件重命名）；不重测基类机制本身。
- GLC：现有 entropy 相关测试改造适配新接口。

## 9. 兼容性与迁移

| 风险 / 项 | 处理 |
|---|---|
| **GLC 主网部署状态** | 未部署。可单 phase 完成全量切换（base + SC + GLC 同步）|
| **Solidity 版本** | infra 0.8.35 + SC 0.8.35 已就绪；GLC 本提案附带升级到 0.8.35 |
| **Pyth SDK 版本** | infra 加 `@pythnetwork/entropy-sdk-solidity ^2.2.x`，与 SC 对齐 |
| **OZ 版本** | 全部 5.6.1（已对齐）|
| **Storage 布局** | SC `_pending` (3 槽) → 基类 `_request` (3 槽，相同槽内排列顺序)。SC 未主网部署，layout 可自由变。GLC 同理。|
| **公开 ABI 变化** | `retryDraw → retryRequest`、`retryBlockGap` 移除 / 新增 `entropyTimeout`、retry 事件统一为 `RequestRetried`。两边前端（interface 仓 + GLC 前端）需要同步改。本设计要求**前后端一并升级**，不留兼容垫片。|
| **ABI 兼容**（治理事件） | 旧 `EntropyProviderChanged(newProvider)` 增加 `oldProvider` 字段（重命名同名事件，参数列表变化）。前端订阅需更新。|
| **`AccessControlPartnerContract` 互操作** | 基类用普通 `AccessControl`；子类如继续使用 `AccessControlPartnerContract`，其覆盖的 `grantRole` 行为不受本提案影响——不属于本提案引入的新约束。（注：`grantRole` 的「必须是合约地址」校验已在 `grantrole-role-gated-contract-check` change 中改为**仅对 `PARTNER_CONTRACT_ROLE` 生效**；`DEFAULT_ADMIN_ROLE` 可授予 EOA/多签。）|

## 10. YAGNI 边界（明确不做）

- ❌ Treasury 垫付池 / fee 自动补贴
- ❌ ScratchCard 的 `_pendingPayouts` / `claimPayout` 抽象（业务兜底，与随机数无关）
- ❌ ScratchCard 的 `_remainingCards / _pendingCount` 抽象（DrawAlgo 槽位机制，与请求/回调正交）
- ❌ Provider 切换时自动取消 in-flight sequence（设计：provider 切换不影响在飞）
- ❌ 多 provider 同时支持（基类只持有单一 `entropyProvider`）
- ❌ 跨 chain 抽象（每条链独立部署，无跨链状态）

## 11. 实施清单（高层，详细计划见后续 implementation plan）

阶段 1：infra 基类落地

1. 在 `infrastructure/package.json` 加 Pyth SDK 依赖
2. 写 `IEntropyConsumerBase.sol`（事件 / 错误 / Request struct）
3. 写 `EntropyConsumerBase.sol`
4. 写 `MockEntropyConsumer.sol` + `EntropyConsumerBase.test.js`
5. infra 仓库 PR 合并

阶段 2：ScratchCard 适配

1. SC 主合约切换为 `is EntropyConsumerBase`
2. 删除冗余 storage / 事件 / setter / `retryDraw`
3. `_requestDraw` / `entropyCallback` 改造
4. 现有测试套件适配
5. interface 仓库前端同步（`retryDraw → retryRequest`、事件订阅更新）

阶段 3：GreatLottoCore 适配

1. 升级 0.8.35
2. 主合约切换为 `is EntropyConsumerBase`
3. 删除 `EntropyConsumer.sol` / `_seqToTokenId` / `retryBlockGap` 等
4. `retryDraw → retryRequest`，业务侧 retry 校验通过 `_beforeRetry` 完成
5. 现有测试套件适配
6. GLC 前端同步

## 12. 开放问题

- 暂无。如实施过程中发现新问题，本文档会补充 v2 / v3 修订记录。

---

## 附录 A：基类签名参考（伪代码全貌）

```solidity
// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.35;

import {IEntropyConsumer} from "@pythnetwork/entropy-sdk-solidity/IEntropyConsumer.sol";
import {IEntropyV2} from "@pythnetwork/entropy-sdk-solidity/IEntropyV2.sol";
import {EntropyStructsV2} from "@pythnetwork/entropy-sdk-solidity/EntropyStructsV2.sol";
import {EntropyStatusConstants} from "@pythnetwork/entropy-sdk-solidity/EntropyStatusConstants.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {DeadLine} from "../base/DeadLine.sol";

abstract contract EntropyConsumerBase is IEntropyConsumer, AccessControl, DeadLine {
    // --- Constants ---
    uint64 public constant MIN_ENTROPY_TIMEOUT = 60;
    uint64 public constant MAX_ENTROPY_TIMEOUT = 24 hours;
    uint32 public constant MIN_CALLBACK_GAS = 100_000;
    uint32 public constant MAX_CALLBACK_GAS = 5_000_000;

    // --- Config ---
    IEntropyV2 public immutable entropy;
    address public entropyProvider;
    uint32  public callbackGasLimit;
    uint64  public entropyTimeout;

    // --- Pending ---
    struct Request {
        uint256 tokenId;
        address requester;
        uint64  requestedAt;
        uint32  itemCount;
        uint128 paidFee;
        bool    exists;
    }
    mapping(uint64 => Request) internal _request;

    // --- Events ---
    event RequestSubmitted(uint64 indexed sequenceNumber, address indexed requester, uint256 indexed tokenId, uint32 itemCount, uint128 paidFee);
    event RequestFulfilled(uint64 indexed sequenceNumber, address indexed requester, uint256 indexed tokenId);
    event RequestRetried(uint64 indexed oldSequenceNumber, uint64 indexed newSequenceNumber, address indexed requester, uint128 oldFee, uint128 newFee);
    event EntropyProviderChanged(address oldProvider, address newProvider);
    event CallbackGasLimitChanged(uint32 oldLimit, uint32 newLimit);
    event EntropyTimeoutChanged(uint64 oldTimeout, uint64 newTimeout);

    // --- Errors ---
    error ErrorInvalidUserRandom();
    error ErrorInsufficientEntropyFee(uint256 needed, uint256 paid);
    error ErrorRequestNotFound();
    error ErrorNotRequester();
    error ErrorRetryNotAllowed();
    error ErrorInvalidEntropyTimeout();
    error ErrorInvalidCallbackGasLimit();
    error ErrorRefundFailed();
    error ErrorZeroAddress();

    constructor(address entropy_, address entropyProvider_) {
        if (entropy_ == address(0) || entropyProvider_ == address(0)) revert ErrorZeroAddress();
        entropy = IEntropyV2(entropy_);
        entropyProvider = entropyProvider_;
        callbackGasLimit = 2_500_000;
        entropyTimeout = 1 hours;
    }

    // --- IEntropyConsumer ---
    function getEntropy() internal view override returns (address) {
        return address(entropy);
    }

    // --- Public reads ---
    function entropyFee() public view returns (uint256) {
        return entropy.getFeeV2(entropyProvider, callbackGasLimit);
    }
    function getRequest(uint64 sequenceNumber) external view returns (Request memory) {
        return _request[sequenceNumber];
    }

    // --- Subclass-facing internal ---
    function _requestRandomness(
        uint256 tokenId,
        address requester,
        uint32 itemCount,
        bytes32 userRandomNumber,
        uint256 paid
    ) internal returns (uint64 sequenceNumber, uint128 paidFee) {
        if (userRandomNumber == bytes32(0)) revert ErrorInvalidUserRandom();
        uint256 fee = entropyFee();
        if (paid < fee) revert ErrorInsufficientEntropyFee(fee, paid);

        sequenceNumber = entropy.requestV2{value: fee}(entropyProvider, userRandomNumber, callbackGasLimit);
        paidFee = uint128(fee);

        _request[sequenceNumber] = Request({
            tokenId: tokenId,
            requester: requester,
            requestedAt: uint64(block.timestamp),
            itemCount: itemCount,
            paidFee: paidFee,
            exists: true
        });

        emit RequestSubmitted(sequenceNumber, requester, tokenId, itemCount, paidFee);

        _postRequest(sequenceNumber, _request[sequenceNumber]);

        uint256 excess = paid - fee;
        if (excess > 0) _refundFee(requester, excess);
    }

    // --- Subclass post-request hook (optional) ---
    function _postRequest(uint64 /*sequenceNumber*/, Request memory /*req*/) internal virtual {}

    // --- Pyth callback ---
    function entropyCallback(uint64 sequenceNumber, address /*provider*/, bytes32 randomNumber) internal override {
        Request memory req = _request[sequenceNumber];
        if (!req.exists) return;
        delete _request[sequenceNumber];
        _onRequestFulfilled(sequenceNumber, req, randomNumber);
        emit RequestFulfilled(sequenceNumber, req.requester, req.tokenId);
    }

    // --- Subclass settlement hook (required) ---
    function _onRequestFulfilled(uint64 sequenceNumber, Request memory req, bytes32 randomNumber) internal virtual;

    // --- Public retry ---
    function retryRequest(uint64 oldSequenceNumber, bytes32 newUserRandomNumber, uint256 deadline)
        external
        payable
        checkDeadline(deadline)
        returns (uint64 newSequenceNumber, uint128 paidFee)
    {
        Request memory old = _request[oldSequenceNumber];
        if (!old.exists) revert ErrorRequestNotFound();
        if (old.requester != msg.sender) revert ErrorNotRequester();
        if (newUserRandomNumber == bytes32(0)) revert ErrorInvalidUserRandom();

        bool timedOut = block.timestamp >= old.requestedAt + entropyTimeout;
        bool callbackFailed = false;
        if (!timedOut) {
            EntropyStructsV2.Request memory pythReq = entropy.getRequestV2(entropyProvider, oldSequenceNumber);
            callbackFailed = pythReq.callbackStatus == EntropyStatusConstants.CALLBACK_FAILED;
        }
        if (!timedOut && !callbackFailed) revert ErrorRetryNotAllowed();

        _beforeRetry(oldSequenceNumber, old);

        uint256 fee = entropyFee();
        if (msg.value < fee) revert ErrorInsufficientEntropyFee(fee, msg.value);

        newSequenceNumber = entropy.requestV2{value: fee}(entropyProvider, newUserRandomNumber, callbackGasLimit);
        uint128 newFee = uint128(fee);

        delete _request[oldSequenceNumber];
        _request[newSequenceNumber] = Request({
            tokenId: old.tokenId,
            requester: old.requester,
            requestedAt: uint64(block.timestamp),
            itemCount: old.itemCount,
            paidFee: newFee,
            exists: true
        });

        emit RequestRetried(oldSequenceNumber, newSequenceNumber, old.requester, old.paidFee, newFee);

        _postRetry(oldSequenceNumber, newSequenceNumber, _request[newSequenceNumber]);

        uint256 excess = msg.value - fee;
        if (excess > 0) _refundFee(msg.sender, excess);
    }

    // --- Subclass retry pre-check (optional) ---
    function _beforeRetry(uint64 /*oldSequenceNumber*/, Request memory /*old*/) internal virtual {}

    // --- Subclass post-retry hook (optional) ---
    function _postRetry(
        uint64 /*oldSequenceNumber*/,
        uint64 /*newSequenceNumber*/,
        Request memory /*updated*/
    ) internal virtual {}

    // --- Refund helper ---
    function _refundFee(address to, uint256 amount) internal {
        (bool ok, ) = payable(to).call{value: amount}("");
        if (!ok) revert ErrorRefundFailed();
    }

    // --- Governance ---
    function setEntropyProvider(address newProvider) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newProvider == address(0)) revert ErrorZeroAddress();
        emit EntropyProviderChanged(entropyProvider, newProvider);
        entropyProvider = newProvider;
    }

    function setCallbackGasLimit(uint32 newLimit) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newLimit < MIN_CALLBACK_GAS || newLimit > MAX_CALLBACK_GAS) revert ErrorInvalidCallbackGasLimit();
        emit CallbackGasLimitChanged(callbackGasLimit, newLimit);
        callbackGasLimit = newLimit;
    }

    function setEntropyTimeout(uint64 newTimeout) external virtual onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newTimeout < MIN_ENTROPY_TIMEOUT || newTimeout > MAX_ENTROPY_TIMEOUT) revert ErrorInvalidEntropyTimeout();
        emit EntropyTimeoutChanged(entropyTimeout, newTimeout);
        entropyTimeout = newTimeout;
    }
}
```

## 附录 B：相关文件索引

- 设计参考：[ScratchCard/doc/draw-logic-design.md](../../ScratchCard/doc/draw-logic-design.md)（v3.2，开奖与异步流程的更高层设计）
- SC 主合约：[ScratchCard/contracts/ScratchCard.sol](../../ScratchCard/contracts/ScratchCard.sol)
- GLC 主合约：[GreatLottoCore/contracts/GreatLotto.sol](../../GreatLottoCore/contracts/GreatLotto.sol)
- GLC 当前 entropy 基类：[GreatLottoCore/contracts/base/EntropyConsumer.sol](../../GreatLottoCore/contracts/base/EntropyConsumer.sol)
- Pyth Entropy 文档：https://docs.pyth.network/entropy

## 修订记录

| 版本 | 日期 | 变更 |
|---|---|---|
| v1 | 2026-05-31 | 初稿 |
| v1.1 | 2026-05-31 | 修正 Pyth SDK 常量名为 `EntropyStatusConstants.CALLBACK_FAILED` |
| v1.2 | 2026-05-31 | 增加 `_postRequest` / `_postRetry` 虚钩，确保子类业务 effects 在 base 退余款（让出控制权）前完成，整体 CEI-correct |
| v1.3 | 2026-05-31 | Phase 1 实施完成；EntropyConsumerBase 落地 + 26 个单元测试用例 |
| v1.4 | 2026-05-31 | Phase 2 实施完成；ScratchCard 切换至 EntropyConsumerBase；63/63 测试通过 |
| v1.5 | 2026-05-31 | Phase 3 实施完成；GreatLotto 切换至 EntropyConsumerBase；删 retryBlockGap / changeRetryBlockGap / _seqToTokenId；新 _postRequest（transient netAmount 桥接）+ _postRetry（NFT 状态同步）|
