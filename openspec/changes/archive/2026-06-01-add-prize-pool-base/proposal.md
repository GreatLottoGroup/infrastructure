## Why

`ScratchCard` 与 `GreatLottoCore` 两个下游仓的奖池合约（`ScratchCard/contracts/base/PrizePoolBase.sol` 与 `GreatLottoCore/contracts/PrizePool.sol`）独立实现了几乎完全一致的"奖金池收款 / 分润 / 转账 / 治理币增发"工具集——7 个 helper 中约 80% 代码重复，且两份实现的安全语义存在不一致（如 `_transferTo` 一个有 fee-on-transfer 后置校验、另一个无；`_colletWithCoin` 一个 revert `amount==0`、另一个不 revert）。这种重复既增加了维护成本，也让安全语义在两条业务线漂移。把公共部分上移到 `@greatlotto/infrastructure` 作为抽象基类，可以一次定义、双方复用，并把更严格的安全语义统一到所有下游。

## What Changes

- **新增** `infrastructure/contracts/base/PrizePoolBase.sol`（abstract）：持有 4 个 immutable（`GreatLottoCoinAddress` / `DaoCoinAddress` / `DaoBenefitPoolAddress` / `SalesChannelAddress`）+ 2 档共有分润率（`channelBenefitRate` / `sellBenefitRate`）+ 8 个 internal helper（`_getCoin` / `_colletWithCoin × 2` / `_channelBenefitTransfer` / `_daoBenefitTransfer` / `_transferTo` / `_getBenefitByRate` / `_mintDaoCoinToPayer` / **`_distributeChannelAndDaoBenefits`**）+ **两个独立的分润率 setter**（`setChannelBenefitRate` / `setSellBenefitRate`），继承 `AccessControlPartnerContract`。
- **新增** `infrastructure/contracts/interfaces/IPrizePoolBase.sol`：`ChannelBenefitRateChanged(uint16 rate)` / `SellBenefitRateChanged(uint16 rate)` 两个事件 + `setChannelBenefitRate(uint16) external returns (bool)` / `setSellBenefitRate(uint16) external returns (bool)` 两个函数声明。
- **新增分润 pipeline helper** `_distributeChannelAndDaoBenefits(ICoinBase coin, uint amountByCoin, uint256 channelId) internal returns (uint netAmount)`：基类内部完成"按 channelId 是否 > 0 决定渠道分润是否打到对应渠道，否则与 sell 分润合并打入 DAO 利润池"的两段公共流程，返回扣除两档后的余额，让 caller 决定净值去向（ScratchCard 打给 creator / GreatLottoCore 入 normalPool）。
- **新增** `infrastructure/contracts/test/PrizePoolBaseHarness.sol`：仅测试用，把 internal helper 暴露为 external wrapper。
- **新增** `infrastructure/test/runTest/PrizePoolBase.test.js`：覆盖率 ≥ 95%，覆盖 7 个 helper 的正常路径与 revert 路径、`changeBenefitRate` 的权限与 rateType 校验。
- **统一安全语义**：
  - `_colletWithCoin` 内部 revert `amount==0`（深一层防御）
  - `_transferTo` 统一为「`amount==0` 早退 + 余额检查 + 后置 `ErrorPaymentUnsuccessful` 校验」
  - helper 可见性统一为 `internal`，让子类直接组合使用
- **构造参数化分润率**：base 不写死任何默认值，`channelBenefitRate` / `sellBenefitRate` 由下游构造时显式传入；避免偏向某一边的现状默认值。
- **拆分分润率 setter**：用 `setChannelBenefitRate` / `setSellBenefitRate` 两个独立函数替代历史上的 `changeBenefitRate(rateType, rate)` dispatch；下游若要新增档（如 invest）只需自加 setter，不再 override 已有函数。事件随之拆分为 `ChannelBenefitRateChanged` / `SellBenefitRateChanged` 以便链下精确订阅。**BREAKING（仅相对未部署的下游）**：ScratchCard / GreatLottoCore 主网均尚未部署，Phase 2 / 3 适配时同步替换 governance 调用约定即可。

不在本提案范围（待下游仓单独提案）：

- ScratchCard 仓适配（删除本地 `PrizePoolBase.sol` / `IPrizePoolBase.sol`，改 import 到 infra）。
- GreatLottoCore 仓适配（删除 `PrizePool.sol` 中重复的 private helper / immutable / 共有分润率，继承 `PrizePoolBase` 并 override `changeBenefitRate`）。

## Capabilities

### New Capabilities
- `prize-pool-base`: 抽象奖池基类，提供奖金池收款（GLC 直接转账 / 外币 mint / EIP-2612 permit）、分润计算、渠道与 DAO 利润池两段分润 pipeline、治理币增发等可组合的 internal helper，以及独立的渠道 / sell 分润率 setter。

### Modified Capabilities
（无）

## Impact

- **新增代码**：`infrastructure/contracts/base/PrizePoolBase.sol`（约 130 行）+ `infrastructure/contracts/interfaces/IPrizePoolBase.sol`（约 10 行）+ test harness 与单元测试。
- **依赖**：`@openzeppelin/contracts/token/ERC20/utils/SafeERC20`，以及 infra 内已有的 `ICoinBase` / `IDaoCoin` / `ISalesChannel` / `IErrorsBase` / `AccessControlPartnerContract`，不引入新的外部依赖。
- **下游仓**：本提案完成后，`ScratchCard` 与 `GreatLottoCore` 各起一个下游 change，分别 bump `@greatlotto/infrastructure` 版本并迁移到新基类。下游迁移属于工作区 pnpm 软链下的连续协作，不需要等 infra 发版。
- **链上行为**：本提案不修改任何已部署合约——仅在 infra 仓内新增可被未来部署引用的基类。
- **安全审计点**：基类汇集了所有奖池转账与分润路径，需在 Phase 1 内完成单元测试与 review 后再进入下游 Phase 2/3。
