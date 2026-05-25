# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 常用命令

### 开发

```shell
# 编译合约
npx hardhat compile

# 清除编译产物
npx hardhat clean

# 运行全部测试（需先启动本地节点）
npx hardhat test --network localhost test/runTest/*.js

# 运行单个测试文件
npx hardhat test --network localhost test/runTest/SalesChannel.js

# 覆盖率报告
npx hardhat coverage --testfiles "test/runTest/*.js"
```

### 启动本地节点（分叉主网或 Holesky）

```shell
# 分叉主网
npx hardhat node --fork https://eth-mainnet.g.alchemy.com/v2/<ALCHEMY_API_KEY> --fork-block-number 22473100

# 分叉 Holesky
npx hardhat node --fork https://eth-holesky.g.alchemy.com/v2/<ALCHEMY_API_KEY> --fork-block-number 2360339
```

### 部署

```shell
# 部署到本地
npx hardhat ignition deploy ignition/modules/infrastructure.js --network localhost

# 部署到测试网
npx hardhat ignition deploy ignition/modules/infrastructure.js --network holesky --reset --verify

# 部署后验证合约
npx hardhat ignition verify chain-17000    # holesky
npx hardhat ignition verify chain-11155111 # sepolia
```

### 环境变量（`.env`）

- `ALCHEMY_API_KEY` — Alchemy API Key，用于所有 RPC 节点及默认 hardhat 分叉
- `DEPLOY_ACCOUNT_PRIVATE_KEY` — 部署账户私钥
- `OWNER_ADDRESS` — 合约部署时传入的管理员地址
- `ETHERSCAN_API_KEY` — 用于合约验证

## 架构说明

本项目使用 Hardhat + Solidity 0.8.24 + OpenZeppelin，为 GreatLottoGroup 彩票平台提供底层代币基础设施。

### 核心合约

| 合约 | 代币符号 | 用途 |
|---|---|---|
| `GreatLottoCoin` | GLC | ERC20，与稳定币 1:1 锚定（主网支持 USDT、USDC、DAI） |
| `GreatLottoEth` | GLETH | ERC20，与 WETH 1:1 锚定，同时支持原生 ETH wrap/unwrap |
| `DaoCoin` | GLDC | 治理代币（ERC20Votes），用户购买彩票时按比例赠送 |
| `DaoBenefitPool` | — | 将合约内的 GLC/GLETH 利润按比例分发给 GLDC 持有者 |
| `SalesChannel` | — | 管理销售渠道的注册与启用/禁用状态 |

### 关键架构模式

**合作合约角色（PARTNER_CONTRACT_ROLE）**：`GreatLottoCoin` 和 `GreatLottoEth` 的 `mint()` 函数仅允许持有 `PARTNER_CONTRACT_ROLE` 的地址调用。`AccessControlPartnerContract` 重写了 `grantRole`，强制要求被授权地址必须是合约地址（非 EOA）。外部彩票合约在用户支付时通过此角色调用 `mint()`。

**受益人分润机制**：`DaoCoin` 继承 `BeneficiaryBase`，后者通过重写 `_update` 钩子自动维护持有量 ≥ 10,000 GLDC 的受益人列表。调用 `DaoBenefitPool.executeBenefit()` 时，合约内全部 GLC 或 GLETH 余额将按持仓比例分发给当前受益人。

**测试合约**：`contracts/test/` 中的 `GreatLottoCoinTest`、`GreatLottoEthTest`、`PartnerTest` 覆盖了代币地址（将主网 USDT/USDC/DAI 替换为本地/Holesky 地址）。`ignition/modules/infrastructure.js` 当前部署的是 `*Test` 版本，**主网部署前须切换为生产合约**。

### 基础合约层级

- `AccessControlPartnerContract` — OpenZeppelin `AccessControl` + `PARTNER_CONTRACT_ROLE`，重写 `grantRole` 限制仅合约地址可被授权
- `BeneficiaryBase` — 维护受益人列表，通过 `_update` hook 嵌入 `DaoCoin`
- `BenefitPoolBase` — 分润执行逻辑，`DaoBenefitPool` 的实现基础
- `NoDelegateCall` — 阻止对敏感函数的 delegatecall
- `DeadLine` — 交易截止时间校验（`checkDeadline` modifier）
- `SelfPermit` — 为 USDT（非标准）和标准 ERC20Permit 代币提供 EIP-2612 permit 辅助方法

### 代币地址配置

主网/本地分叉的代币地址硬编码在 `GreatLottoCoin._tokens` 和 `GreatLottoEth._tokens` 中。测试网地址以注释形式紧跟其后。切换网络时，激活对应的地址数组并注释掉另一组。
