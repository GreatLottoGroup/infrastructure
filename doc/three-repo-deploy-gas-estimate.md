# 三仓合约部署 Gas 测算报告

> 测算日期：2026-07-13
> 场景：GreatLottoGroup 三个合约仓（infrastructure / GreatLottoCore / ScratchCard）在 **Arbitrum Sepolia Testnet** 部署，网络 gas price **0.02 Gwei** 下的 ETH 花费。
> 结论速览：纯 L2 执行费 **≈ 0.000744 ETH**（总 gas ≈ 37.2M）；叠加 Arbitrum L1 数据费后，建议预留 **0.002 ~ 0.004 ETH**。

---

## 1. 测算方法

- **不是估算，是实测**：在本地 Hardhat 网络逐个真实部署每个生产合约，从交易回执读取实际 `gasUsed`。
- 各仓生产 Ignition 模块（`ignition/modules/*.js`）确定部署哪些合约与顺序：
  - `infrastructure/ignition/modules/infrastructure.js`
  - `GreatLottoCore/ignition/modules/GreatLottoCore.js`
  - `ScratchCard/ignition/modules/ScratchCard.js`
- infra 合约按依赖顺序用真实地址部署（GLC → SalesVault → SalesChannel，因 SalesVault 是 ERC4626 构造期读 asset decimals）；Core / ScratchCard 的外部依赖（GLC / SalesVault / SalesChannel / Pyth entropy / provider）用占位非零地址——这些地址在构造期仅被存为 immutable、不发生外部调用，不影响部署 gas。
- ETH 换算：`gasUsed × 0.02 Gwei = gasUsed × 0.02 × 10⁻⁹ ETH`。
- 编译口径：solc 0.8.26、viaIR、optimizer runs=200（三仓一致）。

---

## 2. 逐合约 gasUsed

### infrastructure（3 个合约）

| 合约 | gasUsed |
|---|---:|
| GreatLottoCoinTest | 1,793,240 |
| SalesVault | 1,291,147 |
| SalesChannel | 1,191,435 |
| **小计** | **4,275,822** |

> 当前生产模块部署的是 `GreatLottoCoinTest`（带免费 mint 的测试变体），测试网正合适；**主网前须切回 `GreatLottoCoin`**（gas 量级相近）。

### GreatLottoCore（6 个合约 + 1 笔模块内授权）

| 合约 | gasUsed |
|---|---:|
| GreatLottoNFTSVG | 5,168,084 |
| GreatLottoNFT | 3,771,179 |
| InvestmentPositionSVG | 2,947,952 |
| InvestmentPosition | 2,352,049 |
| PrizePool | 2,800,650 |
| GreatLotto | 3,317,781 |
| **小计** | **20,357,695** |

> 模块内含 1 笔 `grantRole`（InvestmentPosition → PrizePool 授 PARTNER_CONTRACT_ROLE），~54.5k gas。

### ScratchCard（4 个合约）

| 合约 | gasUsed |
|---|---:|
| ScratchCardNFTSVG | 4,352,372 |
| ScratchCardNFT | 2,446,935 |
| PrizePool | 1,614,216 |
| ScratchCard | 3,670,795 |
| **小计** | **12,084,318** |

---

## 3. 汇总与 ETH 花费（@ 0.02 Gwei）

| 项目 | gas | @ 0.02 Gwei |
|---|---:|---:|
| infrastructure（3） | 4,275,822 | 0.0000855 ETH |
| GreatLottoCore（6） | 20,357,695 | 0.0004072 ETH |
| ScratchCard（4） | 12,084,318 | 0.0002417 ETH |
| **合约部署小计（13）** | **36,717,835** | **0.0007344 ETH** |
| grantRole 授权（~9 笔 × ~54.4k） | ~490,000 | ~0.0000098 ETH |
| **总计** | **≈ 37,207,835** | **≈ 0.000744 ETH** |

**部署后授权（~9 笔 grantRole，每笔 ~54.4k gas）**：

- Core：GreatLottoNFT→GreatLotto、PrizePool→GreatLotto、GLC→PrizePool、SalesChannel→PrizePool（4 笔，DAO 手动补）+ InvestmentPosition→PrizePool（1 笔，模块内）
- ScratchCard：ScratchCardNFT→ScratchCard、PrizePool→ScratchCard、GLC→PrizePool、SalesChannel→PrizePool（4 笔，owner 手动补）
- infra：部署当天无授权

---

## 4. ⚠️ Arbitrum 重要修正

1. **以上是纯 L2 执行费**。Arbitrum 部署合约会把全部 init code（三仓 13 个合约合计 **约 190 KB** 创建字节码）作为 calldata 发布到 L1（Sepolia），产生一笔**独立的 L1 数据费**。这笔费用 **不包含在 0.02 Gwei 的 L2 gas price 里**，且对「合约部署」这类大 calldata 交易往往是主要成本。
2. **实用预留**：纯 L2 约 0.00074 ETH；叠加 L1 数据费后，三仓建议按 **0.002 ~ 0.004 ETH** 预留测试网 ETH，绰绰有余。
3. **含 L1 的精确报价**：部署前对每个仓跑一次 `--network arbitrumSepolia` 的 Ignition dry-run（不加 `--verify`），Ignition 会给出含 L1 的真实 gas 估算。
4. Arbitrum One / Sepolia 单笔 tx 的 gas 上限远高于本测算最大单合约（GreatLottoNFTSVG 5.17M），无单笔超限风险。

---

## 5. 复现方式

在各仓写一个一次性脚本，用 `ethers.getContractFactory(name).deploy(...args)` 逐个部署，读 `deploymentTransaction().wait()` 的 `gasUsed` 求和；`--network hardhat`（in-process）即可，无需起独立节点。注意本地 Hardhat 网络默认单笔 tx gas 上限约 16.77M（2²⁴），部署大合约时对 `deploy` 显式传 `{ gasLimit: 16_700_000 }` 可绕过自动 estimateGas 的停滞。
