# Infrastructure

GreatLottoGroup 平台的底层代币基础设施合约（Solidity 0.8.36 + OpenZeppelin v5）。

> **工具链分工**：**测试用 Foundry**（`forge test`，含 fuzz/invariant）；**Hardhat 只管部署（Ignition）与 ABI 产出**。

## 合约一览

| 合约 | 符号 | 用途 |
|---|---|---|
| `GreatLottoCoin` | GLC | ERC20 资产币，与稳定币 1:1 锚定（**当前仅支持 USDC**，白名单可扩展） |
| `SalesVault` | GLSV | ERC4626 销售利润金库；销售分润注入抬高份额净值，份额持有人凭 `redeem`/`withdraw` 按比例提走 GLC |
| `SalesChannel` | — | 销售渠道注册表 + 渠道分润托管账本（PARTNER `creditChannel` 记账、渠道方 `withdraw` 自提，pull payment） |

> **注**：原 `GreatLottoEth` (GLETH) 与 DAO 分红机制（`DaoCoin` / `DaoBenefitPool`）均已下线——销售分润改由 `SalesVault`（ERC4626）承接；`SelfPermit` 仅保留 EIP-2612 标准入口；`_tokens` 白名单中已移除 DAI（详见 `openspec/changes/archive/`）。合约机制详解见根目录 [WhitePaper_ZH.md](WhitePaper_ZH.md)（英文版 [WhitePaper_EN.md](WhitePaper_EN.md)）。

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

> 测试**全本地化、无需 fork**（底层稳定币用 6 位 ERC20Permit mock）。`test/foundry/` 含 7 单测 + 3 invariant；辅助合约在 `test/foundry/{mocks,harness}/`。
> 注：`forge build` 不依赖 forge-std，缺它仍能编过、只有 `forge test` 报错——别被 build 通过误导。

## 接口文档（NatSpec + forge doc）

主合约所有对外方法均有英文 NatSpec 注释。用 Foundry 原生 `forge doc` 一键生成 markdown 接口文档，并用零依赖 checker 校验完整性（缺注释即非零退出）：

```shell
npm run docs        # forge doc → docs/（已 gitignore，按需重生）
npm run docs:serve  # 本地 mdbook 预览（http://localhost:4000）
npm run docs:lint   # forge build --ast --force + 校验所有 external/public 方法都有 @notice/@param/@return
```

> 本仓是基类文档的**权威来源**：下游仓（ScratchCard / GreatLottoCore）继承本仓 `EntropyConsumerBase` / `PrizePoolBase` 的对外 API，其合约页交叉链接回本仓文档。规范见工作区 `.claude-workspace/knowledge/conventions/natspec.md`。

## 部署

部署参数走 Ignition 参数文件（每条链一份，见 [ignition/parameters/](ignition/parameters/)），不再走 `.env`。

```shell
# 部署到本地（先 `anvil` 或 `npx hardhat node` 起本地链）
npx hardhat ignition deploy ignition/modules/infrastructure.js \
  --network localhost --parameters ignition/parameters/localhost.json

# 部署到测试网（Base / Arbitrum / Optimism / Unichain，见 hardhat.config.js networks）
npx hardhat ignition deploy ignition/modules/infrastructure.js \
  --network baseSepolia --parameters ignition/parameters/baseSepolia.json --reset --verify
npx hardhat ignition deploy ignition/modules/infrastructure.js \
  --network arbitrumSepolia --parameters ignition/parameters/arbitrumSepolia.json --reset --verify
npx hardhat ignition deploy ignition/modules/infrastructure.js \
  --network optimismSepolia --parameters ignition/parameters/optimismSepolia.json --reset --verify
npx hardhat ignition deploy ignition/modules/infrastructure.js \
  --network unichainSepolia --parameters ignition/parameters/unichainSepolia.json --reset --verify

# 主网（生产前需将 ignition 模块改为部署 GreatLottoCoin 而非 GreatLottoCoinTest）
npx hardhat ignition deploy ignition/modules/infrastructure.js \
  --network base --parameters ignition/parameters/base.json --reset --verify
npx hardhat ignition deploy ignition/modules/infrastructure.js \
  --network arbitrum --parameters ignition/parameters/arbitrum.json --reset --verify
npx hardhat ignition deploy ignition/modules/infrastructure.js \
  --network optimism --parameters ignition/parameters/optimism.json --reset --verify
npx hardhat ignition deploy ignition/modules/infrastructure.js \
  --network unichain --parameters ignition/parameters/unichain.json --reset --verify
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
ETHERSCAN_API_KEY=...
```

## NPM 发布

```shell
npm publish --access public
```

下游仓库（`GreatLottoCore` / `ScratchCard`）通过 `@greatlotto/infrastructure` 引用本仓库的合约源码与 ABI。
