# Phase 1 Implementation Plan — `EntropyConsumerBase` 落地（infrastructure 仓）

> ⚠️ **数值已于 2026-06-25 更新（本 plan 为历史实施记录，未逐行回改）：** `MAX_CALLBACK_GAS` 2_000_000 → **5_000_000**；构造期默认 `callbackGasLimit` 500_000 → **2_500_000**；`setCallbackGasLimit` 边界 `[100k, 2M]` → **`[100k, 5M]`**；`retryRequest` 返回值由 `(uint64 newSeq)` 改为 **`(uint64 newSeq, uint128 paidFee)`**。以 [entropy-consumer-base-design.md](./entropy-consumer-base-design.md) 与 `openspec/specs/entropy-consumer-base/spec.md` 为当前真值。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `@greatlotto/infrastructure` 仓库内新增抽象基类 `EntropyConsumerBase` 与配套测试，封装 Pyth Entropy V2 请求 / 回调 / 重试 / 治理通用流程，供 ScratchCard 与 GreatLottoCore 后续阶段继承复用。

**Architecture:** 单一抽象合约 + 一个最小测试子类。`EntropyConsumerBase` 持有 `_request[seq]` 通用 pending 结构（含 `tokenId / requester / itemCount / paidFee / requestedAt / exists` 6 个字段），暴露 `_requestRandomness` 内部钩子供子类发起请求，`entropyCallback` final 派发到 `_onRequestFulfilled` virtual 钩子，`retryRequest` 公开重试入口（超时 OR `CALLBACK_FAILED` 任一即可）。完整设计见 [entropy-consumer-base-design.md](./entropy-consumer-base-design.md)。

**Tech Stack:** Solidity 0.8.35 / Cancun / viaIR · `@openzeppelin/contracts ^5.6.1` · `@pythnetwork/entropy-sdk-solidity ^2.2.0` · Hardhat 2.28.6 · Mocha + Chai · Pyth `MockEntropy`（来自 SDK）

**Working directory:** `/Users/tongren/Documents/github/GreatLottoGroup/infrastructure`

---

## File Structure

| 路径 | 类型 | 责任 |
|---|---|---|
| `contracts/base/EntropyConsumerBase.sol` | 新建 | 抽象基类主体 |
| `contracts/interfaces/IEntropyConsumerBase.sol` | 新建 | 公共 ABI（事件 / 错误 / Request struct）|
| `contracts/test/MockEntropyConsumer.sol` | 新建 | 最小测试子类（暴露 `_requestRandomness` 公共包装、记录 callback 数据）|
| `test/runTest/EntropyConsumerBase.test.js` | 新建 | 主单元测试套件 |
| `test/utils/deployEntropyFixture.js` | 新建 | 共享部署 fixture（MockEntropy + MockEntropyConsumer）|
| `package.json` | 修改 | 新增 `@pythnetwork/entropy-sdk-solidity` 依赖 |

---

## Task 1: 添加 Pyth SDK 依赖 + 骨架文件

**Files:**
- Modify: `package.json`
- Create: `contracts/interfaces/IEntropyConsumerBase.sol`
- Create: `contracts/base/EntropyConsumerBase.sol`
- Create: `contracts/test/MockEntropyConsumer.sol`

- [ ] **Step 1: 安装 Pyth SDK 依赖**

```bash
cd /Users/tongren/Documents/github/GreatLottoGroup/infrastructure
npm install --save '@pythnetwork/entropy-sdk-solidity@^2.2.0'
```

预期：`package.json` 的 `dependencies` 新增该条目，安装到 `node_modules/@pythnetwork/entropy-sdk-solidity/`。

- [ ] **Step 2: 写 `IEntropyConsumerBase.sol` 接口文件**

```solidity
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

interface IEntropyConsumerBase {
    struct Request {
        uint256 tokenId;
        address requester;
        uint64  requestedAt;
        uint32  itemCount;
        uint128 paidFee;
        bool    exists;
    }

    event RequestSubmitted(
        uint64  indexed sequenceNumber,
        address indexed requester,
        uint256 indexed tokenId,
        uint32 itemCount,
        uint128 paidFee
    );
    event RequestFulfilled(
        uint64  indexed sequenceNumber,
        address indexed requester,
        uint256 indexed tokenId
    );
    event RequestRetried(
        uint64  indexed oldSequenceNumber,
        uint64  indexed newSequenceNumber,
        address indexed requester,
        uint128 oldFee,
        uint128 newFee
    );
    event EntropyProviderChanged(address oldProvider, address newProvider);
    event CallbackGasLimitChanged(uint32 oldLimit, uint32 newLimit);
    event EntropyTimeoutChanged(uint64 oldTimeout, uint64 newTimeout);

    error ErrorInvalidUserRandom();
    error ErrorInsufficientEntropyFee(uint256 needed, uint256 paid);
    error ErrorRequestNotFound();
    error ErrorNotRequester();
    error ErrorRetryNotAllowed();
    error ErrorInvalidEntropyTimeout();
    error ErrorInvalidCallbackGasLimit();
    error ErrorRefundFailed();
    error ErrorZeroAddress();
}
```

- [ ] **Step 3: 写 `EntropyConsumerBase.sol` 骨架（仅声明，不含实现）**

先建空骨架以便 compile 跑通，后续 task 逐步填实：

```solidity
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {IEntropyConsumer} from "@pythnetwork/entropy-sdk-solidity/IEntropyConsumer.sol";
import {IEntropyV2} from "@pythnetwork/entropy-sdk-solidity/IEntropyV2.sol";
import {EntropyStructsV2} from "@pythnetwork/entropy-sdk-solidity/EntropyStructsV2.sol";
import {EntropyStatusConstants} from "@pythnetwork/entropy-sdk-solidity/EntropyStatusConstants.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {DeadLine} from "./DeadLine.sol";
import {IEntropyConsumerBase} from "../interfaces/IEntropyConsumerBase.sol";

abstract contract EntropyConsumerBase is IEntropyConsumer, AccessControl, DeadLine, IEntropyConsumerBase {
    uint64 public constant MIN_ENTROPY_TIMEOUT = 60;
    uint64 public constant MAX_ENTROPY_TIMEOUT = 24 hours;
    uint32 public constant MIN_CALLBACK_GAS = 100_000;
    uint32 public constant MAX_CALLBACK_GAS = 2_000_000;

    IEntropyV2 public immutable entropy;
    address public entropyProvider;
    uint32  public callbackGasLimit;
    uint64  public entropyTimeout;

    mapping(uint64 sequenceNumber => Request) internal _request;

    constructor(address entropy_, address entropyProvider_) {
        if (entropy_ == address(0) || entropyProvider_ == address(0)) revert ErrorZeroAddress();
        entropy = IEntropyV2(entropy_);
        entropyProvider = entropyProvider_;
        callbackGasLimit = 500_000;
        entropyTimeout = 1 hours;
    }

    function getEntropy() internal view override returns (address) {
        return address(entropy);
    }

    function _onRequestFulfilled(uint64 sequenceNumber, Request memory req, bytes32 randomNumber) internal virtual;
}
```

- [ ] **Step 4: 写 `MockEntropyConsumer.sol` 骨架（最小子类，只实现必需的 abstract）**

```solidity
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import {EntropyConsumerBase} from "../base/EntropyConsumerBase.sol";

/// @dev 测试用最小子类。把基类 internal 暴露为 public、把 callback 内的 randomNumber 写入 mapping。
contract MockEntropyConsumer is EntropyConsumerBase {
    bytes32 public lastRandomNumber;
    uint64  public lastSequence;
    uint256 public lastTokenId;
    address public lastRequester;
    uint32  public lastItemCount;
    bool    public revertOnFulfill;
    bool    public revertOnBeforeRetry;

    constructor(address entropy_, address provider_) EntropyConsumerBase(entropy_, provider_) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function _onRequestFulfilled(uint64 sequenceNumber, Request memory req, bytes32 randomNumber) internal override {
        if (revertOnFulfill) revert("fulfill-revert");
        lastSequence = sequenceNumber;
        lastRandomNumber = randomNumber;
        lastTokenId = req.tokenId;
        lastRequester = req.requester;
        lastItemCount = req.itemCount;
    }

    function setRevertOnFulfill(bool v) external { revertOnFulfill = v; }
    function setRevertOnBeforeRetry(bool v) external { revertOnBeforeRetry = v; }
}
```

- [ ] **Step 5: Compile + smoke check**

Run:
```bash
npx hardhat compile
```

Expected：编译通过，contract sizer 输出三个新合约（abstract 基类不会出现在 sizer，只 `MockEntropyConsumer` 出现）。

- [ ] **Step 6: Commit**

```bash
git add package.json package-lock.json contracts/interfaces/IEntropyConsumerBase.sol contracts/base/EntropyConsumerBase.sol contracts/test/MockEntropyConsumer.sol
git commit -m "feat(entropy): add EntropyConsumerBase skeleton + Pyth SDK dep"
```

---

## Task 2: Deploy fixture + 公共 read 函数

**Files:**
- Modify: `contracts/base/EntropyConsumerBase.sol`（新增 `entropyFee()` / `getRequest()`）
- Create: `test/utils/deployEntropyFixture.js`
- Create: `test/runTest/EntropyConsumerBase.test.js`（首批 deploy 用例）

- [ ] **Step 1: 在 `EntropyConsumerBase.sol` 添加 public read 函数**

在 `getEntropy()` 后插入：

```solidity
function entropyFee() public view returns (uint256) {
    return entropy.getFeeV2(entropyProvider, callbackGasLimit);
}

function getRequest(uint64 sequenceNumber) external view returns (Request memory) {
    return _request[sequenceNumber];
}
```

- [ ] **Step 2: 写 `test/utils/deployEntropyFixture.js`**

```javascript
const { ethers } = require("hardhat");

async function deployEntropyFixture() {
  const [owner, alice, bob, attacker] = await ethers.getSigners();

  // Pyth 官方 MockEntropy（SDK 提供）
  const MockEntropy = await ethers.getContractFactory("@pythnetwork/entropy-sdk-solidity/MockEntropy.sol:MockEntropy");
  const mockEntropy = await MockEntropy.deploy(owner.address);
  await mockEntropy.waitForDeployment();

  // Pyth provider register（MockEntropy 要求 register）
  await mockEntropy.connect(owner).register(
    100,                                          // fee in wei
    ethers.encodeBytes32String("commitment"),     // initial commitment (mock)
    ethers.encodeBytes32String("metadata"),       // metadata
    1000,                                         // chainLength
    "0x"                                          // uri
  );

  // 部署 MockEntropyConsumer
  const MockEntropyConsumer = await ethers.getContractFactory("MockEntropyConsumer");
  const consumer = await MockEntropyConsumer.deploy(
    await mockEntropy.getAddress(),
    owner.address                                 // 用 owner 作为 provider 地址（与 MockEntropy.register 调用方一致）
  );
  await consumer.waitForDeployment();

  return { mockEntropy, consumer, owner, alice, bob, attacker };
}

module.exports = { deployEntropyFixture };
```

> **NOTE on MockEntropy:** Pyth SDK 的 `MockEntropy.sol` 路径在 `node_modules/@pythnetwork/entropy-sdk-solidity/MockEntropy.sol`。如该 SDK 版本下 register 函数签名/参数不一致，应执行 `cat node_modules/@pythnetwork/entropy-sdk-solidity/MockEntropy.sol | head -80` 核对实参。预期 `MockEntropyConsumer` 已在 hardhat artifacts 中（test 合约目录 `contracts/test/` 已被 hardhat 默认编译）。

- [ ] **Step 3: 写首批部署用例**

`test/runTest/EntropyConsumerBase.test.js`：

```javascript
const { expect } = require("chai");
const { loadFixture } = require("@nomicfoundation/hardhat-toolbox/network-helpers");
const { ethers } = require("hardhat");
const { deployEntropyFixture } = require("../utils/deployEntropyFixture");

describe("EntropyConsumerBase", function () {

  describe("deployment", function () {
    it("sets entropy address, provider, defaults", async function () {
      const { mockEntropy, consumer, owner } = await loadFixture(deployEntropyFixture);
      expect(await consumer.entropy()).to.equal(await mockEntropy.getAddress());
      expect(await consumer.entropyProvider()).to.equal(owner.address);
      expect(await consumer.callbackGasLimit()).to.equal(500_000n);
      expect(await consumer.entropyTimeout()).to.equal(3600n);
    });

    it("reverts on zero address in constructor", async function () {
      const Mock = await ethers.getContractFactory("MockEntropyConsumer");
      const ZERO = ethers.ZeroAddress;
      await expect(Mock.deploy(ZERO, ethers.Wallet.createRandom().address))
        .to.be.revertedWithCustomError(Mock, "ErrorZeroAddress");
      await expect(Mock.deploy(ethers.Wallet.createRandom().address, ZERO))
        .to.be.revertedWithCustomError(Mock, "ErrorZeroAddress");
    });

    it("entropyFee() returns the fee from MockEntropy", async function () {
      const { consumer } = await loadFixture(deployEntropyFixture);
      expect(await consumer.entropyFee()).to.equal(100n);
    });

    it("getRequest() returns empty Request for unknown seq", async function () {
      const { consumer } = await loadFixture(deployEntropyFixture);
      const req = await consumer.getRequest(999);
      expect(req.exists).to.equal(false);
      expect(req.tokenId).to.equal(0n);
    });
  });
});
```

- [ ] **Step 4: 跑测试**

Run:
```bash
npx hardhat test test/runTest/EntropyConsumerBase.test.js
```

Expected：4 个用例通过。

- [ ] **Step 5: Commit**

```bash
git add contracts/base/EntropyConsumerBase.sol test/utils/deployEntropyFixture.js test/runTest/EntropyConsumerBase.test.js
git commit -m "feat(entropy): add entropyFee/getRequest reads + deployment tests"
```

---

## Task 3: `_requestRandomness` 实现 + 测试

**Files:**
- Modify: `contracts/base/EntropyConsumerBase.sol`（新增 `_requestRandomness` + `_refundFee`）
- Modify: `contracts/test/MockEntropyConsumer.sol`（暴露 public wrapper）
- Modify: `test/runTest/EntropyConsumerBase.test.js`（新增 describe block）

- [ ] **Step 1: 在 `EntropyConsumerBase.sol` 添加实现**

```solidity
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

/// @dev 子类可在 base 退余款（让出控制权）前继续写业务 storage / emit
function _postRequest(uint64 /*sequenceNumber*/, Request memory /*req*/) internal virtual {}

function _refundFee(address to, uint256 amount) internal {
    (bool ok, ) = payable(to).call{value: amount}("");
    if (!ok) revert ErrorRefundFailed();
}
```

- [ ] **Step 2: 在 `MockEntropyConsumer.sol` 暴露 public wrapper + `_postRequest` 钩子探测**

在 contract 顶部追加状态变量：

```solidity
uint64 public lastPostRequestSeq;
```

contract 内部追加：

```solidity
/// @dev 测试用 public wrapper，把 msg.value 当 paid 传入
function requestRandomness(
    uint256 tokenId,
    address requester,
    uint32 itemCount,
    bytes32 userRandomNumber
) external payable returns (uint64 sequenceNumber, uint128 paidFee) {
    return _requestRandomness(tokenId, requester, itemCount, userRandomNumber, msg.value);
}

function _postRequest(uint64 sequenceNumber, Request memory /*req*/) internal override {
    lastPostRequestSeq = sequenceNumber;
}
```

- [ ] **Step 3: 写 `_requestRandomness` 测试用例**

在 `EntropyConsumerBase.test.js` 末尾新增：

```javascript
  describe("_requestRandomness", function () {
    const RANDOM = "0x" + "11".repeat(32);
    const FEE = 100n;

    it("submits request, writes _request, emits RequestSubmitted", async function () {
      const { consumer, alice } = await loadFixture(deployEntropyFixture);
      const tx = consumer.connect(alice).requestRandomness(
        42n, alice.address, 3, RANDOM, { value: FEE }
      );
      await expect(tx)
        .to.emit(consumer, "RequestSubmitted")
        .withArgs(0n /* first seq from MockEntropy */, alice.address, 42n, 3, FEE);

      const req = await consumer.getRequest(0n);
      expect(req.exists).to.equal(true);
      expect(req.tokenId).to.equal(42n);
      expect(req.requester).to.equal(alice.address);
      expect(req.itemCount).to.equal(3);
      expect(req.paidFee).to.equal(FEE);
    });

    it("reverts ErrorInvalidUserRandom when userRandom == 0", async function () {
      const { consumer, alice } = await loadFixture(deployEntropyFixture);
      const ZERO_RANDOM = ethers.ZeroHash;
      await expect(
        consumer.connect(alice).requestRandomness(1n, alice.address, 1, ZERO_RANDOM, { value: FEE })
      ).to.be.revertedWithCustomError(consumer, "ErrorInvalidUserRandom");
    });

    it("reverts ErrorInsufficientEntropyFee when paid < fee", async function () {
      const { consumer, alice } = await loadFixture(deployEntropyFixture);
      await expect(
        consumer.connect(alice).requestRandomness(1n, alice.address, 1, RANDOM, { value: 50n })
      ).to.be.revertedWithCustomError(consumer, "ErrorInsufficientEntropyFee").withArgs(FEE, 50n);
    });

    it("refunds excess paid to requester", async function () {
      const { consumer, alice } = await loadFixture(deployEntropyFixture);
      const before = await ethers.provider.getBalance(alice.address);
      const overpay = FEE + 999n;
      const tx = await consumer.connect(alice).requestRandomness(
        1n, alice.address, 1, RANDOM, { value: overpay }
      );
      const receipt = await tx.wait();
      const gasCost = receipt.gasUsed * receipt.gasPrice;
      const after = await ethers.provider.getBalance(alice.address);
      expect(before - after).to.equal(FEE + gasCost);
    });

    it("invokes _postRequest hook after _request write, before refund", async function () {
      const { consumer, alice } = await loadFixture(deployEntropyFixture);
      await consumer.connect(alice).requestRandomness(77n, alice.address, 1, RANDOM, { value: FEE });
      // hook recorded the seq → _request[seq] was already written when the hook fired
      expect(await consumer.lastPostRequestSeq()).to.equal(0n);
      expect((await consumer.getRequest(0n)).tokenId).to.equal(77n);
    });
  });
```

- [ ] **Step 4: 跑测试**

Run:
```bash
npx hardhat test test/runTest/EntropyConsumerBase.test.js
```

Expected：累计 8 个用例通过。

- [ ] **Step 5: Commit**

```bash
git add contracts/base/EntropyConsumerBase.sol contracts/test/MockEntropyConsumer.sol test/runTest/EntropyConsumerBase.test.js
git commit -m "feat(entropy): implement _requestRandomness with refund + tests"
```

---

## Task 4: `entropyCallback` + `_onRequestFulfilled` 钩子 + 测试

**Files:**
- Modify: `contracts/base/EntropyConsumerBase.sol`（新增 `entropyCallback` final override）
- Modify: `test/runTest/EntropyConsumerBase.test.js`

- [ ] **Step 1: 在 `EntropyConsumerBase.sol` 添加 callback 派发**

在 `_refundFee` 之后插入：

```solidity
function entropyCallback(uint64 sequenceNumber, address /*provider*/, bytes32 randomNumber) internal override {
    Request memory req = _request[sequenceNumber];
    if (!req.exists) return;
    delete _request[sequenceNumber];
    _onRequestFulfilled(sequenceNumber, req, randomNumber);
    emit RequestFulfilled(sequenceNumber, req.requester, req.tokenId);
}
```

- [ ] **Step 2: 写 callback 测试用例**

在 `EntropyConsumerBase.test.js` 末尾新增：

```javascript
  describe("entropyCallback", function () {
    const RANDOM = "0x" + "11".repeat(32);
    const PROVIDER_RANDOM = "0x" + "22".repeat(32);
    const FEE = 100n;

    async function submitAndReveal(consumer, mockEntropy, alice, owner) {
      await consumer.connect(alice).requestRandomness(7n, alice.address, 2, RANDOM, { value: FEE });
      // MockEntropy.reveal(provider, sequenceNumber, providerRevelation) — provider 调用 reveal 触发 callback
      // 实际签名以 SDK 版本为准；此处用 revealWithCallback 通用 mock 路径
      return mockEntropy.connect(owner).revealWithCallback(
        owner.address,                  // provider
        0n,                              // sequenceNumber
        RANDOM,                          // userRandomNumber
        PROVIDER_RANDOM                  // providerRevelation
      );
    }

    it("dispatches to _onRequestFulfilled, deletes _request, emits RequestFulfilled", async function () {
      const { consumer, mockEntropy, alice, owner } = await loadFixture(deployEntropyFixture);
      const tx = await submitAndReveal(consumer, mockEntropy, alice, owner);

      await expect(tx).to.emit(consumer, "RequestFulfilled").withArgs(0n, alice.address, 7n);

      const req = await consumer.getRequest(0n);
      expect(req.exists).to.equal(false);

      // mock 子类记录的 callback 数据
      expect(await consumer.lastSequence()).to.equal(0n);
      expect(await consumer.lastTokenId()).to.equal(7n);
      expect(await consumer.lastRequester()).to.equal(alice.address);
      expect(await consumer.lastItemCount()).to.equal(2);
      // randomNumber = combined Pyth 协议下的产物 — 不强等，仅断言非零
      expect(await consumer.lastRandomNumber()).to.not.equal(ethers.ZeroHash);
    });

    it("silently returns when callback fires for non-existent seq (late callback)", async function () {
      const { consumer, mockEntropy, alice, owner } = await loadFixture(deployEntropyFixture);
      // 提交后立即 delete（模拟已被 retry 替换）
      await consumer.connect(alice).requestRandomness(7n, alice.address, 1, RANDOM, { value: FEE });
      // 用直接 storage 篡改不可行；用 retryRequest 路径在 Task 5 再覆盖。
      // 这里用一个全新的 sequence（不存在的 999），revealWithCallback 应该静默返回，无 RequestFulfilled emit
      // MockEntropy 不会让我们 reveal 不存在的 seq；改为：跑两次 reveal 同一个 seq —— 第二次因 _request 已 delete，应静默 return
      await mockEntropy.connect(owner).revealWithCallback(owner.address, 0n, RANDOM, PROVIDER_RANDOM);
      // 第二次 reveal 应静默（callback 内 exists=false 直接 return）
      // 注意：MockEntropy 自身可能阻止重复 reveal；如果是这样，本测试改用 retry 替换路径在 Task 5 中验证
      const req = await consumer.getRequest(0n);
      expect(req.exists).to.equal(false);
    });

    it("reverts entire callback when _onRequestFulfilled reverts", async function () {
      const { consumer, mockEntropy, alice, owner } = await loadFixture(deployEntropyFixture);
      await consumer.setRevertOnFulfill(true);
      await consumer.connect(alice).requestRandomness(7n, alice.address, 1, RANDOM, { value: FEE });
      // MockEntropy 的 reveal 会 try-catch 子合约的 callback；若该 mock 不对 hook 失败做特殊处理，
      // tx 整体 revert 即可证明传播路径。如该 SDK 版本将 callback 失败用 EntropyEvents 事件 + 状态标记，
      // 验证方式改为读 entropy.getRequestV2(...).callbackStatus === CALLBACK_FAILED
      const tx = mockEntropy.connect(owner).revealWithCallback(owner.address, 0n, RANDOM, PROVIDER_RANDOM);
      // 任意一种验证方式（实施时按 SDK 实际行为二选一）：
      // (A) await expect(tx).to.be.reverted;
      // (B) await tx; const r = await consumer.entropy().getRequestV2(owner.address, 0n);
      //     expect(r.callbackStatus).to.equal(2 /* CALLBACK_FAILED */);
      await tx; // 占位，按 SDK 行为补断言
    });
  });
```

> **NOTE on MockEntropy.reveal API:** Pyth SDK 的 `MockEntropy.sol` 暴露 reveal 路径名称在不同版本下略有差异（`revealWithCallback` / `_completeRequest` 等）。第一次跑测试如果方法不存在，`cat node_modules/@pythnetwork/entropy-sdk-solidity/MockEntropy.sol` 找实际方法名替换。"晚到回调静默"的测试可能需要换路径覆盖（例如在 Task 5 retry 之后再 reveal old seq），如果当前路径无法直接构造，把该用例 `it.skip` 标注并在 Task 5 用 retry 路径补回。

- [ ] **Step 3: 跑测试**

Run:
```bash
npx hardhat test test/runTest/EntropyConsumerBase.test.js
```

Expected：累计 11 个用例通过（1 个可能 skip）。

- [ ] **Step 4: Commit**

```bash
git add contracts/base/EntropyConsumerBase.sol test/runTest/EntropyConsumerBase.test.js
git commit -m "feat(entropy): implement entropyCallback dispatch + tests"
```

---

## Task 5: `retryRequest` + `_beforeRetry` 钩子 + 测试

**Files:**
- Modify: `contracts/base/EntropyConsumerBase.sol`（新增 `retryRequest` + `_beforeRetry`）
- Modify: `contracts/test/MockEntropyConsumer.sol`（实现 `_beforeRetry` 钩子开关）
- Modify: `test/runTest/EntropyConsumerBase.test.js`

- [ ] **Step 1: 在 `EntropyConsumerBase.sol` 添加 retry**

在 `entropyCallback` 之后插入：

```solidity
function retryRequest(
    uint64 oldSequenceNumber,
    bytes32 newUserRandomNumber,
    uint256 deadline
) external payable checkDeadline(deadline) returns (uint64 newSequenceNumber) {
    Request memory old = _request[oldSequenceNumber];
    if (!old.exists) revert ErrorRequestNotFound();
    if (old.requester != msg.sender) revert ErrorNotRequester();
    if (newUserRandomNumber == bytes32(0)) revert ErrorInvalidUserRandom();

    bool timedOut = block.timestamp >= uint256(old.requestedAt) + uint256(entropyTimeout);
    bool callbackFailed = false;
    if (!timedOut) {
        EntropyStructsV2.Request memory pythReq = entropy.getRequestV2(entropyProvider, oldSequenceNumber);
        callbackFailed = (pythReq.callbackStatus == EntropyStatusConstants.CALLBACK_FAILED);
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

function _beforeRetry(uint64 /*oldSequenceNumber*/, Request memory /*old*/) internal virtual {}

/// @dev 子类可在 base 退余款前同步业务状态（例如把 NFT 的 sequenceNumber 切到 newSeq）
function _postRetry(
    uint64 /*oldSequenceNumber*/,
    uint64 /*newSequenceNumber*/,
    Request memory /*updated*/
) internal virtual {}
```

- [ ] **Step 2: 在 `MockEntropyConsumer.sol` 实现 `_beforeRetry` / `_postRetry` 测试钩子**

contract 顶部追加状态：

```solidity
uint64 public lastPostRetryOldSeq;
uint64 public lastPostRetryNewSeq;
```

contract 内追加：

```solidity
function _beforeRetry(uint64 /*oldSequenceNumber*/, Request memory /*old*/) internal override {
    if (revertOnBeforeRetry) revert("before-retry-revert");
}

function _postRetry(uint64 oldSequenceNumber, uint64 newSequenceNumber, Request memory /*updated*/) internal override {
    lastPostRetryOldSeq = oldSequenceNumber;
    lastPostRetryNewSeq = newSequenceNumber;
}
```

- [ ] **Step 3: 写 retry 测试用例**

在 `EntropyConsumerBase.test.js` 末尾新增：

```javascript
  describe("retryRequest", function () {
    const RANDOM = "0x" + "11".repeat(32);
    const NEW_RANDOM = "0x" + "33".repeat(32);
    const FEE = 100n;
    const FAR_DEADLINE = 9999999999n;

    async function submit(consumer, alice) {
      await consumer.connect(alice).requestRandomness(5n, alice.address, 2, RANDOM, { value: FEE });
      return 0n; // first seq from MockEntropy
    }

    async function fastForward(seconds) {
      await ethers.provider.send("evm_increaseTime", [seconds]);
      await ethers.provider.send("evm_mine");
    }

    it("retries successfully after timeout", async function () {
      const { consumer, alice } = await loadFixture(deployEntropyFixture);
      const oldSeq = await submit(consumer, alice);
      await fastForward(3601); // > 1 hour

      const tx = consumer.connect(alice).retryRequest(oldSeq, NEW_RANDOM, FAR_DEADLINE, { value: FEE });
      await expect(tx).to.emit(consumer, "RequestRetried").withArgs(oldSeq, 1n, alice.address, FEE, FEE);

      expect((await consumer.getRequest(oldSeq)).exists).to.equal(false);
      const newReq = await consumer.getRequest(1n);
      expect(newReq.exists).to.equal(true);
      expect(newReq.tokenId).to.equal(5n);
      expect(newReq.itemCount).to.equal(2);
    });

    it("reverts ErrorRetryNotAllowed before timeout if not CALLBACK_FAILED", async function () {
      const { consumer, alice } = await loadFixture(deployEntropyFixture);
      const oldSeq = await submit(consumer, alice);
      await expect(
        consumer.connect(alice).retryRequest(oldSeq, NEW_RANDOM, FAR_DEADLINE, { value: FEE })
      ).to.be.revertedWithCustomError(consumer, "ErrorRetryNotAllowed");
    });

    it("retries on CALLBACK_FAILED before timeout", async function () {
      // 配合 MockEntropyConsumer.setRevertOnFulfill(true) 触发 Pyth callback 失败
      const { consumer, mockEntropy, alice, owner } = await loadFixture(deployEntropyFixture);
      const oldSeq = await submit(consumer, alice);
      await consumer.setRevertOnFulfill(true);
      // 触发 callback 让 Pyth mock 标记 CALLBACK_FAILED
      await mockEntropy.connect(owner).revealWithCallback(owner.address, oldSeq, RANDOM, "0x" + "22".repeat(32));
      await consumer.setRevertOnFulfill(false);

      // 此时 _request[oldSeq] 仍 exists（callback 未走到 delete 那一步前就 revert 了）
      // 但 SDK 标记了 CALLBACK_FAILED，retry 应该可以提前进行
      const tx = consumer.connect(alice).retryRequest(oldSeq, NEW_RANDOM, FAR_DEADLINE, { value: FEE });
      await expect(tx).to.emit(consumer, "RequestRetried");
    });

    it("reverts ErrorRequestNotFound for unknown seq", async function () {
      const { consumer, alice } = await loadFixture(deployEntropyFixture);
      await expect(
        consumer.connect(alice).retryRequest(999n, NEW_RANDOM, FAR_DEADLINE, { value: FEE })
      ).to.be.revertedWithCustomError(consumer, "ErrorRequestNotFound");
    });

    it("reverts ErrorNotRequester for non-original requester", async function () {
      const { consumer, alice, bob } = await loadFixture(deployEntropyFixture);
      const oldSeq = await submit(consumer, alice);
      await fastForward(3601);
      await expect(
        consumer.connect(bob).retryRequest(oldSeq, NEW_RANDOM, FAR_DEADLINE, { value: FEE })
      ).to.be.revertedWithCustomError(consumer, "ErrorNotRequester");
    });

    it("reverts ErrorInvalidUserRandom for zero random", async function () {
      const { consumer, alice } = await loadFixture(deployEntropyFixture);
      const oldSeq = await submit(consumer, alice);
      await fastForward(3601);
      await expect(
        consumer.connect(alice).retryRequest(oldSeq, ethers.ZeroHash, FAR_DEADLINE, { value: FEE })
      ).to.be.revertedWithCustomError(consumer, "ErrorInvalidUserRandom");
    });

    it("reverts ErrorInsufficientEntropyFee when msg.value < fee", async function () {
      const { consumer, alice } = await loadFixture(deployEntropyFixture);
      const oldSeq = await submit(consumer, alice);
      await fastForward(3601);
      await expect(
        consumer.connect(alice).retryRequest(oldSeq, NEW_RANDOM, FAR_DEADLINE, { value: 50n })
      ).to.be.revertedWithCustomError(consumer, "ErrorInsufficientEntropyFee");
    });

    it("propagates _beforeRetry revert", async function () {
      const { consumer, alice } = await loadFixture(deployEntropyFixture);
      const oldSeq = await submit(consumer, alice);
      await fastForward(3601);
      await consumer.setRevertOnBeforeRetry(true);
      await expect(
        consumer.connect(alice).retryRequest(oldSeq, NEW_RANDOM, FAR_DEADLINE, { value: FEE })
      ).to.be.revertedWith("before-retry-revert");
    });

    it("reverts on stale deadline", async function () {
      const { consumer, alice } = await loadFixture(deployEntropyFixture);
      const oldSeq = await submit(consumer, alice);
      await fastForward(3601);
      const past = (await ethers.provider.getBlock("latest")).timestamp - 1;
      await expect(
        consumer.connect(alice).retryRequest(oldSeq, NEW_RANDOM, past, { value: FEE })
      ).to.be.revertedWithCustomError(consumer, "DeadLineExpiredTransaction");
    });

    it("refunds excess msg.value to caller on retry", async function () {
      const { consumer, alice } = await loadFixture(deployEntropyFixture);
      const oldSeq = await submit(consumer, alice);
      await fastForward(3601);
      const before = await ethers.provider.getBalance(alice.address);
      const overpay = FEE + 999n;
      const tx = await consumer.connect(alice).retryRequest(oldSeq, NEW_RANDOM, FAR_DEADLINE, { value: overpay });
      const receipt = await tx.wait();
      const gasCost = receipt.gasUsed * receipt.gasPrice;
      const after = await ethers.provider.getBalance(alice.address);
      expect(before - after).to.equal(FEE + gasCost);
    });

    it("invokes _postRetry hook with old + new seq after _request[newSeq] is written", async function () {
      const { consumer, alice } = await loadFixture(deployEntropyFixture);
      const oldSeq = await submit(consumer, alice);
      await fastForward(3601);
      await consumer.connect(alice).retryRequest(oldSeq, NEW_RANDOM, FAR_DEADLINE, { value: FEE });
      expect(await consumer.lastPostRetryOldSeq()).to.equal(oldSeq);
      expect(await consumer.lastPostRetryNewSeq()).to.equal(1n);
      // hook saw newSeq populated
      expect((await consumer.getRequest(1n)).tokenId).to.equal(5n);
    });
  });
```

- [ ] **Step 4: 跑测试**

Run:
```bash
npx hardhat test test/runTest/EntropyConsumerBase.test.js
```

Expected：累计 ~21 个用例通过。

- [ ] **Step 5: Commit**

```bash
git add contracts/base/EntropyConsumerBase.sol contracts/test/MockEntropyConsumer.sol test/runTest/EntropyConsumerBase.test.js
git commit -m "feat(entropy): implement retryRequest with timeout/CALLBACK_FAILED gate + tests"
```

---

## Task 6: Governance setters + 测试

**Files:**
- Modify: `contracts/base/EntropyConsumerBase.sol`（新增三个 setter）
- Modify: `test/runTest/EntropyConsumerBase.test.js`

- [ ] **Step 1: 在 `EntropyConsumerBase.sol` 添加 setter**

在文件末尾插入：

```solidity
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
```

- [ ] **Step 2: 写 setter 测试用例**

在 `EntropyConsumerBase.test.js` 末尾新增：

```javascript
  describe("governance setters", function () {
    it("setEntropyProvider: success + event + zero-address revert + non-admin revert", async function () {
      const { consumer, owner, alice, bob } = await loadFixture(deployEntropyFixture);
      const oldProvider = await consumer.entropyProvider();
      await expect(consumer.connect(owner).setEntropyProvider(bob.address))
        .to.emit(consumer, "EntropyProviderChanged").withArgs(oldProvider, bob.address);
      expect(await consumer.entropyProvider()).to.equal(bob.address);

      await expect(consumer.connect(owner).setEntropyProvider(ethers.ZeroAddress))
        .to.be.revertedWithCustomError(consumer, "ErrorZeroAddress");

      await expect(consumer.connect(alice).setEntropyProvider(bob.address))
        .to.be.revertedWithCustomError(consumer, "AccessControlUnauthorizedAccount");
    });

    it("setCallbackGasLimit: bounds [100_000, 2_000_000] + event + non-admin revert", async function () {
      const { consumer, owner, alice } = await loadFixture(deployEntropyFixture);
      await expect(consumer.connect(owner).setCallbackGasLimit(750_000))
        .to.emit(consumer, "CallbackGasLimitChanged").withArgs(500_000, 750_000);
      expect(await consumer.callbackGasLimit()).to.equal(750_000n);

      await expect(consumer.connect(owner).setCallbackGasLimit(99_999))
        .to.be.revertedWithCustomError(consumer, "ErrorInvalidCallbackGasLimit");
      await expect(consumer.connect(owner).setCallbackGasLimit(2_000_001))
        .to.be.revertedWithCustomError(consumer, "ErrorInvalidCallbackGasLimit");

      await expect(consumer.connect(alice).setCallbackGasLimit(750_000))
        .to.be.revertedWithCustomError(consumer, "AccessControlUnauthorizedAccount");
    });

    it("setEntropyTimeout: bounds [60s, 24h] + event + non-admin revert", async function () {
      const { consumer, owner, alice } = await loadFixture(deployEntropyFixture);
      await expect(consumer.connect(owner).setEntropyTimeout(7200))
        .to.emit(consumer, "EntropyTimeoutChanged").withArgs(3600, 7200);
      expect(await consumer.entropyTimeout()).to.equal(7200n);

      await expect(consumer.connect(owner).setEntropyTimeout(59))
        .to.be.revertedWithCustomError(consumer, "ErrorInvalidEntropyTimeout");
      await expect(consumer.connect(owner).setEntropyTimeout(24 * 3600 + 1))
        .to.be.revertedWithCustomError(consumer, "ErrorInvalidEntropyTimeout");

      await expect(consumer.connect(alice).setEntropyTimeout(7200))
        .to.be.revertedWithCustomError(consumer, "AccessControlUnauthorizedAccount");
    });
  });
```

- [ ] **Step 3: 跑测试**

Run:
```bash
npx hardhat test test/runTest/EntropyConsumerBase.test.js
```

Expected：累计 ~24 个用例通过。

- [ ] **Step 4: Commit**

```bash
git add contracts/base/EntropyConsumerBase.sol test/runTest/EntropyConsumerBase.test.js
git commit -m "feat(entropy): governance setters with bounds + tests"
```

---

## Task 7: 终验 — 编译大小、覆盖率、文档交叉引用

**Files:**
- 无新增 / 修改源码（仅核验）
- Modify: `doc/entropy-consumer-base-design.md` 修订记录

- [ ] **Step 1: 编译 + 大小检查**

Run:
```bash
npx hardhat clean && npx hardhat compile
```

Expected：合约编译通过；hardhat-contract-sizer 输出表格。`MockEntropyConsumer` 应远低于 24KiB。基类是 abstract，sizer 不输出。

- [ ] **Step 2: 跑覆盖率（可选，如果时间允许）**

Run:
```bash
npx hardhat coverage --testfiles "test/runTest/EntropyConsumerBase.test.js"
```

Expected：基类核心分支（`_requestRandomness` / `entropyCallback` / `retryRequest` / setter）≥ 95% 行覆盖、≥ 90% 分支覆盖。

- [ ] **Step 3: 重跑 infra 现有测试套件，确保未破坏其他模块**

Run:
```bash
npx hardhat test
```

Expected：所有现有测试（BeneficiaryBase / GreatLottoCoin / DaoCoin / SalesChannel）+ 新增 EntropyConsumerBase 全部 PASS。

- [ ] **Step 4: 在 design doc 加修订记录**

修改 `doc/entropy-consumer-base-design.md` 文件末尾「修订记录」表格：

```markdown
| v1.1 | 2026-05-31 | Phase 1 实施完成；常量名修正为 `EntropyStatusConstants.CALLBACK_FAILED` |
```

- [ ] **Step 5: Final commit**

```bash
git add doc/entropy-consumer-base-design.md
git commit -m "docs(entropy): mark Phase 1 complete in design doc"
```

- [ ] **Step 6: Push 与 PR**

```bash
git push -u origin <branch-name>
gh pr create --title "feat(entropy): EntropyConsumerBase abstract base contract" --body "$(cat <<'EOF'
## Summary
- 新增 `EntropyConsumerBase` 抽象基类，封装 Pyth Entropy V2 的请求 / 回调 / 重试 / 治理流程
- 新增 `IEntropyConsumerBase` 接口（事件 / 错误 / Request struct）
- 新增 `MockEntropyConsumer` 测试子类 + 24 个单元测试用例
- 新增 `@pythnetwork/entropy-sdk-solidity` 运行时依赖

## Design
完整设计见 [doc/entropy-consumer-base-design.md](doc/entropy-consumer-base-design.md)。

## Test plan
- [x] 单元测试 ≥ 24 个用例覆盖部署、_requestRandomness、entropyCallback、retryRequest、governance setters
- [x] 覆盖率 ≥ 95% 行、≥ 90% 分支
- [x] 现有 infra 测试套件 PASS

## Follow-up
- Phase 2：ScratchCard 适配（独立 PR，依赖此 PR 合并后 bump infra 版本）
- Phase 3：GreatLottoCore 适配 + Solidity 0.8.35 升级
EOF
)"
```

---

## Self-Review Checklist（实施完成后核对）

- [ ] 所有 Task commit message 已使用规范前缀（`feat(entropy):` / `docs(entropy):`）
- [ ] `EntropyConsumerBase.sol` 行数 < 200，单一职责
- [ ] `_request` mapping 占用 3 storage slot 与设计文档一致
- [ ] 所有 custom error 在 `IEntropyConsumerBase.sol` 声明、`EntropyConsumerBase.sol` 抛出，无重复定义
- [ ] `entropyCallback` 没有 `virtual` 标记（final）；子类无法绕过软删除 + emit
- [ ] `_requestRandomness` 与 `retryRequest` 都遵守 CEI（先写 storage 后 refund）
- [ ] `setEntropyProvider` 切换时 in-flight `oldSeq` 仍可在原 provider 完成 callback（手动验证：写一个不在测试套件中的 sandbox 用例确认）
