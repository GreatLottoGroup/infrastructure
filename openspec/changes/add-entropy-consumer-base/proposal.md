## Why

`GreatLottoCore`（GLC）与 `ScratchCard`（SC）两个合约都依赖 Pyth Entropy V2 完成异步随机数请求 + 回调结算 + 失败/超时重试。两边骨架几乎一致，但实现各自分离：

- GLC 已经把"请求 + fee 退还 + 回调派发"抽到 `contracts/base/EntropyConsumer.sol`，但 retry / 治理 setter 仍在主合约
- SC 整套流水（含 retry、治理 setter）都内联在 `contracts/ScratchCard.sol`
- 两边重试触发条件不一致（GLC 用区块差，SC 用时间戳 + CALLBACK_FAILED）

把通用机制上提到 infrastructure 共享基类，可以消除代码重复、统一行为契约（重试触发、fee 退款、治理事件签名），并为未来第三个随机数消费方提供一致接口。

详细分析与跨仓对比见 `doc/entropy-consumer-base-design.md`。

## What Changes

### 新增

- 新增 capability `entropy-consumer-base`：抽象基类 `EntropyConsumerBase` + 接口 `IEntropyConsumerBase`
- `contracts/base/EntropyConsumerBase.sol`（抽象合约）：封装 Pyth Entropy V2 的请求 / 回调 / 重试 / 治理通用流程
- `contracts/interfaces/IEntropyConsumerBase.sol`：暴露 `Request` struct、6 个事件、9 个错误
- `contracts/test/MockEntropyConsumer.sol`：最小测试子类
- `test/runTest/EntropyConsumerBase.test.js`：~26 个单元测试用例
- `package.json` 新增运行时依赖 `@pythnetwork/entropy-sdk-solidity@^2.2.0`

### 接口要点

- 子类实现 `_onRequestFulfilled(uint64 seq, Request memory req, bytes32 randomNumber)` 处理业务结算
- 子类可选 override `_postRequest(seq, req)` / `_beforeRetry(oldSeq, old)` / `_postRetry(oldSeq, newSeq, updated)` 三个钩子
- 公共入口 `retryRequest(uint64 oldSeq, bytes32 newRandom, uint256 deadline) external payable`，超时 OR `CALLBACK_FAILED` 任一即可触发
- 治理 setter `setEntropyProvider / setCallbackGasLimit / setEntropyTimeout`，受 `DEFAULT_ADMIN_ROLE` 守卫
- 基类自动退还多余 `msg.value`（CEI：state 写完再退）

### 非目标

- 不抽象任何业务结算逻辑（DrawAlgo / 奖池 / 分润 / payout 兜底属于业务子类）
- 不引入 treasury 垫付池 / fee 自动补贴
- 不做 in-flight sequence 取消 / 撤回（设计上 retry 是唯一推进手段）
- 不改 SC / GLC 主合约（它们的迁移由各自仓库的独立 change 处理）

## Capabilities

### New Capabilities

- `entropy-consumer-base`：抽象基类提供 Pyth Entropy V2 异步请求 / 回调 / 重试 / 治理的统一契约

### Modified Capabilities

（无）

## Impact

- **依赖**：无前置 change
- **下游 change**（必须等本 change archive 后才能起草）：
  - `ScratchCard/openspec/changes/delegate-entropy-to-base`：SC 主合约切换继承 `EntropyConsumerBase`
  - `GreatLottoCore/openspec/changes/delegate-entropy-to-base`：GLC 主合约切换继承 `EntropyConsumerBase`，删除本地 `contracts/base/EntropyConsumer.sol`
- **infra 包语义版本**：minor 升（新增 capability，无破坏）；建议发 `0.2.0`
- **Solidity / OZ 版本**：与 infra 现状一致（0.8.35 / Cancun / viaIR / OZ 5.6.1）
- **Pyth SDK 版本**：新增 `@pythnetwork/entropy-sdk-solidity ^2.2.0`，与 SC 当前使用版本对齐
- **合约大小**：基类是 abstract，本身不占独立部署体积；继承的子类会增加 ~3-4 KiB，需在 SC / GLC 仓库的迁移 change 中验证 EIP-170 上限
- **测试**：本 change 在 infra 仓库新增 ~26 个用例，独立运行
