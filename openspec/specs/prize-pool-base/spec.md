# prize-pool-base Specification

## Purpose
TBD - created by archiving change add-prize-pool-base. Update Purpose after archive.
## Requirements
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

### Requirement: `_getCoin` 返回资产币 ICoinBase

`PrizePoolBase` SHALL 提供 `_getCoin() internal view returns (ICoinBase)`，返回 `ICoinBase(GreatLottoCoinAddress)`。

#### Scenario: 视图调用

- **WHEN** 子类调用 `_getCoin()`
- **THEN** MUST 返回类型为 `ICoinBase` 的引用，其底层地址等于 `GreatLottoCoinAddress`

### Requirement: `_colletWithCoin` 收款（直接版）

`PrizePoolBase` SHALL 提供 `_colletWithCoin(address token, address payer, uint amount) internal returns (ICoinBase coin)`：当 `token == GreatLottoCoinAddress` 时调用 `coin.getAmount(amount)` 拿到底层小数额，再 `safeTransferFrom(payer, address(this), amount)`；否则调用 `coin.mint(token, amount, payer)`。

#### Scenario: amount == 0 拒绝

- **WHEN** `_colletWithCoin` 被调用且 `amount == 0`
- **THEN** MUST revert with `ErrorInvalidAmount(0)`

#### Scenario: GLC 路径

- **GIVEN** `token == GreatLottoCoinAddress` 且 `payer` 已对合约 approve 足量 GLC
- **WHEN** 子类调用 `_colletWithCoin(token, payer, amount)`
- **THEN** MUST 调用 `coin.getAmount(amount)` 转换金额
- **AND** MUST 通过 `safeTransferFrom(payer, address(this), 转换后金额)` 完成收款
- **AND** MUST 返回 `ICoinBase(GreatLottoCoinAddress)`

#### Scenario: 外币 mint 路径

- **GIVEN** `token != GreatLottoCoinAddress` 且 `token` 为 GLC 白名单内的稳定币
- **WHEN** 子类调用 `_colletWithCoin(token, payer, amount)`
- **THEN** MUST 调用 `coin.mint(token, amount, payer)` 完成外币换 GLC 入账
- **AND** MUST 返回 `ICoinBase(GreatLottoCoinAddress)`

### Requirement: `_colletWithCoin` 收款（permit 版）

`PrizePoolBase` SHALL 提供 `_colletWithCoin(address token, address payer, uint amount, uint deadline, uint8 v, bytes32 r, bytes32 s) internal returns (ICoinBase coin)`：GLC 路径在 allowance 不足时先调用 `coin.permit(...)` 再 `safeTransferFrom`；外币路径调用 `coin.mint(token, amount, payer, deadline, v, r, s)`。

#### Scenario: amount == 0 拒绝

- **WHEN** permit 版 `_colletWithCoin` 被调用且 `amount == 0`
- **THEN** MUST revert with `ErrorInvalidAmount(0)`

#### Scenario: GLC permit 路径 — allowance 不足时调用 permit

- **GIVEN** `token == GreatLottoCoinAddress` 且 `coin.allowance(payer, address(this)) < amount`
- **WHEN** 子类调用 permit 版 `_colletWithCoin`
- **THEN** MUST 先调用 `coin.permit(payer, address(this), amount, deadline, v, r, s)`
- **AND** 然后 MUST 调用 `safeTransferFrom(payer, address(this), 转换后金额)`

#### Scenario: GLC permit 路径 — allowance 已足够时跳过 permit

- **GIVEN** `token == GreatLottoCoinAddress` 且 `coin.allowance(payer, address(this)) >= amount`
- **WHEN** 子类调用 permit 版 `_colletWithCoin`
- **THEN** MUST NOT 调用 `coin.permit`
- **AND** 直接调用 `safeTransferFrom`

#### Scenario: 外币 permit mint 路径

- **GIVEN** `token != GreatLottoCoinAddress`
- **WHEN** 子类调用 permit 版 `_colletWithCoin`
- **THEN** MUST 调用 `coin.mint(token, amount, payer, deadline, v, r, s)`

### Requirement: `_transferTo` 严格不变量转账

`PrizePoolBase` SHALL 提供 `_transferTo(ICoinBase coin, address recipient, uint amount) internal`：amount==0 早退；余额不足 revert；`safeTransfer`；后置 strict equality 校验 `coin.balanceOf(address(this)) == _balance - amount`，任何偏差 revert `ErrorPaymentUnsuccessful`。该不变量同时 catch silent-fail 与 fee-on-transfer 两类异常代币。

#### Scenario: amount == 0 早退

- **WHEN** `_transferTo` 被调用且 `amount == 0`
- **THEN** MUST 立即返回，不读取余额、不调用 `safeTransfer`

#### Scenario: 余额不足 revert

- **GIVEN** `coin.balanceOf(address(this)) < amount` 且 `amount > 0`
- **WHEN** `_transferTo` 被调用
- **THEN** MUST revert with `ErrorInsufficientBalance(coin, address(this), balance, amount)`

#### Scenario: 正常转账成功

- **GIVEN** `coin` 为标准 ERC20，`coin.balanceOf(address(this)) >= amount > 0`
- **WHEN** `_transferTo(coin, recipient, amount)` 被调用
- **THEN** MUST 调用 `coin.safeTransfer(recipient, amount)`
- **AND** transfer 完成后 MUST 校验 `coin.balanceOf(address(this)) == _balance - amount`；满足时函数正常返回，recipient 余额增加 `amount`

#### Scenario: silent-fail token 触发后置校验

- **GIVEN** `coin` 的 `transfer` 返回 true 但实际未扣款（合约余额不变），即 transfer 后 `coin.balanceOf(address(this)) == _balance`
- **WHEN** `_transferTo` 调用 `safeTransfer` 完成
- **THEN** MUST revert with `ErrorPaymentUnsuccessful`（因为 `_balance != _balance - amount`，amount > 0）

#### Scenario: fee-on-transfer token 触发后置校验

- **GIVEN** `coin` 在 transfer 时多扣手续费 `fee > 0`，即 transfer 后 `coin.balanceOf(address(this)) == _balance - amount - fee`
- **WHEN** `_transferTo` 调用 `safeTransfer` 完成
- **THEN** MUST revert with `ErrorPaymentUnsuccessful`（因为 `_balance - amount - fee != _balance - amount`）

### Requirement: `_channelBenefitTransfer` 渠道分润打款

`PrizePoolBase` SHALL 提供 `_channelBenefitTransfer(ICoinBase coin, uint256 benefit, uint256 chnId) internal`：通过 `ISalesChannel(SalesChannelAddress).getChannelById(chnId)` 查询渠道；当且仅当 `status == false && chn == address(0)`（即渠道 id 完全不存在）时 revert；其它情况一律 `_transferTo(coin, chn, benefit)` 打款。

#### Scenario: id 不存在 revert

- **GIVEN** `ISalesChannel.getChannelById(chnId)` 返回 `(status=false, chn=address(0), ...)`
- **WHEN** `_channelBenefitTransfer` 被调用
- **THEN** MUST revert with `ISalesChannel.SalesChannelInvalid(address(0))`

#### Scenario: 有效启用渠道打款

- **GIVEN** `ISalesChannel.getChannelById(chnId)` 返回 `(status=true, chn=channelAddr, ...)` 且合约余额充足
- **WHEN** `_channelBenefitTransfer(coin, benefit, chnId)` 被调用
- **THEN** MUST 通过 `_transferTo(coin, channelAddr, benefit)` 完成打款

#### Scenario: 已停用但有地址的渠道仍打款

- **GIVEN** `ISalesChannel.getChannelById(chnId)` 返回 `(status=false, chn=channelAddr != address(0), ...)`（渠道历史存在但已 disable）
- **WHEN** `_channelBenefitTransfer(coin, benefit, chnId)` 被调用
- **THEN** MUST NOT revert；MUST 通过 `_transferTo(coin, channelAddr, benefit)` 把 benefit 打到该地址（沿用 ScratchCard 历史语义：仅 id 不存在才拒绝；停用的渠道地址依然收款，由治理层决定是否事后回收）

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

### Requirement: `_getBenefitByRate` 分润计算

`PrizePoolBase` SHALL 提供 `_getBenefitByRate(uint originAmount, uint16 benefitRate) internal pure returns (uint benefit, uint afterAmount)`：`benefit = originAmount * benefitRate / 1000`；`afterAmount = originAmount - benefit`。

#### Scenario: 标准分润

- **WHEN** `_getBenefitByRate(1000, 70)` 被调用
- **THEN** MUST 返回 `(70, 930)`

#### Scenario: rate == 0

- **WHEN** `_getBenefitByRate(1000, 0)` 被调用
- **THEN** MUST 返回 `(0, 1000)`

#### Scenario: rate == 1000（100%）

- **WHEN** `_getBenefitByRate(1000, 1000)` 被调用
- **THEN** MUST 返回 `(1000, 0)`

### Requirement: `setChannelBenefitRate` 治理 setter

`PrizePoolBase` SHALL 实现 `setChannelBenefitRate(uint16 rate) external virtual onlyRole(DEFAULT_ADMIN_ROLE) returns (bool)`：rate==0 revert；写入 `channelBenefitRate`；emit `ChannelBenefitRateChanged(rate)`；返回 `true`。实现 SHALL NOT 校验 `channelBenefitRate + sellBenefitRate ≤ 1000`——由治理层保证两档之和不超过 100%；超过时 `_distributeChannelAndDaoBenefits` 会在下次调用时 underflow revert，是已知 governance footgun。

#### Scenario: 非 DEFAULT_ADMIN_ROLE 拒绝

- **GIVEN** caller 不持有 `DEFAULT_ADMIN_ROLE`
- **WHEN** `setChannelBenefitRate(40)` 被调用
- **THEN** MUST revert with `AccessControlUnauthorizedAccount(caller, DEFAULT_ADMIN_ROLE)`

#### Scenario: rate == 0 拒绝

- **WHEN** admin 调用 `setChannelBenefitRate(0)`
- **THEN** MUST revert with `ErrorInvalidAmount(0)`

#### Scenario: 成功更新

- **WHEN** admin 调用 `setChannelBenefitRate(40)`
- **THEN** `channelBenefitRate()` MUST 返回 `40`
- **AND** MUST emit `ChannelBenefitRateChanged(40)`
- **AND** 函数 MUST 返回 `true`

### Requirement: `setSellBenefitRate` 治理 setter

`PrizePoolBase` SHALL 实现 `setSellBenefitRate(uint16 rate) external virtual onlyRole(DEFAULT_ADMIN_ROLE) returns (bool)`：rate==0 revert；写入 `sellBenefitRate`；emit `SellBenefitRateChanged(rate)`；返回 `true`。实现 SHALL NOT 校验 `channelBenefitRate + sellBenefitRate ≤ 1000`——治理层负责保证两档之和不超过 100%（同 `setChannelBenefitRate`）。

#### Scenario: 非 DEFAULT_ADMIN_ROLE 拒绝

- **GIVEN** caller 不持有 `DEFAULT_ADMIN_ROLE`
- **WHEN** `setSellBenefitRate(80)` 被调用
- **THEN** MUST revert with `AccessControlUnauthorizedAccount(caller, DEFAULT_ADMIN_ROLE)`

#### Scenario: rate == 0 拒绝

- **WHEN** admin 调用 `setSellBenefitRate(0)`
- **THEN** MUST revert with `ErrorInvalidAmount(0)`

#### Scenario: 成功更新

- **WHEN** admin 调用 `setSellBenefitRate(80)`
- **THEN** `sellBenefitRate()` MUST 返回 `80`
- **AND** MUST emit `SellBenefitRateChanged(80)`
- **AND** 函数 MUST 返回 `true`

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

