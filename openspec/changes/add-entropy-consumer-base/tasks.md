# Tasks

> **执行约定**：按段编号顺序执行（§1 → §2 → ... → §7）；同段内子项可并行。
> 详细 step-by-step（含完整 Solidity / JS 代码）见 `doc/entropy-consumer-base-phase1-plan.md`。

## 1. 依赖与骨架文件

- [ ] 1.1 `package.json`：新增 `dependencies."@pythnetwork/entropy-sdk-solidity": "^2.2.0"`，`npm install`
- [ ] 1.2 新建 `contracts/interfaces/IEntropyConsumerBase.sol`：声明 `Request` struct、6 个事件、9 个错误
- [ ] 1.3 新建 `contracts/base/EntropyConsumerBase.sol` 骨架：imports / 继承（`IEntropyConsumer + AccessControl + DeadLine + IEntropyConsumerBase`）/ 常量 / 状态变量 / constructor / `getEntropy` override / `_onRequestFulfilled` abstract 声明
- [ ] 1.4 新建 `contracts/test/MockEntropyConsumer.sol`：最小测试子类，constructor 内 `_grantRole(DEFAULT_ADMIN_ROLE, msg.sender)`，实现 `_onRequestFulfilled` 把 `randomNumber` 写入 mapping 供断言
- [ ] 1.5 `npx hardhat compile` 编译通过

## 2. 部署 fixture + 公共 read

- [ ] 2.1 `EntropyConsumerBase.sol`：新增 `entropyFee()` public view、`getRequest(uint64)` external view
- [ ] 2.2 新建 `test/utils/deployEntropyFixture.js`：部署 Pyth 官方 `MockEntropy` + `MockEntropyConsumer`，return `{ mockEntropy, consumer, owner, alice, bob, attacker }`
  - 注：MockEntropy `register` 签名以当前 SDK 版本为准（必要时 `cat node_modules/@pythnetwork/entropy-sdk-solidity/MockEntropy.sol` 核对）
- [ ] 2.3 新建 `test/runTest/EntropyConsumerBase.test.js`：`describe("deployment")` 4 个用例（state 默认值 / zero-address revert / `entropyFee` / `getRequest` 空值）
- [ ] 2.4 `npx hardhat test test/runTest/EntropyConsumerBase.test.js` 全绿

## 3. `_requestRandomness` + `_postRequest` hook

- [ ] 3.1 `EntropyConsumerBase.sol`：实现 `_requestRandomness(...)`，按顺序：校验 `userRandom != 0`、校验 `paid >= entropyFee()`、调 `requestV2`、写 `_request[seq]`、emit `RequestSubmitted`、调 `_postRequest(seq, _request[seq])`、`_refundFee(requester, paid - fee)`
- [ ] 3.2 `EntropyConsumerBase.sol`：新增 `function _postRequest(uint64, Request memory) internal virtual {}` 与 `function _refundFee(address, uint256) internal { ... revert ErrorRefundFailed; }`
- [ ] 3.3 `MockEntropyConsumer.sol`：新增 `lastPostRequestSeq` 状态变量、override `_postRequest` 记录 seq、新增 public wrapper `requestRandomness(...)` 把 `msg.value` 当 `paid` 传入
- [ ] 3.4 `EntropyConsumerBase.test.js` 新增 `describe("_requestRandomness")`：5 个用例（成功 / 零 random / 不足 fee / 退多余 fee / `_postRequest` 调用顺序）
- [ ] 3.5 测试全绿

## 4. `entropyCallback` final + `_onRequestFulfilled` 派发

- [ ] 4.1 `EntropyConsumerBase.sol`：实现 `entropyCallback(uint64, address, bytes32) internal override`，按顺序：读 `_request[seq]` → 若 `!exists` return → `delete _request[seq]` → 调 `_onRequestFulfilled` → emit `RequestFulfilled`
- [ ] 4.2 `EntropyConsumerBase.test.js` 新增 `describe("entropyCallback")`：3 个用例（正常派发 / 晚到回调静默 / 子类 hook revert 传播）
  - "晚到回调"用例若 MockEntropy 不允许重 reveal，则在 §5 retry 流程内补回
- [ ] 4.3 测试全绿

## 5. `retryRequest` + `_beforeRetry` + `_postRetry`

- [ ] 5.1 `EntropyConsumerBase.sol`：实现 `retryRequest(uint64, bytes32, uint256) external payable checkDeadline(deadline) returns (uint64)`，完整路径见设计文档 §6.3：校验 `exists / requester / newRandom != 0 / timeout || CALLBACK_FAILED` → 调 `_beforeRetry` → 校验 `msg.value >= fee` → `requestV2` → `delete oldSeq + write newSeq` → emit `RequestRetried` → 调 `_postRetry` → 退多余 fee
- [ ] 5.2 `EntropyConsumerBase.sol`：新增 `_beforeRetry / _postRetry` 默认空 virtual
- [ ] 5.3 `MockEntropyConsumer.sol`：新增 `revertOnBeforeRetry` 开关、`lastPostRetryOldSeq / lastPostRetryNewSeq` 状态、override 两个 hook
- [ ] 5.4 `EntropyConsumerBase.test.js` 新增 `describe("retryRequest")`：11 个用例（timeout retry / CALLBACK_FAILED retry / 未到时间也未失败 revert / 不存在 seq / 非 requester / 零 random / 不足 fee / `_beforeRetry` revert / deadline 过期 / 退多余 fee / `_postRetry` 调用与可见 newSeq）
- [ ] 5.5 测试全绿

## 6. 治理 setter

- [ ] 6.1 `EntropyConsumerBase.sol`：实现 `setEntropyProvider / setCallbackGasLimit / setEntropyTimeout` 三个 setter，全部 `virtual onlyRole(DEFAULT_ADMIN_ROLE)`，含边界检查与 emit 双参数事件
- [ ] 6.2 `EntropyConsumerBase.test.js` 新增 `describe("governance setters")`：3 个用例覆盖三个 setter 的 success / 边界 / 非 admin revert
- [ ] 6.3 `npx hardhat test test/runTest/EntropyConsumerBase.test.js` 累计 ≥ 26 用例全绿

## 7. 终验 + 文档 + Archive 准备

- [ ] 7.1 `npx hardhat clean && npx hardhat compile` 通过；contract sizer 输出 `MockEntropyConsumer` 大小（abstract 基类不出现）
- [ ] 7.2 `npx hardhat coverage --testfiles "test/runTest/EntropyConsumerBase.test.js"`：基类核心分支 ≥ 95% 行、≥ 90% 分支
- [ ] 7.3 `npx hardhat test`：全套现有 infra 测试 + 新增 EntropyConsumerBase 全绿，无回归
- [ ] 7.4 `doc/entropy-consumer-base-design.md`：在「修订记录」追加本 change archive 日期
- [ ] 7.5 `package.json`：版本号升到 `0.2.0`（minor，新增 capability）
- [ ] 7.6 在 GitHub 发布 npm tag / 直接 commit + tag，使下游 SC / GLC 可以 `npm install --save '@greatlotto/infrastructure@0.2.0'`
- [ ] 7.7 archive 本 change（`openspec archive add-entropy-consumer-base`）
- [ ] 7.8 通知 SC / GLC 仓库可以起草各自的 `delegate-entropy-to-base` change（跨仓任务）
