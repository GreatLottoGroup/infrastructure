# Design — add-entropy-consumer-base

> 完整跨仓分析、字段选择理由、流程图与附录代码见 [`doc/entropy-consumer-base-design.md`](../../../doc/entropy-consumer-base-design.md)（单一 source of truth）。本文件聚焦关键决策与权衡。

## Context

GLC 与 SC 两个仓库分别落地了 Pyth Entropy V2 的异步随机数闭环，但实现互相隔离：

- 重试模型不一致（GLC 256 区块差 vs SC 时间戳 + CALLBACK_FAILED）
- Fee 退款行为不一致（GLC 退、SC 不退）
- Pending struct 形态不一致（GLC 仅 `seq → tokenId`、SC 6 字段完整结构）
- 治理事件签名各异（GLC 单参数、SC 单参数；本 change 决议双参数 `(old, new)`）

跨仓对比 + 共有/差异维度分析详见设计文档第 2-3 节。

## Goals / Non-Goals

**Goals:**
- 把请求 / 回调 / 重试 / 治理 / fee 退还五件事抽到统一基类
- 保留业务子类对结算逻辑的完整自主（通过 4 个 virtual hook）
- 统一重试模型：超时 OR `EntropyStatusConstants.CALLBACK_FAILED`
- 提供 `_postRequest` / `_postRetry` 让子类在 base 退余款（让出控制权）前继续写业务 storage，保持 CEI

**Non-Goals:**
- 不引入跨链协调 / 多 provider 同时请求
- 不抽象业务结算（DrawAlgo / 奖池 / payout 兜底）
- 不改 Pyth SDK 调用契约（直接 `requestV2` / `getFeeV2` / `getRequestV2`）

## Decisions

### D1: 重试触发条件统一为 时间戳 OR CALLBACK_FAILED

抛弃 GLC 的"区块差"模型。理由：

- 时间戳更符合用户感知（"等多久能 retry"对用户更直观）
- `EntropyStatusConstants.CALLBACK_FAILED` 让"明确失败"路径不必等满 timeout 再 retry，UX 更好
- SC 已经在用，迁 GLC 改动小（block→time 单字段替换）

`entropyTimeout` 默认 `1 hours`，边界 `[60s, 24h]`，治理可调。

### D2: Pending 由基类持有 + `tokenId` / `itemCount` 通用字段

基类 `Request` 结构（3 storage slot）：

```solidity
struct Request {
    uint256 tokenId;       // slot 1: 业务 token id（NFT id 等，子类自定义语义）
    address requester;     // slot 2: 20 + 8 + 4 = 32
    uint64  requestedAt;
    uint32  itemCount;
    uint128 paidFee;       // slot 3: 16 + 1 = 17
    bool    exists;
}
mapping(uint64 sequenceNumber => Request) internal _request;
```

`itemCount` 作为"从一份 Pyth 随机数派生几个独立结果"的通用概念：GLC 填 1（单票一抽），SC 填 quantity（1-10 张）。子类业务字段（awards、DrawState 等）通过 `tokenId` 反查自身 storage，**不**强制并行 mapping。

### D3: `entropyCallback` 标记为 final + 软删除

基类 `entropyCallback` 不声明 `virtual`，子类无法覆盖。统一执行：

1. `if (!_request[seq].exists) return;`（晚到回调静默 return，用于 retry 替换后老 seq）
2. `delete _request[seq];`（先删后调 hook，防止子类内部重入读到陈旧数据）
3. 调 `_onRequestFulfilled(seq, req, randomNumber)` 由子类结算
4. emit `RequestFulfilled(seq, requester, tokenId)`

子类的所有结算逻辑都在 `_onRequestFulfilled` 内完成；`_onRequestFulfilled` 抛出会回滚整个回调，被 Pyth SDK 标 `CALLBACK_FAILED`，触发 retry 路径。

### D4: 4 个 virtual hook 让子类参与而不破坏框架

| Hook | 触发位置 | 默认 | 用途 |
|---|---|---|---|
| `_onRequestFulfilled(seq, req, rand)` | callback 内 delete 之后 | abstract（必须实现） | 业务结算 |
| `_postRequest(seq, req)` | `_requestRandomness` 内 emit 之后、refund 之前 | 空 | 子类写业务 effects（CEI-correct） |
| `_beforeRetry(oldSeq, old)` | retry 内校验通过、新 request 之前 | 空 | 业务前置校验 |
| `_postRetry(oldSeq, newSeq, updated)` | retry 内 emit 之后、refund 之前 | 空 | 子类同步业务状态（如 NFT seq 切换） |

**为什么需要 post hook**：base 在 emit 之后会调 `_refundFee` 用 `call{value: ...}("")` 把多余 `msg.value` 退给 caller。此调用让出控制权给可能是合约的 caller，构成外部调用。子类若在 base 调用**之后**才写自己的 storage（例如 SC `_pendingCount += 1`、GLC `lockPending` / `setDrawRequested`），就违反 CEI；攻击者可在 fallback 重入读到陈旧 state。`_postRequest` / `_postRetry` 给子类一个在 refund **之前**继续写 effects 的位置。

### D5: 治理用 `AccessControl.DEFAULT_ADMIN_ROLE`

基类继承 `AccessControl`，三个 setter 用 `onlyRole(DEFAULT_ADMIN_ROLE)`。

子类如使用 `Ownable`（GLC 现状），在 constructor 中 `_grantRole(DEFAULT_ADMIN_ROLE, owner_)` 即可让 owner 兼任 admin。两套 access 系统并存的成本是可接受的字节码重复，比强制所有子类换访问控制系统简单。

setter 标记 `virtual`，子类如有特殊访问控制需求可 override。

### D6: 老 fee 不退还

retry 触发后，基类**不**退还老 sequence 的 entropy fee，仅退多余的 `msg.value`。沿用 SC v3.2 review 决议（类比 L2 gas，由用户自担）。事件中携带 `oldFee` / `newFee` 供链下个例补偿决策。

### D7: provider 切换不影响 in-flight sequence

`setEntropyProvider` 改动 `entropyProvider` storage 但不取消已发出的 `_request[seq]`。在飞 sequence 仍可在原 provider 完成 callback。retry 时使用**新** provider，可能产生跨 provider 状态。这是 Pyth SDK 不支持原子切换的客观限制，本基类不试图掩盖。

## Risks

- **Pyth SDK 升级**：基类用具体常量 `EntropyStatusConstants.CALLBACK_FAILED` 与具体类型 `EntropyStructsV2.Request`。SDK 在大版本 break 时需要同步升级。
- **MockEntropy 行为差异**：测试 fixture 用 SDK 自带 `MockEntropy`。若 SDK 版本下 `register` / `revealWithCallback` 签名变化，fixture 需相应调整（task 1 / task 2 中已标注 NOTE）。
- **下游适配工作量**：SC / GLC 各自的迁移是**独立 change**，必须等本 change archive + infra 包发布新版本后才能起草，避免循环依赖。

## Open Questions

暂无。
