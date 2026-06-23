## MODIFIED Requirements

### Requirement: `_channelBenefitTransfer` 渠道分润打款

`PrizePoolBase` SHALL 提供 `_channelBenefitTransfer(ICoinBase coin, uint256 benefit, uint256 chnId) internal`：通过 `ISalesChannel(SalesChannelAddress).getChannelById(chnId)`（返回 `(address chn, string name)`，已去 `status`）查询渠道；当且仅当 `chn == address(0)`（即渠道 id 不存在）时 revert `ISalesChannel.SalesChannelInvalid(address(0))`。其它情况：当 `benefit == 0` 时早退、不转账不记账；当 `benefit > 0` 时 MUST **先** `_transferTo(coin, SalesChannelAddress, benefit)` 把**等额** benefit 转入 `SalesChannel` 合约，**再**调 `ISalesChannel(SalesChannelAddress).creditChannel(chnId, benefit)` 按 `chnId` 记同等额。转账与记账金额 MUST 相等、顺序 MUST 为「先转账后记账」——这是 `SalesChannel` 偿付能力不变量的前提（见 sales-channel spec「渠道分润记账」前置条件）。分润不再直接 push 给渠道 EOA，改由渠道方经 `SalesChannel.withdraw` 自提（pull payment）。

#### Scenario: id 不存在 revert

- **GIVEN** `ISalesChannel.getChannelById(chnId)` 返回 `(chn=address(0), ...)`
- **WHEN** `_channelBenefitTransfer` 被调用
- **THEN** MUST revert with `ISalesChannel.SalesChannelInvalid(address(0))`

#### Scenario: 有效渠道转入 SalesChannel 并记账

- **GIVEN** `ISalesChannel.getChannelById(chnId)` 返回 `(chn=channelAddr != address(0), ...)`，`benefit > 0`，合约 GLC 余额充足
- **WHEN** `_channelBenefitTransfer(coin, benefit, chnId)` 被调用
- **THEN** MUST 通过 `_transferTo(coin, SalesChannelAddress, benefit)` 把 benefit 转入 SalesChannel 合约
- **AND** MUST 调用 `ISalesChannel(SalesChannelAddress).creditChannel(chnId, benefit)` 记账
- **AND** MUST NOT 直接 `_transferTo` 到渠道 EOA

#### Scenario: benefit 为 0 时早退

- **GIVEN** `ISalesChannel.getChannelById(chnId)` 返回有效渠道（`chn != address(0)`）但 `benefit == 0`
- **WHEN** `_channelBenefitTransfer(coin, 0, chnId)` 被调用
- **THEN** MUST NOT 转账、MUST NOT 调用 `creditChannel`、MUST NOT revert

### Requirement: `_distributeChannelAndSalesBenefits` 渠道+金库两段分润 pipeline

`PrizePoolBase` SHALL 提供 `_distributeChannelAndSalesBenefits(ICoinBase coin, uint amountByCoin, uint256 channelId) internal returns (uint netAmount)`：基于 `amountByCoin` 计算 `channelBenefit` 与 `sellBenefit`；当 `channelId > 0` 时把 `channelBenefit` 通过 `_channelBenefitTransfer`（转入 SalesChannel 合约并 `creditChannel` 记账）处理、`sellBenefit` 单独通过 `_salesVaultTransfer` 打到销售金库；当 `channelId == 0` 时把 `channelBenefit` 与 `sellBenefit` 合并通过 `_salesVaultTransfer` 打到销售金库。返回 `netAmount = amountByCoin - channelBenefit - sellBenefit`，由 caller 决定净值去向。计算逻辑与 channelId 分支结构不变，仅渠道档收款方从「渠道 EOA」改为「SalesChannel 合约记账」。

#### Scenario: channelId > 0 时分别打款

- **GIVEN** `channelId > 0` 且对应渠道在 `SalesChannel` 中有效，合约 GLC 余额充足，`amountByCoin = 10000`，`channelBenefitRate = 30`，`sellBenefitRate = 70`
- **WHEN** 调用 `_distributeChannelAndSalesBenefits(coin, 10000, channelId)`
- **THEN** MUST 通过 `_channelBenefitTransfer(coin, 300, channelId)` 把 300 转入 SalesChannel 并经 `creditChannel(channelId, 300)` 记账
- **AND** MUST 通过 `_salesVaultTransfer(coin, 700)` 把 700 打到销售金库
- **AND** MUST 返回 `netAmount == 9000`

#### Scenario: channelId == 0 时合并打款

- **GIVEN** `channelId == 0`，合约 GLC 余额充足，`amountByCoin = 10000`，`channelBenefitRate = 30`，`sellBenefitRate = 70`
- **WHEN** 调用 `_distributeChannelAndSalesBenefits(coin, 10000, 0)`
- **THEN** MUST NOT 调用 `_channelBenefitTransfer`
- **AND** MUST 通过 `_salesVaultTransfer(coin, 1000)` 把 channel 与 sell 合并的 1000 打到销售金库
- **AND** MUST 返回 `netAmount == 9000`

#### Scenario: channelId > 0 但渠道无效时 revert

- **GIVEN** `channelId > 0` 但 `ISalesChannel.getChannelById(channelId)` 返回 `(chn=address(0), ...)`
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
