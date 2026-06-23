## 1. ISalesChannel 接口收窄 + 扩展（infrastructure）

- [x] 1.1 `ChannelInfo` 删除 `status` 字段（保留 `id` / `chn` / `name`）
- [x] 1.2 删除 error `SalesChannelAlreadyDisabled` / `SalesChannelAlreadyEnabled`；新增 `SalesChannelPageTooLarge(uint256)` / `SalesChannelNothingToWithdraw(uint256)`
- [x] 1.3 删除 event `SalesChannelDisabled` / `SalesChannelEnabled`；新增 `SalesChannelCredited(uint256 indexed id, uint256 amount)` / `SalesChannelWithdrawn(uint256 indexed id, address indexed chn, uint256 amount)`
- [x] 1.4 视图 getter 签名收窄：`getChannelByAddr → (uint, string)`、`getChannelById → (address, string)`；删除 `disableChannel` / `enableChannel`
- [x] 1.5 新增函数声明：`getChannelsPaged` / `creditChannel` / `withdraw` / `pendingOf` / `accruedOf` / `withdrawnOf` / `totalAccrued` / `totalWithdrawn`

## 2. SalesChannel 合约重构（infrastructure）

- [x] 2.1 基类从 `Ownable` 迁到 `AccessControlPartnerContract`；构造新增 GLC 资产币地址参数（D1）
- [x] 2.2 删除 `disableChannel` / `enableChannel` 及 `_channel[chnId].status` 全部读写；`changeChannelName` 去 status 守卫
- [x] 2.3 `registerChannel` 写入去 `status` 的 `ChannelInfo`；`getChannelByAddr` / `getChannelById` 返回值去 status，存在性判据改 `chn == address(0)`（D6）
- [x] 2.4 实现 `getChannelsPaged(startId, count)`：`MAX_CHANNEL_PAGE = 20` 常量、count>20 revert、startId==0 规整为 1、尾部裁剪、越界返回空（D8）
- [x] 2.5 新增账本 storage：`_accrued` / `_withdrawn`（按 chnId）+ `_totalAccrued` / `_totalWithdrawn`（全局）
- [x] 2.6 实现 `creditChannel(chnId, amount)`（`onlyRole(PARTNER_CONTRACT_ROLE)`）：累加 `_accrued` + `_totalAccrued`，emit `SalesChannelCredited`
- [x] 2.7 实现 `withdraw()`（`noDelegateCall`）：解析 msg.sender 的 chnId、强制提到自己、CEI 先记账后 `SafeERC20` 转账、0 待提 revert、emit `SalesChannelWithdrawn`（D4）
- [x] 2.8 实现账本视图 `pendingOf` / `accruedOf` / `withdrawnOf` / `totalAccrued` / `totalWithdrawn`

## 3. PrizePoolBase 改写（infrastructure）

- [x] 3.1 `_channelBenefitTransfer` 解构改 `(address chn, ) = getChannelById(chnId)`，存在性判据 `chn == address(0)` 才 revert（D6）
- [x] 3.2 `_channelBenefitTransfer`：`benefit == 0` 早退（D5）；否则 `_transferTo(coin, SalesChannelAddress, benefit)` + `creditChannel(chnId, benefit)`
- [x] 3.3 复核 `_distributeChannelAndSalesBenefits` 调用点不变（仅被调函数内部行为改变）

## 4. infrastructure 测试

- [x] 4.1 重写 `test/foundry/SalesChannel.t.sol`：register / changeName / 分页（正常/尾裁/超限/越界）/ creditChannel 访问控制 / withdraw（成功/0待提/非渠道）/ 账本视图；删 disable/enable 用例
- [x] 4.2 改 `test/foundry/PrizePoolBase.t.sol` + harness：渠道分润断言收款方→SalesChannel + `creditChannel` 记账；benefit==0 早退；id 不存在 revert
- [x] 4.3 新增 SalesChannel 偿付能力 invariant：`balanceOf >= totalAccrued - totalWithdrawn`，恒等式 `totalAccrued == Σ accruedOf` / `totalWithdrawn == Σ withdrawnOf`（D7）；invariant handler 须遵守「先 transfer 后 credit、等额」前置条件以反映真实调用约束
- [x] 4.4 withdraw 未注册者用例：`_channelAddress[msg.sender]==0` → `pendingOf(0)==0` → revert `SalesChannelNothingToWithdraw(0)`（零解析显式覆盖）
- [x] 4.5 `forge test` 全绿 + `forge coverage` 不低于现状

## 5. 下游 ScratchCard 适配

- [x] 5.1 重编译 + `forge test` 全绿（无源码改动）
- [x] 5.2 `test/foundry/PrizePool.t.sol` 分润断言改写：渠道收款方→SalesChannel 合约 + `pendingOf` 增长
- [x] 5.3 部署模块：部署后给 ScratchCard `PrizePool` 授 SalesChannel 的 `PARTNER_CONTRACT_ROLE`
- [x] 5.4 本地部署补授（D2）：`ignition/modules/ScratchCardLocal.js` 加 SalesChannel 部署 + grantRole；`ignition/parameters/localhost.json` 补 SalesChannel/GLC 地址参数

## 6. 下游 GreatLottoCore 适配

- [x] 6.1 重编译 + `forge test` 全绿（无源码改动）
- [x] 6.2 `test/foundry/PrizePool.t.sol` 分润断言改写：渠道收款方→SalesChannel + `pendingOf` 增长
- [x] 6.3 部署模块：部署后给 GreatLottoCore `PrizePool` 授 SalesChannel 的 `PARTNER_CONTRACT_ROLE`
- [x] 6.4 本地部署补授（D2）：本地部署模块加 SalesChannel grantRole + 参数文件补地址

## 7. interface 适配

- [x] 7.1 `abi/SalesChannel.json` 从 artifacts 重新同步
- [x] 7.2 `hooks/contracts/SalesChannel.js`：删 `disableChannel` / `enableChannel` / `statusEl`；加 `getChannelsPaged` / `withdraw` / `pendingOf` / `accruedOf` / `withdrawnOf` / `totalAccrued` / `totalWithdrawn`；`getChannelByAddr` / `getChannelById` 返回值去 status 解构
- [x] 7.3 渠道页（`launch/channel/`）：渠道列表改分页遍历；渠道详情加「待提收益 + 提取按钮」；移除启用/禁用 UI

## 8. Review 三道门 + 收尾

- [x] 8.1 `openspec validate sales-channel-accrual-withdraw` 通过
- [x] 8.2 方案 review `/flow-review-spec`（6 维）
- [x] 8.3 代码 review `requesting-code-review`
- [x] 8.4 安全 review `/security-review`（合约仓必跑）
- [x] 8.5 合约体积复核（EIP-170 内）
