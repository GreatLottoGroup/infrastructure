# prize-pool-base Specification (delta)

## ADDED Requirements

### Requirement: `_payoutTransfer` 自调用隔离转账

`PrizePoolBase` SHALL 提供 `_payoutTransfer(address to, uint256 amount) external`：守卫 `msg.sender == address(this)`，仅允许本合约经 `this._payoutTransfer(...)` 自调用；通过后执行 `_transferTo(_getCoin(), to, amount)`。该函数 MUST 为 `external`（制造独立 message-call frame 以隔离调用方 catch 的回滚边界），MUST NOT 被改为 `internal`/`public`-直调，MUST NOT 被外部 EOA 或其它合约直接调用。

#### Scenario: 外部直调被守卫拒绝

- **GIVEN** 任意 `msg.sender != address(this)`（EOA 或第三方合约）
- **WHEN** 直接调用 `_payoutTransfer(to, amount)`
- **THEN** MUST revert with `ErrorUnauthorizedSelfCall`
- **AND** MUST NOT 发生任何转账

#### Scenario: 本合约自调用执行转账

- **GIVEN** 调用经 `this._payoutTransfer(to, amount)` 发起，故 `msg.sender == address(this)`，且合约余额充足
- **WHEN** `_payoutTransfer` 执行
- **THEN** MUST 调用 `_transferTo(_getCoin(), to, amount)` 完成转账（含 `_transferTo` 的余额检查与 strict-equality 后置校验）

### Requirement: `_softPay` 软付款兜底

`PrizePoolBase` SHALL 提供 `_softPay(address to, uint256 amount) internal`：经 `try this._payoutTransfer(to, amount) {} catch { _recordPendingPayout(to, amount); }` 实现。转账成功则直接完成；转账失败（含收款方 revert、代币黑名单、`_transferTo` 后置校验失败等任意 revert）时，资金留存合约内并调用 `_recordPendingPayout(to, amount)` 转 pull 兜底。`_softPay` MUST NOT revert（push 失败不传播）。调用方 MUST 在调用 `_softPay` **之前**完成自身账本扣减（CEI），使「账本扣一次 + 兜底记一次」在 push 失败时仍配平。

#### Scenario: push 成功直接付款

- **GIVEN** `to` 可正常收款，合约余额 ≥ `amount > 0`
- **WHEN** 调用 `_softPay(to, amount)`
- **THEN** MUST 经独立 frame 完成 `_transferTo` 转账
- **AND** MUST NOT 调用 `_recordPendingPayout`
- **AND** `pendingPayoutOf(to)` MUST 不变

#### Scenario: push 失败转兜底且不 revert

- **GIVEN** `to` 为会 revert 的合约（或触发任意转账失败），调用方已先行扣减自身账本
- **WHEN** 调用 `_softPay(to, amount)`
- **THEN** MUST NOT revert
- **AND** MUST 调用 `_recordPendingPayout(to, amount)`，使 `pendingPayoutOf(to)` 增加 `amount`
- **AND** 资金 MUST 留存合约内（`balanceOf` 不变）

#### Scenario: amount == 0 视为成功不记兜底

- **WHEN** 调用 `_softPay(to, 0)`
- **THEN** `_transferTo` 早退、`_payoutTransfer` 正常返回（不 revert）
- **AND** MUST NOT 调用 `_recordPendingPayout`

### Requirement: 兜底欠款聚合 `pendingPayoutTotal`

`PrizePoolBase` SHALL 维护私有聚合 `_pendingPayoutTotal`：在 `_recordPendingPayout(user, amount)` 内 `+= amount`、在 `claimPayout()` 成功提取时 `-= amount`，使其恒等于「当前滞留合约内、尚未被 claim 的兜底欠款总额」。SHALL 暴露 `pendingPayoutTotal() public view returns (uint256)` 返回该聚合，供下游把滞留兜底资金纳入余额不变量。`_recordPendingPayout` / `claimPayout` / `pendingPayoutOf` 的既有签名、事件与对外行为 MUST 保持不变。

#### Scenario: 记账自增

- **GIVEN** 初始 `pendingPayoutTotal() == P`
- **WHEN** `_recordPendingPayout(user, amount)` 被调用（amount > 0）
- **THEN** `pendingPayoutTotal()` MUST 返回 `P + amount`
- **AND** `pendingPayoutOf(user)` MUST 同步增加 `amount`
- **AND** MUST emit `PayoutPending(user, GreatLottoCoinAddress, amount)`（事件不变）

#### Scenario: claim 自减配平

- **GIVEN** `pendingPayoutOf(user) == amount > 0` 且 `pendingPayoutTotal() == P`（P ≥ amount）
- **WHEN** `user` 调用 `claimPayout()`
- **THEN** `pendingPayoutOf(user)` MUST 归 0
- **AND** `pendingPayoutTotal()` MUST 返回 `P - amount`
- **AND** 合约 `balanceOf` 减少 `amount`（聚合与余额同步下降，外部余额不变量守恒）

#### Scenario: 无兜底时为 0

- **GIVEN** 从未发生 `_recordPendingPayout`
- **WHEN** 读取 `pendingPayoutTotal()`
- **THEN** MUST 返回 `0`

## MODIFIED Requirements

### Requirement: `IPrizePoolBase` 接口

`infrastructure` SHALL 提供 `IPrizePoolBase` 接口声明：

- 事件 `ChannelBenefitRateChanged(uint16 rate)`
- 事件 `SellBenefitRateChanged(uint16 rate)`
- 错误 `ErrorUnauthorizedSelfCall`（供 `_payoutTransfer` 自调用守卫使用，下游不再各自定义本地副本）
- 函数 `setChannelBenefitRate(uint16 rate) external returns (bool)`
- 函数 `setSellBenefitRate(uint16 rate) external returns (bool)`

`PrizePoolBase` MUST 通过 `is IPrizePoolBase` 实现该接口。`IPrizePoolBase` MUST NOT 包含历史的 `BenefitRateChanged(uint8, uint16)` 事件或 `changeBenefitRate(uint8, uint16)` 函数声明（已被取代）。

#### Scenario: 事件声明对齐

- **WHEN** 任意子类合约 emit `ChannelBenefitRateChanged(rate)` 或 `SellBenefitRateChanged(rate)`
- **THEN** 事件签名 MUST 与 `IPrizePoolBase` 中声明的完全一致（`uint16 rate` 参数，无 indexed）

#### Scenario: 接口可被下游引用

- **WHEN** ScratchCard 或 GreatLottoCore 仓 import `@greatlotto/infrastructure/contracts/interfaces/IPrizePoolBase.sol`
- **THEN** MUST 能在不依赖 `PrizePoolBase` 实现的前提下编译通过

#### Scenario: 不再暴露历史聚合 setter

- **WHEN** 任意调用方尝试通过 `IPrizePoolBase` 调用 `changeBenefitRate(uint8, uint16)`
- **THEN** MUST 编译失败（接口不再声明该函数）

#### Scenario: `ErrorUnauthorizedSelfCall` 由接口统一提供

- **WHEN** 下游合约（如 ScratchCard `PrizePool`）需要引用 `ErrorUnauthorizedSelfCall`
- **THEN** MUST 经 `IPrizePoolBase`（由 `PrizePoolBase` 继承）获得，MUST NOT 再在下游本地重复定义同名 error
