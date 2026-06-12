# Infrastructure

GreatLottoGroup 平台的底层代币基础设施合约（Hardhat + Solidity 0.8.24 + OpenZeppelin v5）。

## 合约一览

| 合约 | 符号 | 用途 |
|---|---|---|
| `GreatLottoCoin` | GLC | ERC20 资产币，与稳定币 1:1 锚定（**仅支持 USDT、USDC**） |
| `DaoCoin` | GLDC | 治理币（ERC20Votes），按 `coinPrice` 单一定价铸造 |
| `DaoBenefitPool` | — | 单轨分润池，将 GLC 余额按持仓比例分发给 GLDC 受益人 |
| `SalesChannel` | — | 销售渠道注册与启用/禁用 |

> **注**：原 `GreatLottoEth` (GLETH) 已下线；`SelfPermit` 仅保留 EIP-2612 标准入口；`_tokens` 白名单中已移除 DAI（详见 `openspec/changes/archive/`）。

## 常用命令

```shell
# 编译
npx hardhat compile

# 清理
npx hardhat clean

# 测试（默认 fork mainnet，由 hardhat.config.js networks.hardhat.forking 提供）
npx hardhat test test/runTest/*.js

# 单文件
npx hardhat test test/runTest/SalesChannel.js

# 覆盖率
npx hardhat coverage --testfiles "test/runTest/*.js"
```

如需独立的 fork 节点：

```shell
# arb主网 fork
npx hardhat node --fork https://arb-mainnet.g.alchemy.com/v2/<ALCHEMY_KEY> --fork-block-number 472312054
```

## 部署

```shell
# 本地（hardhat 临时网络）
npx hardhat ignition deploy ignition/modules/infrastructure.js

# Localhost 节点
npx hardhat ignition deploy ignition/modules/infrastructure.js --network localhost
npx hardhat ignition deploy ignition/modules/infrastructure.js --network localhost --reset

# Sepolia
npx hardhat ignition deploy ignition/modules/infrastructure.js --network sepolia --verify
npx hardhat ignition verify chain-11155111

# Mainnet（生产前需将 ignition 模块改为部署 GreatLottoCoin 而非 GreatLottoCoinTest）
npx hardhat ignition deploy ignition/modules/infrastructure.js --network mainnet --verify
```

## 部署 Checklist

1. 测试用例全绿（`npx hardhat test test/runTest/*.js`）
2. `GreatLottoCoin._tokens` 中的代币地址匹配目标链（mainnet vs sepolia 注释切换）
3. `.env` 中 `OWNER_ADDRESS` / `DEPLOY_ACCOUNT_PRIVATE_KEY` 已配置
4. `ignition/modules/infrastructure.js` 切换为生产合约（默认部署的是 `*Test` 变种）

## 环境变量（`.env`）

```
ALCHEMY_API_KEY=...
DEPLOY_ACCOUNT_PRIVATE_KEY=...
OWNER_ADDRESS=0x...
ETHERSCAN_API_KEY=...
```

## NPM 发布

```shell
npm publish --access public
```

下游仓库（`GreatLottoCore` / `ScratchCard`）通过 `@greatlotto/infrastructure` 引用本仓库的合约源码与 ABI。
