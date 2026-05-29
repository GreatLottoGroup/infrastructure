# 跨仓 ETH 支付通道下线方案（v2，2026-05-28）

> v2 改动：在 v1 基础上追加 **下线 DAI 支付** 的范围（包含 `SelfPermit` 中的 DAI/CHAI 风格 permit 接口）。

## 1. 背景与目标

GreatLottoGroup 当前在三个合约仓库中并行维护两条支付轨道：

- **稳定币轨道**（`GreatLottoCoin` / GLC）：USDT、USDC、DAI 三种 1:1 锚定的 ERC20。
- **ETH 轨道**（`GreatLottoEth` / GLETH）：原生 ETH（`wrap` / `unwrap`） + WETH（`mint` / `withdraw`）。

业务侧已决定 **下线 ETH 支付通道**，并 **同步下线 DAI**——稳定币列表收敛为 **USDT + USDC**。本文给出 `infrastructure`、`GreatLottoCore`、`ScratchCard` 三个仓库的统一下线方案，并指明每个仓库需要发起的 OpenSpec change proposal。

### 目标

1. 删除 `infrastructure/contracts/GreatLottoEth.sol` 及其接口、测试合约、ignition 引用。
2. 上层合约去掉所有 `bool isEth` 分支，统一走 `GreatLottoCoin` 稳定币路径。
3. 上层合约的 view / event / struct 中的 `isEth` 字段一并清理，不保留兼容字段（**Breaking Change，按全新部署执行**，不做就地升级）。
4. **下线 DAI 子通道**：
   - `GreatLottoCoin._tokens` 数组移除 DAI（mainnet `0x6B17…1d0F` / sepolia `0x6819…D574`），`_tokens` 收敛为 `[USDT, USDC]`。
   - `GreatLottoCoin.mint(... permit)` 中针对 DAI 的特殊分支（`token == _tokens[2]` → `selfPermitAllowedIfNecessary`）删除；permit 路径仅保留标准 EIP-2612 分支。
   - `SelfPermit` 删除 `selfPermitAllowed` / `selfPermitAllowedIfNecessary` 两个 DAI/CHAI 风格函数；`ISelfPermit` 同步收敛。
   - 删除 `interfaces/IERC20PermitAllowed.sol`（DAI/CHAI permit 专用接口）。
5. 三个仓库的 `openspec/specs/` 与文档同步刷新，避免 ETH / DAI 残影遗留。

### 非目标

- 不在合约层做"既兼容又屏蔽"的过渡逻辑（运行环境是新链全新部署，不存在已落账的 GLETH / 由 DAI 铸造的 GLC 余额需要保护）。
- 不替换 USDT / USDC 地址，不引入新的支付币种。
- 不调整 Pyth Entropy 异步开奖、刮刮卡奖品分布、彩票奖金算法等业务逻辑；本次仅做"币种通道收敛"。
- 不修改 `interface` 前端仓库 —— 该仓库的下线由前端侧另起 PR / change，本方案只更新它依赖的 ABI 输出。
- USDT 在以太坊主网 **不支持** EIP-2612 permit，下线 DAI 后用户走 USDT 路径仍需先 `approve` 再 mint；这与现状一致，不在本次改造范围内。

## 2. 影响面盘点（按仓库）

### 2.1 `infrastructure/`（基础设施层）

| 文件 | 处理 |
|---|---|
| `contracts/GreatLottoEth.sol` | **删除** |
| `contracts/interfaces/IGreatLottoEth.sol` | **删除** |
| `contracts/test/GreatLottoEthTest.sol` | **删除** |
| `contracts/test/PartnerTest.sol` | 删除 ETH 相关 mint 测试入口 |
| `contracts/DaoCoin.sol` | 删除 `coinPriceEth` / `mintToUser(... bool isEth)` / `changePrice(... bool isEth)` 中的 isEth 分支，函数签名收敛为单参数 |
| `contracts/interfaces/IDaoCoin.sol` | 同步 `event PriceChanged` / `mintToUser` / `changePrice` 签名 |
| `contracts/DaoBenefitPool.sol` | 构造函数去掉 `ethAddr`，改为只传 GLC + DaoCoin |
| `contracts/base/BenefitPoolBase.sol` | 删除 `GreatLottoEthAddress` / `GovernEthAddress` immutable，`executeBenefit` 去掉 `bool isEth` 入参 |
| `contracts/interfaces/IBenefitPoolBase.sol` | 同步 `event BenefitExecuted` / `executeBenefit` 签名 |
| `contracts/GreatLottoCoin.sol` | `_tokens` 数组移除 DAI 项（mainnet/sepolia 两套都改）；`mint(... permit)` 中 `if(token == _tokens[2])` 分支与 `selfPermitAllowedIfNecessary` 调用全部删除，统一走 `selfPermitIfNecessary` 标准 EIP-2612 路径 |
| `contracts/base/SelfPermit.sol` | 删除 `selfPermitAllowed` / `selfPermitAllowedIfNecessary`；删除 `import '../interfaces/IERC20PermitAllowed.sol'` |
| `contracts/interfaces/ISelfPermit.sol` | 同步删除两个 DAI/CHAI 风格函数声明 |
| `contracts/interfaces/IERC20PermitAllowed.sol` | **删除**（DAI/CHAI permit 专用接口已无消费方） |
| `ignition/modules/infrastructure.js` | 不再部署 `GreatLottoEth(Test)`；`DaoBenefitPool` 构造改为 `(greatLottoCoin, daoCoin)` |
| `test/runTest/*.js` | 删除 / 改写 ETH wrap/unwrap、isEth=true、DAI permit 相关用例；保留 USDT/USDC 用例 |
| `test/utils/getCoin.js` / `test/utils/permitUtils.js` / `test/scripts/initTestCoin.js` / `test/scripts/approveTestCoin.js` | 删除 `DAI_ADDRESS` / `getDAICoin` / `approveDAICoin` / `DAI_DECIMALS` / `DAI_ABI` 等 helper 与 fixture，permit util 中的 DAI 分支删除 |

> ⚠️ **`SelfPermit.selfPermit` / `selfPermitIfNecessary` 保留**：USDC（标准 ERC20Permit）仍依赖该路径。USDT 主网无 permit 支持，沿用 `approve` + `mint` 的两步流程，不在本次改造范围。
> ⚠️ **`_tokens` 索引收敛**：原 `_tokens[0..2] = [USDT, USDC, DAI]` → 收敛后 `_tokens[0..1] = [USDT, USDC]`。`mint` 中通过 `_tokens[2]` 索引 DAI 的硬编码分支同时删除。

> ⚠️ **DAI 影响仅限 infrastructure**：`GreatLottoCore` / `ScratchCard` 没有任何对 DAI 地址或 `selfPermitAllowed*` 的直接引用，它们经由 `GreatLottoCoin.checkToken` / `mint` 间接消费，因此 DAI 下线在两个下游仓库 **不需要单独的 OpenSpec change**——`GreatLottoCoin._tokens` 收敛后下游自然只接受 USDT/USDC。下游测试 fixture 中如有 DAI 入金辅助函数，由各自仓库的 ETH 下线 change 顺手清理。

### 2.2 `GreatLottoCore/`（彩票主合约）

| 文件 | 处理 |
|---|---|
| `contracts/InvestmentEth.sol` | **删除**（`GLIETH` ERC4626 vault）|
| `contracts/test/InvestmentEthTest.sol`、`test/GreatLottoEthTest2.sol` | **删除** |
| `contracts/GreatLotto.sol` | 删除 `GreatLottoEthAddress` immutable；`buyTicket` 路径不再判断 `isEth`；`quoteTicket(... bool isEth)` 收敛为单参数 |
| `contracts/PrizePool.sol` | 删除所有 `_normalPoolByEth` / `_rollupBalanceByEth` / `_totalDebtByEth` / `InvestmentEthAddress` / `_getInvestmentCoin(isEth)` / `X_BONUS_MAX_ETH` 双轨字段；`_colletWithCoin`、`lockPending`、`fulfillBonus`、`payDebt`、`getRollupBalance` 等签名去掉 `bool isEth` |
| `contracts/InvestmentBenefitPool.sol` | 构造函数去掉 `ethAddr` / `investmentEth` |
| `contracts/GreatLottoNFT.sol` | `Ticket.params.isEth` 字段移除 |
| `contracts/interfaces/IGreatLotto.sol` / `IGreatLottoNFT.sol` / `IPrizePool.sol` | 同步删除字段、event、function 签名中的 `isEth` |
| `contracts/libraries/NumberUtils.sol` | `quoteTicket(... bool isEth)` 删 ETH 价格分支 |
| `contracts/libraries/DrawUtils.sol` | `getRewardByList` / `getReward` 删 ETH 奖金分支 |
| `contracts/libraries/NFTTicket.sol` | SVG 渲染删除 `_getAmountStr(... isEth)`，统一稳定币精度 |
| `ignition/modules/GreatLottoCore.js` | 不再部署 `InvestmentEth`；`InvestmentBenefitPool` 构造收敛 |
| `test/runTest/*.js` | 删除 / 改写 isEth=true 相关用例；测试 fixture 中的 DAI helper（`getDAICoin` / `approveDAICoin` / `DAI_ADDRESS`）顺手清理 |

### 2.3 `ScratchCard/`（刮刮卡）

| 文件 | 处理 |
|---|---|
| `contracts/ScratchCard.sol` | 删除 `GreatLottoEthAddress` immutable；`_checkToken` 不再返回 `isEth`，仅校验 token 是否在 GLC 白名单；`PayoutPending` / `PayoutClaimed` / `_recordPendingPayout` / `claimPayout` / `pendingPayoutOf` / `pendingPayoutCoinOf` 删 `bool isEth` 入参与分支；只剩单条欠款映射 `_pendingPayouts[user]` |
| `contracts/base/PrizePool.sol` | `_setPrizePool` / `_payBonus` / `_afterCollectForBuy` 删 `isEth` 分支 |
| `contracts/base/PrizePoolBase.sol` | 删除 `GreatLottoEthAddress` / `_getCoin(isEth)` / `_getIsEth` / `_mintDaoCoinToPayer` 中的分支，固定为 GLC |
| `contracts/interfaces/IScratchCard.sol` | 4 个事件、`pendingPayoutCoinOf`、`PayoutPending/Claimed` 等删 `bool isEth`（事件仍可保留 `coin` indexed 参数用于前端筛选） |
| `contracts/interfaces/IScratchCardNFT.sol` | `CardParams.isEth` / `Card.isEth` 字段删除 |
| `contracts/ScratchCardNFT.sol` | `createCard` 中 `isEth: cardParams.isEth` 字段移除；`getCard` 返回结构变化 |
| `contracts/interfaces/IPrizePool.sol` | `CardParams` / `CollectForBuyParam` 等结构体的 `isEth` 字段移除 |
| `contracts/test/InfraImports.sol` | 不再 import `GreatLottoEth`、`GreatLottoEthTest` |
| `ignition/modules/ScratchCard.js` + `ignition/parameters/*.json` | 不再传 `greatLottoEthAddress` |
| `test/runTest/*.js` | 现有 55 个用例中所有 ETH 相关用例改写为稳定币；新增"ETH 路径已下线"的 revert 用例（如传入 GLETH 地址应 revert `ErrorUnsupportedToken`）|

## 3. 跨仓改造分阶段执行顺序

由于 `GreatLottoCore` / `ScratchCard` 通过 `@greatlotto/infrastructure` 直接 import 基础合约 + 接口，**必须按依赖顺序合并**：

```
infrastructure  →  GreatLottoCore + ScratchCard（可并行）
```

每个阶段都形成独立的 OpenSpec change proposal，独立 review、独立 archive。

### 阶段 A：infrastructure

**Change ID**：`remove-eth-payment-track`（同时承载 DAI 下线，不另建 change）

- proposal.md：阐述去 ETH + 去 DAI 决策与影响面（本文 §2.1）
- design.md：列出 `DaoCoin` / `DaoBenefitPool` / `BenefitPoolBase` / `GreatLottoCoin` / `SelfPermit` 的接口前后对比表（含 `_tokens` 数组前后对比、permit 分支收敛）
- specs/：因 `infrastructure/openspec/specs/` 当前为空，本次首次落入：
  - `coin-base-stable-only`（仅保留稳定币 mint/withdraw 路径的 SHALL 列表，并在此 capability 中明确 `_tokens = [USDT, USDC]` 的不变量）
  - `dao-benefit-pool-single-track`（单一资产币分润契约）
  - `dao-coin-pricing-single-track`（DaoCoin 单价格、单分支铸造契约）
  - `self-permit-eip2612-only`（SelfPermit 仅保留 EIP-2612 标准 permit 分支，删除 DAI/CHAI allowed-style permit）
- tasks.md：删除 GLETH/DAI → 接口收敛 → SelfPermit 收敛 → 测试改写 → ignition 与文档更新
- 验收：`npx hardhat test --network localhost test/runTest/*.js` 全绿、coverage ≥ 现状基线、`infrastructure.js` 模块本地部署成功；额外断言 `checkToken(USDT) && checkToken(USDC) && !checkToken(DAI)` 且任一调用 `selfPermitAllowed*` 的 selector 解析失败

### 阶段 B：GreatLottoCore

**Change ID**：`drop-eth-investment-and-prizepool-track`

- 依赖：阶段 A 的 npm 包发布到本地 workspace（pnpm workspace 已链接 `@greatlotto/infrastructure`）
- proposal.md：阐述对彩票主流程的影响（本文 §2.2）
- design.md：重点呈现 `PrizePool` 双轨 → 单轨的状态收敛（normalPool / rollup / totalDebt 各一份）、`Ticket.isEth` 删除对 NFT SVG 的影响、`X_BONUS_MAX` 仅保留稳定币上限
- specs/：
  - 修改 `prize-pool`：删除 `getRollupBalance(bool)` 等双参数 SHALL；新增"`PrizePool` 不再持有 GLETH，所有 deposit 路径 revert 非 GLC token"
  - 修改 `great-lotto`：`buyTicket` 不再返回 `isEth`、`quoteTicket` 单签名
  - 修改 `great-lotto-nft`：`Ticket` 结构体收敛
- tasks.md：先删 `InvestmentEth.sol` → 再删 `PrizePool` 双轨字段 → 最后改 `GreatLotto.sol` 入口 → 测试用例改写
- 验收：`npx hardhat test`、SVG snapshot 比对、合约大小不超 EIP-170

### 阶段 C：ScratchCard

**Change ID**：`drop-eth-from-scratchcard`

- 依赖：阶段 A 的接口落地；与阶段 B **并行**（`ScratchCard` 不依赖 `GreatLottoCore`）
- proposal.md：阐述对发卡 / 购卡 / 异步开奖的影响（本文 §2.3）
- design.md：
  - `Card.isEth` 字段删除是 `getCard` 返回结构变化，对 interface 仓库 ABI 是 Breaking
  - `pendingPayoutOf(user, isEth)` → `pendingPayoutOf(user)`，事件参数对应收敛
  - 与已 archive 的 `scratchcard-m2-issuer-queries` 的兼容性说明（M2 已落地的 `pendingPayoutCoinOf` 签名同步收敛）
- specs/：
  - 修改 `card-management`：删除 `Card.isEth`、`CardParams.isEth`，更新 `getCardOverview` 返回值描述
  - 修改 `card-events`：4 个事件参数收敛、`pendingPayoutCoinOf` 单参数签名
  - 修改 `draw-logic`：`_payBonus` / `_recordPendingPayout` / `claimFailedDraw` / `claimTimedOutDraw` 路径不再分叉
  - `entropy-randomness` / `multi-chain-deployment` 不变，仅做引用更新
- tasks.md：先 base/PrizePool* → 再 ScratchCardNFT → 再 ScratchCard → 测试用例 → ignition 参数表
- 验收：`npx hardhat test test/runTest/*.js`、合约大小检查、本地 fork 部署演练

## 4. Breaking Changes & 部署策略

| 维度 | 决策 |
|---|---|
| 链上合约 | **全新部署**，不做存储升级。原 GLETH / InvestmentEth / 双轨 PrizePool / DAI 入金路径在新链不存在历史余额。 |
| ABI | 输出新版本，interface 仓库 `src/app/abi/` 同步替换；老 ABI 不再保留。`SelfPermit` 的 `selfPermitAllowed` / `selfPermitAllowedIfNecessary` selector 从 ABI 中消失。 |
| 事件 topic | 因签名改变，topic hash 变化；前端 indexer / The Graph 子图需重建（由前端仓库另起 change） |
| 配置参数 | `ignition/parameters/*.json` 删除 `greatLottoEthAddress`，部署前由 owner 走 Safe 多签确认 |
| 支持币种 | `GreatLottoCoin._tokens` 收敛为 `[USDT, USDC]`；前端币种选择器、文案、文档（白皮书 `WhitePaper_*.md` 含 DAI 表述）同步刷新 |
| 测试网 | 先在 Holesky / Base Sepolia / Arbitrum Sepolia 走完整路演，再上主网 |

## 5. 风险与回滚

- **风险 1：DaoCoin 持有人在旧合约里有未提现 GLETH 收益。** 缓解：旧 `DaoBenefitPool` 不下架，新合约独立部署，旧账户在新链不复存在；新链初始化前确认 `DaoCoin` 是全新合约。
- **风险 2：测试覆盖率下降。** 缓解：删除 ETH / DAI 用例的同时为稳定币路径补"原 ETH 路径应 revert"、"传入 DAI 地址应 revert `ErrorUnsupportedToken`"、"调用 `selfPermitAllowed` selector 应 fallback 失败" 三类负向用例。
- **风险 3：interface 仓库未同步导致页面崩溃。** 缓解：三个 change 全部 archive 后再切前端 ABI，interface 仓库的下线 PR 引用本方案 ID 链；前端币种选择器同步移除 DAI option。
- **风险 4：DAI 与下游 fixture 解耦不彻底。** 缓解：`infrastructure/test/utils/getCoin.js` 的 DAI helper 是 `GreatLottoCore` / `ScratchCard` 测试间接依赖（通过 fork mainnet 取 DAI 余额）；本方案在阶段 A 一并清理这些 helper，下游仓库的 ETH 下线 change 在 tasks 中追加 "fixture 同步收敛" 子任务。
- **回滚**：每个 change proposal 在合并前都通过 OpenSpec workflow 留档（proposal/design/specs/tasks），revert 整个 PR 即可恢复双轨。**新链尚未上线主网时回滚成本最低，应在主网部署前完成全部三阶段验收。**

## 6. 三个 OpenSpec change 的入口

实施时按以下路径建立目录：

- `infrastructure/openspec/changes/remove-eth-payment-track/`
- `GreatLottoCore/openspec/changes/drop-eth-investment-and-prizepool-track/`
- `ScratchCard/openspec/changes/drop-eth-from-scratchcard/`

每个目录包含 `proposal.md` / `design.md` / `tasks.md` / `specs/<capability>/spec.md`，遵循各仓库 `openspec/AGENTS.md`（如存在）或 `openspec/config.yaml` 既定约定。三个 proposal 都需要在文首引用本文档（`infrastructure/doc/remove-eth-support-plan.md`）作为顶层依据。

## 7. 检查清单（合并前确认）

- [ ] 三个仓库的 `proposal.md` 已发起并通过 review
- [ ] `infrastructure` 已合并并发布到 workspace（pnpm link 自动同步），包含 DAI 下线
- [ ] `GreatLottoCore` / `ScratchCard` 两个 PR 在 CI 全绿后并行合并
- [ ] 三个仓库的 `CLAUDE.md` 同步更新（删除 `GLETH` / `isEth` / DAI 相关行）
- [ ] `infrastructure` 仓库白皮书 `WhitePaper_EN.md` / `WhitePaper_ZH.md` 中 DAI 表述刷新
- [ ] `interface` 仓库收到 ABI 更新后另起前端下线 PR（含币种选择器移除 DAI）
- [ ] 测试网部署演练通过后，再在 Safe 多签下确认主网部署
