# Ignition 部署参数

每条目标链一份 JSON（部署参数已从 `.env` 迁到此处）。`owner` 默认 `0x000...`，部署前必须替换为真实值。

## 字段来源

| 字段 | 来源 |
|------|------|
| `owner` | 构造时取得 `DEFAULT_ADMIN_ROLE` 的管理员地址（主网强烈建议 Safe 多签） |
| `supportedTokens` | `GreatLottoCoin._tokens` 稳定币白名单，按目标链填入对应稳定币地址。`GreatLottoCoinTest`（测试变体，免费 mint）+ 测试网 / 本地可留空 `[]` |

## 部署示例

```bash
# 本地（先 `anvil` 或 `npx hardhat node`）
npx hardhat ignition deploy ignition/modules/infrastructure.js \
  --network localhost --parameters ignition/parameters/localhost.json

# 测试网
npx hardhat ignition deploy ignition/modules/infrastructure.js \
  --network baseSepolia --parameters ignition/parameters/baseSepolia.json --reset --verify
npx hardhat ignition deploy ignition/modules/infrastructure.js \
  --network arbitrumSepolia --parameters ignition/parameters/arbitrumSepolia.json --reset --verify
npx hardhat ignition deploy ignition/modules/infrastructure.js \
  --network optimismSepolia --parameters ignition/parameters/optimismSepolia.json --reset --verify
npx hardhat ignition deploy ignition/modules/infrastructure.js \
  --network unichainSepolia --parameters ignition/parameters/unichainSepolia.json --reset --verify

# 主网
npx hardhat ignition deploy ignition/modules/infrastructure.js \
  --network base --parameters ignition/parameters/base.json --reset --verify
npx hardhat ignition deploy ignition/modules/infrastructure.js \
  --network arbitrum --parameters ignition/parameters/arbitrum.json --reset --verify
npx hardhat ignition deploy ignition/modules/infrastructure.js \
  --network optimism --parameters ignition/parameters/optimism.json --reset --verify
npx hardhat ignition deploy ignition/modules/infrastructure.js \
  --network unichain --parameters ignition/parameters/unichain.json --reset --verify
```

## 校对清单

- [ ] `owner` 为预期治理账户（主网建议 Safe 多签）
- [ ] `supportedTokens` 与目标链稳定币地址一致（主网部署 `GreatLottoCoin` 时必填；测试网 / 本地 `GreatLottoCoinTest` 可留空）
- [ ] 主网前把 `ignition/modules/infrastructure.js` 从 `GreatLottoCoinTest` 切回 `GreatLottoCoin`
- [ ] `.env` 中的 `DEPLOY_ACCOUNT_PRIVATE_KEY` / `ALCHEMY_API_KEY` / `*SCAN_API_KEY` 已配置（RPC / 验证仍读 env）

> **下游 localhost 地址依赖**：ScratchCard / GreatLottoCore 的 `localhost.json` 预填了「fresh 本地链上由 account#0 首个部署本模块」得到的确定性地址（GreatLottoCoin / SalesVault / SalesChannel）。改动本模块的合约部署顺序会影响这些地址 —— 如调整顺序，记得同步更新下游两仓的 `localhost.json`。
