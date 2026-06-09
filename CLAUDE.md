# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **工作区协调层**：本仓属于 GreatLottoGroup 4 仓工作区。跨仓需求 / 流水线 / 共享知识库见 `@see` [../.claude-workspace/CLAUDE.md](../.claude-workspace/CLAUDE.md)（知识库索引 [../.claude-workspace/knowledge/index.md](../.claude-workspace/knowledge/index.md)）。
>
> **superpower × OpenSpec 路径覆盖**：`writing-plans` 的 plan 落 `openspec/changes/<id>/design.md` 与 `tasks.md`（覆盖默认 `docs/superpowers/...`）；`requesting-code-review` / `/flow-review-spec` 笔记落 `openspec/changes/<id>/review.md`。三道 review 门：方案(`/flow-review-spec`) → 代码(`requesting-code-review`) → 安全(`/security-review`，合约仓必跑)。**本仓接口变更是下游 ScratchCard / Core 的契约源，先定稿。**

## 常用命令

### 开发

```shell
# 编译合约
npx hardhat compile

# 清除编译产物
npx hardhat clean

# 运行全部测试
npx hardhat test test/runTest/*.js

# 运行单个测试文件
npx hardhat test test/runTest/SalesChannel.js

# 覆盖率报告
npx hardhat coverage --testfiles "test/runTest/*.js"
```

### 启动本地节点（分叉主网）

```shell
# 分叉主网（GreatLottoCoin / permit 测试需要 fork）
npx hardhat node --fork https://eth-mainnet.g.alchemy.com/v2/<ALCHEMY_API_KEY> --fork-block-number 22473100
```

### 部署

```shell
# 部署到本地
npx hardhat ignition deploy ignition/modules/infrastructure.js --network localhost

# 部署到测试网（首发链 Base / Arbitrum，见 hardhat.config.js networks）
npx hardhat ignition deploy ignition/modules/infrastructure.js --network baseSepolia --reset --verify
npx hardhat ignition deploy ignition/modules/infrastructure.js --network arbitrumSepolia --reset --verify

# 主网
npx hardhat ignition deploy ignition/modules/infrastructure.js --network base --reset --verify
npx hardhat ignition deploy ignition/modules/infrastructure.js --network arbitrum --reset --verify
```

### 环境变量（`.env`）

- `ALCHEMY_API_KEY` — Alchemy API Key，用于所有 RPC 节点及默认 hardhat 分叉
- `DEPLOY_ACCOUNT_PRIVATE_KEY` — 部署账户私钥
- `OWNER_ADDRESS` — 合约部署时传入的管理员地址
- `BASESCAN_API_KEY` — Base 主网 / Base Sepolia 合约验证
- `ARBISCAN_API_KEY` — Arbitrum One / Arbitrum Sepolia 合约验证

## 架构说明

本项目使用 Hardhat + Solidity 0.8.24 + OpenZeppelin，为 GreatLottoGroup 彩票平台提供底层代币基础设施。

### 核心合约

| 合约 | 代币符号 | 用途 |
|---|---|---|
| `GreatLottoCoin` | GLC | ERC20，与稳定币 1:1 锚定（主网支持 USDT、USDC） |
| `DaoCoin` | GLDC | 治理代币（ERC20Votes），用户购买彩票时按比例赠送（单一定价 `coinPrice`） |
| `DaoBenefitPool` | — | 将合约内的 GLC 利润按比例分发给 GLDC 持有者（单轨：仅 GLC） |
| `SalesChannel` | — | 管理销售渠道的注册与启用/禁用状态 |

### 关键架构模式

**合作合约角色（PARTNER_CONTRACT_ROLE）**：`GreatLottoCoin` 的 `mint()` 函数仅允许持有 `PARTNER_CONTRACT_ROLE` 的地址调用。`AccessControlPartnerContract` 重写了 `grantRole`，强制要求被授权地址必须是合约地址（非 EOA）。外部彩票合约在用户支付时通过此角色调用 `mint()`。

**受益人分润机制**：`DaoCoin` 继承 `BeneficiaryBase`，后者通过重写 `_update` 钩子自动维护持有量 ≥ 10,000 GLDC 的受益人列表。调用 `DaoBenefitPool.executeBenefit(deadline)` 时，合约内全部 GLC 余额将按持仓比例分发给当前受益人。

**测试合约**：`contracts/test/` 中的 `GreatLottoCoinTest`（加 `mintFor` 等测试入口）和 `PartnerTest`。支持的代币地址现由构造参数传入（见「代币地址配置」），不再靠 `*Test` 改源码覆盖。`ignition/modules/infrastructure.js` 当前部署的是 `*Test` 版本，**主网部署前须切换为生产合约**。

### 基础合约层级

- `AccessControlPartnerContract` — OpenZeppelin `AccessControl` + `PARTNER_CONTRACT_ROLE`，重写 `grantRole` 限制仅合约地址可被授权
- `BeneficiaryBase` — 维护受益人列表，通过 `_update` hook 嵌入 `DaoCoin`
- `BenefitPoolBase` — 单轨分润执行逻辑，`DaoBenefitPool` 的实现基础
- `EntropyConsumerBase` — Pyth Entropy V2 异步随机数请求/回调/重试/治理基类，下游通过 `is EntropyConsumerBase` 接入。构造签名 `(address entropy_, address entropyProvider_, address owner_)`：在构造期 `_grantRole(DEFAULT_ADMIN_ROLE, owner_)`（`owner_ == address(0)` 时回退到 `msg.sender`），使治理 setter（`setEntropyProvider` / `setCallbackGasLimit` / `setEntropyTimeout`）在「未同时继承 `AccessControlPartnerContract`」的独立消费者上也可用。`_refundFee` 内部对 `amount == 0` 早退，请求/重试两处退款直接调用即可
- `PrizePoolBase` — 抽象奖池基类，提供奖金池收款（GLC 直接转账 / 外币 mint / EIP-2612 permit）、`_transferTo` 严格不变量转账、渠道+DAO 两段分润 pipeline、治理币增发等 internal helper，以及独立的渠道/sell 分润率治理 setter（`setChannelBenefitRate` / `setSellBenefitRate`）。下游（ScratchCard / GreatLottoCore）通过 `is PrizePoolBase` 继承，构造时显式传入 4 个 immutable 地址 + 2 档分润率初值。**付奖兜底（push→pull）已下沉至本基类**：子类在 try/catch 付奖失败分支调 `_recordPendingPayout(user, amount)`（按 user 记账 + emit `PayoutPending`），用户经 `claimPayout()`（`noDelegateCall`，故基类已 `is NoDelegateCall`）提取、`pendingPayoutOf(user)` 查询；资产币单一 GLC 故仅记金额。对应接口/事件/错误在 `IPrizePoolBase`（`claimPayout` / `pendingPayoutOf` / `PayoutPending` / `PayoutClaimed` / `ErrorNoPendingPayout`）
- `NoDelegateCall` — 阻止对敏感函数的 delegatecall
- `DeadLine` — 交易截止时间校验（`checkDeadline` modifier）
- `SelfPermit` — 仅 EIP-2612 标准 permit（`selfPermit` / `selfPermitIfNecessary`）；DAI/CHAI 风格入口已下线

### 代币地址配置

支持的稳定币地址由 **构造参数** `GreatLottoCoin(address[] tokensAddress_, address owner_)` 在部署时传入（不再硬编码在 `_tokens` 源码中）。按部署网络在部署脚本里传对应地址数组：
- `ignition/modules/infrastructure.js` 顶部 `supportedTokens` 常量（默认主网 USDT / USDC，测试网请替换）。
- 测试 fork 默认值在 `test/utils/deployTool.js` 的 `deploy()`（可经 `config.tokens` 覆盖）。

`GreatLottoCoinTest` 仅在父构造参数之外加 `mintFor` 等测试入口，构造签名与 `GreatLottoCoin` 一致（`(address[] tokensAddress_, address owner_)`）。
