# entropy-consumer-base

## ADDED Requirements

### Requirement: 暴露 Pyth Entropy 配置只读视图

`EntropyConsumerBase` SHALL 暴露 `entropy()`（IEntropyV2 immutable）、`entropyProvider()`（address，可治理修改）、`callbackGasLimit()`（uint32）、`entropyTimeout()`（uint64）、`entropyFee()`（计算当前 fee）与 `getRequest(uint64) returns (Request)` 公共只读接口。

#### Scenario: 部署时写入 immutable / 默认值

- **GIVEN** 部署参数 `(entropyAddress, entropyProvider)` 均非零地址
- **WHEN** 子类合约部署
- **THEN** `entropy()` MUST 返回构造器传入的 `entropyAddress`
- **AND** `entropyProvider()` MUST 返回构造器传入的 provider 地址
- **AND** `callbackGasLimit()` MUST 返回 `500_000`
- **AND** `entropyTimeout()` MUST 返回 `3600`（1 hour）

#### Scenario: 零地址部署被拒绝

- **WHEN** 部署时 `entropyAddress == address(0)` 或 `entropyProvider == address(0)`
- **THEN** MUST revert with `ErrorZeroAddress`（inherited from `IErrorsBase` via `IEntropyConsumerBase is IErrorsBase`，避免子类双继承时的 selector 冲突）

#### Scenario: entropyFee 计算

- **WHEN** 调用 `entropyFee()`
- **THEN** MUST 返回 `entropy.getFeeV2(entropyProvider, callbackGasLimit)`

#### Scenario: getRequest 返回未存在请求时为零值结构

- **GIVEN** `_request[seq].exists == false`
- **WHEN** 调用 `getRequest(seq)`
- **THEN** MUST 返回 `Request` 结构，其中 `exists == false`、其他字段为类型零值

### Requirement: `_requestRandomness` 内部入口

子类 SHALL 通过 `_requestRandomness(uint256 tokenId, address requester, uint32 itemCount, bytes32 userRandomNumber, uint256 paid) returns (uint64 sequenceNumber, uint128 paidFee)` 发起 entropy 请求。基类内部完成校验、写 `_request`、emit、调 `_postRequest` hook、退多余 fee。

#### Scenario: 成功提交请求

- **GIVEN** `userRandomNumber != bytes32(0)` 且 `paid >= entropyFee()`
- **WHEN** 子类调用 `_requestRandomness(tokenId, requester, itemCount, userRandomNumber, paid)`
- **THEN** MUST 调用 `entropy.requestV2{value: fee}(entropyProvider, userRandomNumber, callbackGasLimit)` 取得 `sequenceNumber`
- **AND** MUST 写入 `_request[sequenceNumber] = {tokenId, requester, requestedAt: block.timestamp, itemCount, paidFee: uint128(fee), exists: true}`
- **AND** MUST emit `RequestSubmitted(sequenceNumber, requester, tokenId, itemCount, paidFee)`
- **AND** MUST 在 `_refundFee` 之前调用 `_postRequest(sequenceNumber, _request[sequenceNumber])` hook
- **AND** 当 `paid > fee` 时 MUST 通过 `_refundFee` 退还 `paid - fee` 给 `requester`

#### Scenario: 零 userRandomNumber 拒绝

- **WHEN** `_requestRandomness` 被调用且 `userRandomNumber == bytes32(0)`
- **THEN** MUST revert with `ErrorInvalidUserRandom`

#### Scenario: paid 不足拒绝

- **WHEN** `_requestRandomness` 被调用且 `paid < entropyFee()`
- **THEN** MUST revert with `ErrorInsufficientEntropyFee(needed, paid)`

#### Scenario: refund 失败拒绝整笔交易

- **GIVEN** `requester` 是无 `receive` / `fallback` 的合约且 `paid > fee`
- **WHEN** 基类执行 `_refundFee(requester, excess)`
- **THEN** `call` 失败，MUST revert with `ErrorRefundFailed`

### Requirement: 回调派发与软删除

`entropyCallback(uint64, address, bytes32)` SHALL 被基类标记为 final（不声明 virtual），子类不可覆盖。基类 SHALL 在调用子类结算钩子前完成 `exists` 检查与 `delete`。

#### Scenario: 正常回调

- **GIVEN** `_request[seq].exists == true`
- **WHEN** Pyth Entropy 触发 `_entropyCallback(seq, provider, randomNumber)`
- **THEN** MUST `delete _request[seq]`
- **AND** MUST 调用 `_onRequestFulfilled(seq, req, randomNumber)` 由子类结算
- **AND** MUST emit `RequestFulfilled(seq, req.requester, req.tokenId)`

#### Scenario: 晚到回调静默 return

- **GIVEN** `_request[seq].exists == false`（已被 retry 替换 / 不存在的 seq）
- **WHEN** Pyth Entropy 触发 `_entropyCallback(seq, provider, randomNumber)`
- **THEN** MUST 静默 `return`，不 revert，不调用 `_onRequestFulfilled`，不 emit `RequestFulfilled`

#### Scenario: 子类钩子 revert 传播

- **GIVEN** `_request[seq].exists == true` 且子类 `_onRequestFulfilled` 主动 revert
- **WHEN** Pyth Entropy 触发回调
- **THEN** 整个回调 transaction MUST 回滚（被 Pyth SDK 标记为 `CALLBACK_FAILED`，触发 retry 路径）

### Requirement: 公开 retry 入口

基类 SHALL 提供 `retryRequest(uint64 oldSeq, bytes32 newUserRandomNumber, uint256 deadline) external payable returns (uint64 newSeq)`。仅当 `block.timestamp >= old.requestedAt + entropyTimeout` 或 `entropy.getRequestV2(provider, oldSeq).callbackStatus == EntropyStatusConstants.CALLBACK_FAILED` 任一成立时允许触发。仅 `_request[oldSeq].requester` 可调用。

#### Scenario: 超时后重试

- **GIVEN** `_request[oldSeq].exists == true` 且 `block.timestamp >= old.requestedAt + entropyTimeout`
- **WHEN** `old.requester` 调用 `retryRequest(oldSeq, newUserRandomNumber, deadline)` 且 `msg.value >= entropyFee()` 且 `newUserRandomNumber != bytes32(0)` 且 `deadline >= block.timestamp`
- **THEN** MUST 调用 `_beforeRetry(oldSeq, old)` 让子类做业务前置（默认空）
- **AND** MUST 调 `entropy.requestV2{value: fee}(...)` 取得 `newSeq`
- **AND** MUST `delete _request[oldSeq]` 并写入 `_request[newSeq] = {tokenId: old.tokenId, requester: old.requester, requestedAt: block.timestamp, itemCount: old.itemCount, paidFee: uint128(fee), exists: true}`
- **AND** MUST emit `RequestRetried(oldSeq, newSeq, old.requester, old.paidFee, uint128(fee))`
- **AND** MUST 在 `_refundFee` 之前调用 `_postRetry(oldSeq, newSeq, _request[newSeq])` hook
- **AND** 当 `msg.value > fee` 时 MUST 退还 `msg.value - fee` 给 `msg.sender`

#### Scenario: CALLBACK_FAILED 后立即重试

- **GIVEN** `_request[oldSeq].exists == true`
- **AND** `block.timestamp < old.requestedAt + entropyTimeout`
- **AND** `entropy.getRequestV2(entropyProvider, oldSeq).callbackStatus == EntropyStatusConstants.CALLBACK_FAILED`
- **WHEN** `old.requester` 调用 `retryRequest(...)`
- **THEN** MUST 走与超时重试相同路径

#### Scenario: 既未超时也未失败时拒绝

- **GIVEN** `_request[oldSeq].exists == true`
- **AND** `block.timestamp < old.requestedAt + entropyTimeout`
- **AND** `entropy.getRequestV2(...).callbackStatus != EntropyStatusConstants.CALLBACK_FAILED`
- **WHEN** 调用 `retryRequest(...)`
- **THEN** MUST revert with `ErrorRetryNotAllowed`

#### Scenario: 不存在的 sequence

- **GIVEN** `_request[oldSeq].exists == false`
- **WHEN** 调用 `retryRequest(oldSeq, ...)`
- **THEN** MUST revert with `ErrorRequestNotFound`

#### Scenario: 非 requester 拒绝

- **GIVEN** `_request[oldSeq].requester != msg.sender`
- **WHEN** 调用 `retryRequest(oldSeq, ...)`
- **THEN** MUST revert with `ErrorNotRequester`

#### Scenario: 零 userRandomNumber 拒绝

- **WHEN** 调用 `retryRequest(oldSeq, bytes32(0), deadline)`
- **THEN** MUST revert with `ErrorInvalidUserRandom`

#### Scenario: msg.value < fee 拒绝

- **WHEN** 调用 `retryRequest(oldSeq, newRandom, deadline)` 且 `msg.value < entropyFee()`
- **THEN** MUST revert with `ErrorInsufficientEntropyFee`

#### Scenario: deadline 过期拒绝

- **WHEN** 调用 `retryRequest(...)` 且 `block.timestamp > deadline`
- **THEN** MUST revert with `DeadLineExpiredTransaction`（来自 `DeadLine.checkDeadline`）

#### Scenario: `_beforeRetry` 抛出回滚整个 retry

- **GIVEN** 子类 override `_beforeRetry` 并 revert
- **WHEN** `retryRequest` 进入 `_beforeRetry` 调用点
- **THEN** 整笔交易 MUST 回滚，`_request[oldSeq]` 仍保持原状

### Requirement: 治理 setter

基类 SHALL 提供 `setEntropyProvider(address)` / `setCallbackGasLimit(uint32)` / `setEntropyTimeout(uint64)` 三个治理入口，受 `onlyRole(DEFAULT_ADMIN_ROLE)` 守卫，并发出对应事件。三个 setter 都标记 `virtual`，子类可 override 替换访问控制。

#### Scenario: setEntropyProvider 成功

- **GIVEN** caller 持有 `DEFAULT_ADMIN_ROLE`
- **WHEN** 调用 `setEntropyProvider(newProvider)` 且 `newProvider != address(0)`
- **THEN** MUST 更新 `entropyProvider` 为 `newProvider`
- **AND** MUST emit `EntropyProviderChanged(oldProvider, newProvider)`

#### Scenario: setEntropyProvider 零地址拒绝

- **WHEN** 调用 `setEntropyProvider(address(0))`
- **THEN** MUST revert with `ErrorZeroAddress`

#### Scenario: setCallbackGasLimit 边界

- **GIVEN** caller 持有 `DEFAULT_ADMIN_ROLE`
- **WHEN** 调用 `setCallbackGasLimit(newLimit)` 且 `newLimit ∈ [100_000, 2_000_000]`
- **THEN** MUST 更新 `callbackGasLimit` 并 emit `CallbackGasLimitChanged(oldLimit, newLimit)`

#### Scenario: setCallbackGasLimit 越界

- **WHEN** 调用 `setCallbackGasLimit(newLimit)` 且 `newLimit < 100_000` 或 `newLimit > 2_000_000`
- **THEN** MUST revert with `ErrorInvalidCallbackGasLimit`

#### Scenario: setEntropyTimeout 边界

- **GIVEN** caller 持有 `DEFAULT_ADMIN_ROLE`
- **WHEN** 调用 `setEntropyTimeout(newTimeout)` 且 `newTimeout ∈ [60, 86400]`
- **THEN** MUST 更新 `entropyTimeout` 并 emit `EntropyTimeoutChanged(oldTimeout, newTimeout)`

#### Scenario: setEntropyTimeout 越界

- **WHEN** 调用 `setEntropyTimeout(newTimeout)` 且 `newTimeout < 60` 或 `newTimeout > 86400`
- **THEN** MUST revert with `ErrorInvalidEntropyTimeout`

#### Scenario: 非 admin 调用 setter

- **GIVEN** caller 不持有 `DEFAULT_ADMIN_ROLE`
- **WHEN** 调用任意 setter
- **THEN** MUST revert with `AccessControlUnauthorizedAccount`

#### Scenario: provider 切换不影响 in-flight sequence

- **GIVEN** `_request[seq].exists == true` 且当 entropyProvider 已更新为 newProvider
- **WHEN** 原 provider 触发 `_entropyCallback(seq, oldProvider, randomNumber)`
- **THEN** MUST 正常派发到 `_onRequestFulfilled`（基类不依据 provider 重定向 callback）

### Requirement: 子类钩子契约

基类 SHALL 暴露 4 个 virtual 钩子供子类实现：

- `_onRequestFulfilled(uint64 seq, Request memory req, bytes32 randomNumber)` —— **abstract**，子类必须实现业务结算
- `_postRequest(uint64 seq, Request memory req)` —— 默认空；子类在 base 退余款（让出控制权）**前**继续写业务 storage / emit 业务事件
- `_beforeRetry(uint64 oldSeq, Request memory old)` —— 默认空；子类在 base 发新请求**前**做业务校验
- `_postRetry(uint64 oldSeq, uint64 newSeq, Request memory updated)` —— 默认空；子类在 base 退余款**前**同步业务状态

#### Scenario: `_postRequest` 在 emit 之后、refund 之前调用

- **GIVEN** 子类 override `_postRequest` 记录调用顺序
- **WHEN** `_requestRandomness` 完整执行
- **THEN** MUST 在 `RequestSubmitted` emit 之后调用 `_postRequest`
- **AND** MUST 在 `_postRequest` 返回之后才调用 `_refundFee`

#### Scenario: `_postRetry` 在 emit 之后、refund 之前调用

- **GIVEN** 子类 override `_postRetry` 记录调用顺序
- **WHEN** `retryRequest` 完整执行
- **THEN** MUST 在 `RequestRetried` emit 之后调用 `_postRetry`
- **AND** MUST 在 `_postRetry` 返回之后才调用 `_refundFee`

#### Scenario: `_postRequest` / `_postRetry` 抛出回滚整笔交易

- **GIVEN** 子类 override hook 并 revert
- **WHEN** 基类调用至该 hook
- **THEN** 整笔交易 MUST 回滚，`_request` 写入与 emit 都被撤销
