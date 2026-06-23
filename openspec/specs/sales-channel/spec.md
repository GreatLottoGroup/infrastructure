# sales-channel Specification

## Purpose
TBD - created by syncing change sales-channel-accrual-withdraw. Update Purpose after archive.
## Requirements
### Requirement: 渠道注册

`SalesChannel` SHALL 提供 `registerChannel(string name, uint256 deadline) external returns (bool)`：以 `msg.sender` 为渠道地址登记，分配自增 `chnId`（从 1 起），存储 `ChannelInfo{ id, chn, name }`（无 `status` 字段），emit `SalesChannelRegistered(addr, id, name)`。同一地址重复注册 MUST revert `SalesChannelAlreadyExists(addr)`。受 `noDelegateCall` 与 `checkDeadline(deadline)` 守卫。

#### Scenario: 注册成功

- **WHEN** 一个未注册地址调用 `registerChannel("ch-A", futureDeadline)`
- **THEN** MUST 分配 `chnId`（首个为 1）并存储 `ChannelInfo{id, chn=msg.sender, name}`
- **AND** MUST emit `SalesChannelRegistered(msg.sender, chnId, "ch-A")`
- **AND** `getChannelById(chnId)` MUST 返回 `(msg.sender, "ch-A")`

#### Scenario: 重复注册 revert

- **GIVEN** 地址已注册
- **WHEN** 同一地址再次调用 `registerChannel`
- **THEN** MUST revert `SalesChannelAlreadyExists(msg.sender)`

#### Scenario: 经 delegatecall 调用 revert

- **WHEN** `registerChannel` 经 delegatecall 触发
- **THEN** MUST revert `NoDelegateCall.DelegateCalled`

### Requirement: 渠道改名

`SalesChannel` SHALL 提供 `changeChannelName(string name, uint256 deadline) external returns (bool)`：仅渠道注册地址可改自己的名称，emit `SalesChannelNameChanged(addr, id, name)`。地址未注册 MUST revert `SalesChannelNotExists(addr)`。不再有 `status` 禁用守卫。受 `noDelegateCall` 与 `checkDeadline` 守卫。

#### Scenario: 改名成功

- **GIVEN** `msg.sender` 已注册为 chnId
- **WHEN** 调用 `changeChannelName("renamed", futureDeadline)`
- **THEN** MUST 更新该 chnId 的 name 并 emit `SalesChannelNameChanged(msg.sender, chnId, "renamed")`

#### Scenario: 未注册地址改名 revert

- **WHEN** 未注册地址调用 `changeChannelName`
- **THEN** MUST revert `SalesChannelNotExists(msg.sender)`

### Requirement: 渠道查询视图（去 status）

`SalesChannel` SHALL 提供 `getChannelByAddr(address) returns (uint id, string name)` 与 `getChannelById(uint chnId) returns (address chn, string name)`，返回值均**不含** `status`。不存在时分别返回 `(0, "")` 与 `(address(0), "")`。`getChannelCount() returns (uint)` 返回已注册渠道总数（`_nextId - 1`）。

#### Scenario: 按地址查询已注册

- **GIVEN** alice 注册为 chnId 1，name "ch-A"
- **WHEN** 调用 `getChannelByAddr(alice)`
- **THEN** MUST 返回 `(1, "ch-A")`

#### Scenario: 按 id 查询不存在

- **WHEN** 调用 `getChannelById(999)`（未注册）
- **THEN** MUST 返回 `(address(0), "")`

#### Scenario: 计数

- **GIVEN** 已注册 2 个渠道
- **WHEN** 调用 `getChannelCount()`
- **THEN** MUST 返回 2

### Requirement: 渠道分页遍历

`SalesChannel` SHALL 提供 `getChannelsPaged(uint256 startId, uint256 count) external view returns (ChannelInfo[] memory)`，按 `chnId` 升序返回区间内渠道，单页上限常量 `MAX_CHANNEL_PAGE = 20`。`count > 20` MUST revert `SalesChannelPageTooLarge(count)`；`startId == 0` 规整为 1；`end = min(startId + count - 1, getChannelCount())`；`startId > end` 返回空数组；否则返回实际命中（长度可能 < count）。

#### Scenario: 正常分页

- **GIVEN** 已注册 5 个渠道
- **WHEN** 调用 `getChannelsPaged(2, 3)`
- **THEN** MUST 返回 chnId 2、3、4 的 `ChannelInfo`（长度 3，按 id 升序）

#### Scenario: 尾部裁剪

- **GIVEN** 已注册 5 个渠道
- **WHEN** 调用 `getChannelsPaged(4, 10)`（count ≤ 20）
- **THEN** MUST 返回 chnId 4、5 的 `ChannelInfo`（长度 2，按剩余裁剪）

#### Scenario: 超上限 revert

- **WHEN** 调用 `getChannelsPaged(1, 21)`
- **THEN** MUST revert `SalesChannelPageTooLarge(21)`

#### Scenario: 越界返回空

- **GIVEN** 已注册 5 个渠道
- **WHEN** 调用 `getChannelsPaged(6, 5)`
- **THEN** MUST 返回空数组

### Requirement: 权限模型与资产币托管

`SalesChannel` SHALL 继承 `AccessControlPartnerContract`（替换 `Ownable`），构造参数包含 GLC 资产币地址与 owner。`creditChannel` 入口 MUST 受 `PARTNER_CONTRACT_ROLE` 守护；治理（授角色）由 `DEFAULT_ADMIN_ROLE` 行使。合约托管 GLC，所有转账经 `SafeERC20`。

#### Scenario: 非 PARTNER 调 creditChannel revert

- **WHEN** 一个未被授予 `PARTNER_CONTRACT_ROLE` 的地址调用 `creditChannel(chnId, amount)`
- **THEN** MUST revert（AccessControl 未授权）

#### Scenario: 授予 PARTNER 后可记账

- **GIVEN** `DEFAULT_ADMIN_ROLE` 已给某 PrizePool 合约授 `PARTNER_CONTRACT_ROLE`
- **WHEN** 该 PrizePool 调用 `creditChannel(chnId, amount)`
- **THEN** MUST 成功记账

### Requirement: 渠道分润记账

`SalesChannel` SHALL 提供 `creditChannel(uint256 chnId, uint256 amount) external`（仅 `PARTNER_CONTRACT_ROLE`）：按 `chnId` 累加 `_accrued[chnId] += amount` 与全局 `_totalAccrued += amount`，emit `SalesChannelCredited(chnId, amount)`。

**前置条件（MUST，偿付能力依据）**：调用方（PARTNER PrizePool）MUST 在调用 `creditChannel` **之前**已把**等额** `amount` GLC `safeTransfer` 入本合约——记账与到账严格配套，二者不得分离调用。该耦合是偿付能力不变量 `balanceOf >= totalAccrued - totalWithdrawn` 成立的前提：`creditChannel` 抬高 `_totalAccrued` 而不自行收款，若调用方未先转入等额 GLC 将破坏不变量。`creditChannel` 本身**不**校验到账（信任 PARTNER），故 `PARTNER_CONTRACT_ROLE` MUST 只授予经审计、保证「先 transfer 后 credit、金额一致」的合约（如 `PrizePoolBase._channelBenefitTransfer`），绝不授予 EOA。

#### Scenario: 记账累加并 emit

- **GIVEN** PrizePool 已把 300 GLC 转入 SalesChannel
- **WHEN** PrizePool 调用 `creditChannel(1, 300)`
- **THEN** MUST `accruedOf(1)` 增加 300、`totalAccrued()` 增加 300
- **AND** MUST emit `SalesChannelCredited(1, 300)`

### Requirement: 渠道自提分润

`SalesChannel` SHALL 提供 `withdraw() external`（`noDelegateCall`）：以 `chnId = _channelAddress[msg.sender]` 解析调用方注册的 chnId（未注册者解析为 0），提取当前待提额 `pendingOf(chnId) = _accrued[chnId] - _withdrawn[chnId]` 全额到 `msg.sender` 自己（不接受任意 `to`）。待提为 0（含未注册者的 chnId 0，`pendingOf(0)` 恒为 0 因 `channelId == 0` 路径从不 `creditChannel`）MUST revert `SalesChannelNothingToWithdraw(chnId)`。MUST 先更新 `_withdrawn[chnId]` 与全局 `_totalWithdrawn`（CEI），再 `SafeERC20` 转账，emit `SalesChannelWithdrawn(chnId, msg.sender, amount)`。

#### Scenario: 提取成功

- **GIVEN** alice（chnId 1）`pendingOf(1) == 300`
- **WHEN** alice 调用 `withdraw()`
- **THEN** MUST 把 300 GLC 转给 alice
- **AND** MUST `withdrawnOf(1)` 增加 300、`pendingOf(1)` 归 0、`totalWithdrawn()` 增加 300
- **AND** MUST emit `SalesChannelWithdrawn(1, alice, 300)`

#### Scenario: 无待提 revert

- **GIVEN** alice（chnId 1）`pendingOf(1) == 0`
- **WHEN** alice 调用 `withdraw()`
- **THEN** MUST revert `SalesChannelNothingToWithdraw(1)`

#### Scenario: 非渠道地址提取 revert（chnId 零解析）

- **GIVEN** `msg.sender` 未注册任何渠道
- **WHEN** 调用 `withdraw()`
- **THEN** `_channelAddress[msg.sender]` 解析为 chnId 0，`pendingOf(0) == 0`
- **AND** MUST revert `SalesChannelNothingToWithdraw(0)`

### Requirement: 账本查询

`SalesChannel` SHALL 提供单渠道账本视图 `pendingOf(uint256 chnId) returns (uint256)`（= `_accrued - _withdrawn`）、`accruedOf(uint256 chnId) returns (uint256)`（累计入账含已提）、`withdrawnOf(uint256 chnId) returns (uint256)`（累计已提）；以及全局聚合 `totalAccrued() returns (uint256)`（仅 `creditChannel` 自增）、`totalWithdrawn() returns (uint256)`（仅 `withdraw` 自增）。

#### Scenario: 单渠道三口径一致

- **GIVEN** chnId 1 累计入账 500、已提 200
- **THEN** `accruedOf(1) == 500` AND `withdrawnOf(1) == 200` AND `pendingOf(1) == 300`

#### Scenario: 全局聚合恒等式

- **GIVEN** 任意 credit / withdraw 序列后
- **THEN** `totalAccrued() == Σ accruedOf(chnId)` AND `totalWithdrawn() == Σ withdrawnOf(chnId)`

### Requirement: 偿付能力不变量

`SalesChannel` 持有的 GLC 余额 SHALL 恒满足 `coin.balanceOf(SalesChannel) >= totalAccrued() - totalWithdrawn()`（全局待提总额），即合约始终有足额 GLC 兑付所有渠道待提分润。

#### Scenario: 任意操作序列后偿付能力成立

- **GIVEN** 任意 `creditChannel` / `withdraw` 操作序列（含多渠道交叉）
- **THEN** MUST 始终满足 `coin.balanceOf(SalesChannel) >= totalAccrued() - totalWithdrawn()`

### Requirement: 移除渠道状态干预

`SalesChannel` SHALL NOT 暴露 `disableChannel` / `enableChannel` 函数，SHALL NOT 暴露 `ChannelInfo.status` 字段，SHALL NOT 定义 `SalesChannelAlreadyDisabled` / `SalesChannelAlreadyEnabled` error 或 `SalesChannelDisabled` / `SalesChannelEnabled` event。

#### Scenario: disable/enable 已删除

- **WHEN** 调用方尝试调用 `disableChannel` 或 `enableChannel`
- **THEN** MUST 编译失败（函数不存在）

#### Scenario: status 字段已删除

- **WHEN** 调用方尝试读取 `ChannelInfo.status`
- **THEN** MUST 编译失败（字段不存在）；`getChannelById` / `getChannelByAddr` 返回值不含 status
