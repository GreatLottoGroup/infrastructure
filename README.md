# Infrastructure

GreatLottoGroup 平台的底层代币基础设施合约（Solidity 0.8.26 + OpenZeppelin v5）。

> **工具链分工**：**测试用 Foundry**（`forge test`，含 fuzz/invariant）；**Hardhat 只管部署（Ignition）与 ABI 产出**。

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
# —— 测试（Foundry）——
# 首次 / CI 需先装 forge-std（lib/ 已 gitignore，不入库）
forge install foundry-rs/forge-std

forge test                         # 全部测试（单测 + invariant）；等价 npm test
forge test --match-path test/foundry/SalesChannel.t.sol   # 单文件
forge test --gas-report            # gas 报告；等价 npm run gas
forge coverage --report summary   # 覆盖率；等价 npm run coverage

# —— 编译 / 部署（Hardhat）——
npx hardhat compile                # 编译 + 产出 ABI（供下游与 interface 消费）
npx hardhat clean
```

> 测试**全本地化、无需 fork**（底层稳定币用 6 位 ERC20Permit mock）。`test/foundry/` 含 9 单测 + 2 invariant；辅助合约在 `test/foundry/{mocks,harness}/`。
> 注：`forge build` 不依赖 forge-std，缺它仍能编过、只有 `forge test` 报错——别被 build 通过误导。

## 部署

部署参数走 Ignition 参数文件（每条链一份，见 [ignition/parameters/](ignition/parameters/)），不再走 `.env`。

```shell
# 部署到本地（先 `anvil` 或 `npx hardhat node` 起本地链）
npx hardhat ignition deploy ignition/modules/infrastructure.js \
  --network localhost --parameters ignition/parameters/localhost.json

# 部署到测试网（首发链 Base / Arbitrum，见 hardhat.config.js networks）
npx hardhat ignition deploy ignition/modules/infrastructure.js \
  --network baseSepolia --parameters ignition/parameters/baseSepolia.json --reset --verify
npx hardhat ignition deploy ignition/modules/infrastructure.js \
  --network arbitrumSepolia --parameters ignition/parameters/arbitrumSepolia.json --reset --verify

# 主网（生产前需将 ignition 模块改为部署 GreatLottoCoin 而非 GreatLottoCoinTest）
npx hardhat ignition deploy ignition/modules/infrastructure.js \
  --network base --parameters ignition/parameters/base.json --reset --verify
npx hardhat ignition deploy ignition/modules/infrastructure.js \
  --network arbitrum --parameters ignition/parameters/arbitrum.json --reset --verify
```

## 部署 Checklist

1. 测试用例全绿（`forge test`）
2. `ignition/parameters/<network>.json` 的 `supportedTokens` 与目标链稳定币地址一致（测试网 / 本地可留空）
3. `ignition/parameters/<network>.json` 的 `owner` 为预期治理账户；`.env` 中 `DEPLOY_ACCOUNT_PRIVATE_KEY` 已配置
4. `ignition/modules/infrastructure.js` 切换为生产合约（默认部署的是 `*Test` 变种）

## 环境变量（`.env`）

`.env` 仅保留 RPC / 部署账号 / 验证密钥；`owner` / `supportedTokens` 等部署参数已迁到 [ignition/parameters/](ignition/parameters/)。

```
ALCHEMY_API_KEY=...
DEPLOY_ACCOUNT_PRIVATE_KEY=...
BASESCAN_API_KEY=...
ARBISCAN_API_KEY=...
```

## NPM 发布

```shell
npm publish --access public
```

下游仓库（`GreatLottoCore` / `ScratchCard`）通过 `@greatlotto/infrastructure` 引用本仓库的合约源码与 ABI。
