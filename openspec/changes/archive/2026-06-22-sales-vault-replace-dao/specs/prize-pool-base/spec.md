# prize-pool-base Specification

## MODIFIED Requirements

### Requirement: 暴露奖池配置 immutable 与分润率

`PrizePoolBase` SHALL 暴露 `GreatLottoCoinAddress`（资产币）/ `SalesVaultAddress`（销售利润金库）/ `SalesChannelAddress`（销售渠道注册表）三个 `address public immutable`，以及 `channelBenefitRate` / `sellBenefitRate` 两个 `uint16 public` 分润率（千分比，由构造参数初始化）。`PrizePoolBase` SHALL NOT 再暴露 `DaoCoinAddress` 或 `DaoBenefitPoolAddress`。

#### Scenario: 部署写入 immutable 与默认分润率

- **GIVEN** 部署参数 `(coin, salesVaultAddr, salesChannelAddr, _owner, initialChannelRate, initialSellRate)` 全部非零
- **WHEN** 子类合约部署
- **THEN** `GreatLottoCoinAddress()` MUST 返回 `coin`
- **AND** `SalesVaultAddress()` MUST 返回 `salesVaultAddr`
- **AND** `SalesChannelAddress()` MUST 返回 `salesChannelAddr`
- **AND** `channelBenefitRate()` MUST 返回 `initialChannelRate`
- **AND** `sellBenefitRate()` MUST 返回 `initialSellRate`

#### Scenario: 不再暴露 DAO 相关 immutable

- **WHEN** 任意调用方尝试读取 `DaoCoinAddress()` 或 `DaoBenefitPoolAddress()`
- **THEN** MUST 编译失败（这两个 getter 已删除）

#### Scenario: 构造写入由子类决定校验

- **WHEN** 子类构造时传入 `address(0)` 给任意 immutable 参数
- **THEN** `PrizePoolBase` 自身 MUST NOT 内置零地址校验（由子类按需添加），允许下游对部分地址保留可选语义

## ADDED Requirements

### Requirement: `_salesVaultTransfer` 销售金库打款

`PrizePoolBase` SHALL 提供 `_salesVaultTransfer(ICoinBase coin, uint256 benefit) internal`：等价于 `_transferTo(coin, SalesVaultAddress, benefit)`，作为语义化 sugar，把销售分润打入 `SalesVault`。该 helper 取代历史的 `_daoBenefitTransfer`。

#### Scenario: 金库打款

- **GIVEN** 合约余额 ≥ benefit
- **WHEN** `_salesVaultTransfer(coin, benefit)` 被调用
- **THEN** MUST 通过 `_transferTo(coin, SalesVaultAddress, benefit)` 把 benefit 打到销售金库
- **AND** 该转账抬高金库 `totalAssets`、不动其 `totalSupply`

#### Scenario: 历史 `_daoBenefitTransfer` 已删除

- **WHEN** 下游尝试调用 `_daoBenefitTransfer`
- **THEN** MUST 编译失败（已被 `_salesVaultTransfer` 取代）

### Requirement: `_distributeChannelAndSalesBenefits` 渠道+金库两段分润 pipeline

`PrizePoolBase` SHALL 提供 `_distributeChannelAndSalesBenefits(ICoinBase coin, uint amountByCoin, uint256 channelId) internal returns (uint netAmount)`：基于 `amountByCoin` 计算 `channelBenefit` 与 `sellBenefit`；当 `channelId > 0` 时把 `channelBenefit` 通过 `_channelBenefitTransfer` 打到对应渠道、`sellBenefit` 单独通过 `_salesVaultTransfer` 打到销售金库；当 `channelId == 0` 时把 `channelBenefit` 与 `sellBenefit` 合并通过 `_salesVaultTransfer` 打到销售金库。返回 `netAmount = amountByCoin - channelBenefit - sellBenefit`，由 caller 决定净值去向。该 helper 取代历史的 `_distributeChannelAndDaoBenefits`，计算逻辑与渠道档行为不变，仅 sell 档目标从 DAO 利润池改为销售金库。

#### Scenario: channelId > 0 时分别打款

- **GIVEN** `channelId > 0` 且对应渠道在 `SalesChannel` 中有效，合约 GLC 余额充足，`amountByCoin = 10000`，`channelBenefitRate = 30`，`sellBenefitRate = 70`
- **WHEN** 调用 `_distributeChannelAndSalesBenefits(coin, 10000, channelId)`
- **THEN** MUST 通过 `_channelBenefitTransfer(coin, 300, channelId)` 把 300 打到渠道地址
- **AND** MUST 通过 `_salesVaultTransfer(coin, 700)` 把 700 打到销售金库
- **AND** MUST 返回 `netAmount == 9000`

#### Scenario: channelId == 0 时合并打款

- **GIVEN** `channelId == 0`，合约 GLC 余额充足，`amountByCoin = 10000`，`channelBenefitRate = 30`，`sellBenefitRate = 70`
- **WHEN** 调用 `_distributeChannelAndSalesBenefits(coin, 10000, 0)`
- **THEN** MUST NOT 调用 `_channelBenefitTransfer`
- **AND** MUST 通过 `_salesVaultTransfer(coin, 1000)` 把 channel 与 sell 合并的 1000 打到销售金库
- **AND** MUST 返回 `netAmount == 9000`

#### Scenario: channelId > 0 但渠道无效时 revert

- **GIVEN** `channelId > 0` 但 `ISalesChannel.getChannelById(channelId)` 返回 `(status=false, chn=address(0), ...)`
- **WHEN** 调用 `_distributeChannelAndSalesBenefits(coin, 10000, channelId)`
- **THEN** MUST revert with `ISalesChannel.SalesChannelInvalid(address(0))`，整个交易回滚；销售金库余额不应被改动

#### Scenario: 合约余额不足时 revert

- **GIVEN** 合约 GLC 余额 < 应付的渠道分润或金库分润
- **WHEN** 调用 `_distributeChannelAndSalesBenefits(coin, amountByCoin, channelId)`
- **THEN** MUST revert with `ErrorInsufficientBalance`（来自下层 `_transferTo`）

#### Scenario: 两档分润率均为 0 时 net = amountByCoin

- **GIVEN** `channelBenefitRate == 0` 且 `sellBenefitRate == 0`
- **WHEN** 调用 `_distributeChannelAndSalesBenefits(coin, 10000, channelId)`，channelId 任意
- **THEN** MUST NOT 触发任何 `_transferTo`（对应 amount==0 早退）
- **AND** MUST 返回 `netAmount == 10000`

#### Scenario: 历史 `_distributeChannelAndDaoBenefits` 已删除

- **WHEN** 下游尝试调用 `_distributeChannelAndDaoBenefits`
- **THEN** MUST 编译失败（已被 `_distributeChannelAndSalesBenefits` 取代）

## REMOVED Requirements

### Requirement: `_mintDaoCoinToPayer` 增发 DAO 治理币

**Reason**: DAO 治理币机制整体移除——购买不再给买家增发 GLDC，`DaoCoin` 合约删除。

**Migration**: 下游 `PrizePool` 子类 MUST 删除对 `_mintDaoCoinToPayer(payer, amountByCoin)` 的调用（ScratchCard `_afterCollectForBuy` / GreatLottoCore `_collect`）。买家的购买收益不再以治理币份额体现；销售收益权改由 `SalesVault` 的 ERC4626 份额承载（见 `sales-vault` 能力）。

### Requirement: `_daoBenefitTransfer` DAO 利润池打款

**Reason**: DAO 利润池机制移除——分润目标从 `DaoBenefitPoolAddress` 改为 `SalesVaultAddress`。

**Migration**: 由 `_salesVaultTransfer(ICoinBase coin, uint256 benefit)`（见本能力 ADDED）取代，逻辑等价但目标地址改为销售金库。下游若直接引用 `_daoBenefitTransfer` MUST 改名。

### Requirement: `_distributeChannelAndDaoBenefits` 渠道+DAO 两段分润 pipeline

**Reason**: sell 档分润目标从 DAO 利润池改为销售金库；helper 随之改名以消除「Dao」误导。

**Migration**: 由 `_distributeChannelAndSalesBenefits(ICoinBase coin, uint amountByCoin, uint256 channelId)`（见本能力 ADDED）取代——计算逻辑与渠道档行为逐字不变，仅 sell 档（及无渠道时合并档）目标改为 `_salesVaultTransfer`。下游 ScratchCard `_afterCollectForBuy` / GreatLottoCore `_collect` MUST 改用新名。
