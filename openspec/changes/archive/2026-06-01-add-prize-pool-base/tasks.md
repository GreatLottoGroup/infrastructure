## 1. 接口与基类骨架

- [x] 1.1 新增 `contracts/interfaces/IPrizePoolBase.sol`：声明 `event ChannelBenefitRateChanged(uint16 rate)` / `event SellBenefitRateChanged(uint16 rate)` 与 `function setChannelBenefitRate(uint16 rate) external returns (bool)` / `function setSellBenefitRate(uint16 rate) external returns (bool)`（不再包含历史的 `BenefitRateChanged` / `changeBenefitRate`）
- [x] 1.2 新增 `contracts/base/PrizePoolBase.sol` 文件骨架：`abstract contract PrizePoolBase is AccessControlPartnerContract, IPrizePoolBase`，import `SafeERC20` / `ICoinBase` / `IDaoCoin` / `ISalesChannel` / `AccessControlPartnerContract`
- [x] 1.3 声明 4 个 `address public immutable`（`GreatLottoCoinAddress` / `DaoCoinAddress` / `DaoBenefitPoolAddress` / `SalesChannelAddress`）与 2 个 `uint16 public`（`channelBenefitRate` / `sellBenefitRate`）storage
- [x] 1.4 实现构造函数 `constructor(address coin, address daoCoinAddr, address daoBenefitPoolAddr, address salesChannelAddr, address _owner, uint16 initialChannelRate, uint16 initialSellRate) AccessControlPartnerContract(_owner)`，按入参写入 6 个状态变量

## 2. Internal helpers

- [x] 2.1 实现 `_getCoin() internal view returns (ICoinBase)`
- [x] 2.2 实现 `_colletWithCoin(address token, address payer, uint amount) internal returns (ICoinBase coin)`：amount==0 revert `ErrorInvalidAmount(0)`；GLC 路径走 `coin.getAmount` + `safeTransferFrom`；外币路径走 `coin.mint(token, amount, payer)`
- [x] 2.3 实现 `_colletWithCoin` permit 重载（带 `deadline, v, r, s`）：amount==0 revert；GLC 路径在 `allowance < amount` 时先 `coin.permit(...)` 再 `safeTransferFrom`；外币路径走 `coin.mint(token, amount, payer, deadline, v, r, s)`
- [x] 2.4 实现 `_transferTo(ICoinBase coin, address recipient, uint amount) internal`：amount==0 早退；`balanceOf < amount` revert `ErrorInsufficientBalance`；`safeTransfer`；后置 **strict equality** 校验 `coin.balanceOf(address(this)) != _balance - amount` 时 revert `ErrorPaymentUnsuccessful`（同时 catch silent-fail 与 fee-on-transfer 两类异常）
- [x] 2.5 实现 `_channelBenefitTransfer(ICoinBase coin, uint256 benefit, uint256 chnId) internal`：调 `ISalesChannel.getChannelById`；`status==false && chn==address(0)` revert `ISalesChannel.SalesChannelInvalid(chn)`；否则 `_transferTo(coin, chn, benefit)`
- [x] 2.6 实现 `_daoBenefitTransfer(ICoinBase coin, uint256 benefit) internal`：直接 `_transferTo(coin, DaoBenefitPoolAddress, benefit)`
- [x] 2.7 实现 `_getBenefitByRate(uint originAmount, uint16 benefitRate) internal pure returns (uint benefit, uint afterAmount)`：`benefit = originAmount * benefitRate / 1000`；`afterAmount = originAmount - benefit`
- [x] 2.8 实现 `_mintDaoCoinToPayer(address payer, uint256 assets) internal`：`IDaoCoin(DaoCoinAddress).mintToUser(payer, assets)`
- [x] 2.9 实现 `_distributeChannelAndDaoBenefits(ICoinBase coin, uint amountByCoin, uint256 channelId) internal returns (uint netAmount)`：
  - 用 `_getBenefitByRate(amountByCoin, channelBenefitRate)` / `_getBenefitByRate(amountByCoin, sellBenefitRate)` 算 `channelBenefit` / `sellBenefit`
  - 若 `channelId > 0`：调 `_channelBenefitTransfer(coin, channelBenefit, channelId)`；`daoBenefit = sellBenefit`
  - 否则：`daoBenefit = sellBenefit + channelBenefit`（不调 `_channelBenefitTransfer`）
  - 若 `daoBenefit > 0`：调 `_daoBenefitTransfer(coin, daoBenefit)`（注意：`_transferTo` 已在 amount==0 时早退，但此处显式 if 可省一次 SLOAD/`balanceOf`）
  - 返回 `netAmount = amountByCoin - channelBenefit - sellBenefit`
- [x] 2.10 NatSpec：说明返回 `netAmount` 的含义、channelId 语义、调用方需保证合约 GLC 余额足够覆盖应付分润

## 3. 治理 setter（拆分）

- [x] 3.1 实现 `function setChannelBenefitRate(uint16 rate) external virtual onlyRole(DEFAULT_ADMIN_ROLE) returns (bool)`：rate==0 revert `ErrorInvalidAmount(0)`；写入 `channelBenefitRate`；emit `ChannelBenefitRateChanged(rate)`；返回 `true`
  - 注意：仅来自 interface 的函数实现**不需要** `override(IPrizePoolBase)`（Solidity 0.8 中 interface 函数无 implementation 可被 override，加 `override` 会编译报错）；`virtual` 留给下游覆盖时使用
- [x] 3.2 实现 `function setSellBenefitRate(uint16 rate) external virtual onlyRole(DEFAULT_ADMIN_ROLE) returns (bool)`：rate==0 revert `ErrorInvalidAmount(0)`；写入 `sellBenefitRate`；emit `SellBenefitRateChanged(rate)`；返回 `true`
- [x] 3.3 NatSpec 注释清楚说明：每档独立 setter；下游若需新增档（如 invest），自行加同形 setter + 事件，不需要 override 已有函数；任意 setter 都通过 `DEFAULT_ADMIN_ROLE` 守护；**调用方负责保证 `channelBenefitRate + sellBenefitRate ≤ 1000`**（base 不强制 cap，超过会让 `_distributeChannelAndDaoBenefits` 在下次 collect 时 underflow revert，是已知 governance footgun）

## 4. 测试 harness

- [x] 4.1 新增 `contracts/test/PrizePoolBaseHarness.sol`：`is PrizePoolBase`，构造函数原样转发 7 参数到 base
- [x] 4.2 给 9 个 internal helper（§2.1–§2.9）分别加 external wrapper：`getCoin()` / `colletWithCoin(...)` × 2 / `transferTo(...)` / `channelBenefitTransfer(...)` / `daoBenefitTransfer(...)` / `getBenefitByRate(...)` / `mintDaoCoinToPayer(...)` / `distributeChannelAndDaoBenefits(...)`
- [x] 4.3 harness 文件加 `// SPDX-License-Identifier: GPL-3.0` 头与 hardhat-only 注释，避免被误用作生产合约

## 5. 单元测试 — fixtures 与基础场景

- [x] 5.1 新增 `contracts/test/MockSilentFailCoin.sol`：实现 `IERC20` + `safeTransfer` 路径下 `transfer(...)` 返回 `true` 但**不**修改任何 balance；用于 `_transferTo` silent-fail scenario
- [x] 5.2 新增 `contracts/test/MockFeeOnTransferCoin.sol`：标准 ERC20 + 在 `_update` 中扣固定 `fee`（如 `1`）转给销毁地址，模拟 transfer 多扣手续费；用于 `_transferTo` fee-on-transfer scenario
- [x] 5.3 新增 `test/runTest/PrizePoolBase.test.js` 与配套 `test/utils/deployPrizePoolBaseFixture.js`：复用既有 `test/utils/deployTool.js#deploy()` 拿到 `GreatLottoCoinTest` / `DaoCoin` / `DaoBenefitPool` / `SalesChannel`；在此基础上部署 `PrizePoolBaseHarness`（构造参数 `(coin, daoCoin, daoBenefitPool, salesChannel, owner, 30, 70)`）；并把 `PARTNER_CONTRACT_ROLE` 授予 harness（`DaoCoin.mintToUser` 需要该角色）
- [x] 5.4 部署后断言：4 个 immutable getter 返回值正确；`channelBenefitRate()==30`；`sellBenefitRate()==70`

## 6. 单元测试 — `_colletWithCoin`（直接版）

- [x] 6.1 amount==0 revert `ErrorInvalidAmount(0)`
- [x] 6.2 GLC 路径：approve 足量后调用，断言合约 GLC 余额增加；返回值类型为 `ICoinBase`
- [x] 6.3 外币 mint 路径：白名单稳定币 approve harness，断言 `coin.mint` 被调用、合约 GLC 余额增加（结合 `getAmount`）
- [x] 6.4 GLC 路径未 approve 时 revert（来自 `safeTransferFrom`）

## 7. 单元测试 — `_colletWithCoin` permit 版

- [x] 7.1 amount==0 revert
- [x] 7.2 GLC permit 路径 — allowance 不足：构造 EIP-2612 签名，断言 `permit` 调用成功 + `safeTransferFrom` 完成
- [x] 7.3 GLC permit 路径 — allowance 已足够：传任意 `(v, r, s)`，断言 `permit` 不被调用（通过 nonce 不变 / 事件不发等观察）
- [x] 7.4 外币 permit mint 路径：断言 `coin.mint(token, amount, payer, deadline, v, r, s)` 被调用

## 8. 单元测试 — `_transferTo`

- [x] 8.1 amount==0 早退：合约余额为 0 时调用 `_transferTo(coin, recipient, 0)` 不 revert，recipient 余额不变；断言不读取 `balanceOf`（可通过 mock 计数器观察）
- [x] 8.2 余额不足 revert `ErrorInsufficientBalance(coin, harness, balance, amount)`
- [x] 8.3 正常 transfer：harness 预存 GLC，调用 `_transferTo(coin, recipient, amount)`；断言 recipient 余额增加 `amount`，harness 余额减少 `amount`，函数正常返回
- [x] 8.4 **silent-fail mock**：使用 `MockSilentFailCoin`（transfer 返回 true 但合约余额不扣减），调用 `_transferTo` 后断言 revert `ErrorPaymentUnsuccessful`
- [x] 8.5 **fee-on-transfer mock**：使用 `MockFeeOnTransferCoin`（transfer 多扣 `fee > 0`），调用 `_transferTo` 后断言 revert `ErrorPaymentUnsuccessful`

## 9. 单元测试 — `_channelBenefitTransfer`

- [x] 9.1 无效渠道（`chnId` 不存在 / 已 disable 且 `chn==address(0)`）revert `SalesChannelInvalid(chn)`
- [x] 9.2 有效渠道：harness 预存 GLC，调用 `_channelBenefitTransfer(coin, benefit, chnId)`；断言渠道地址余额增加 benefit、harness 余额减少 benefit

## 10. 单元测试 — `_daoBenefitTransfer` / `_getBenefitByRate` / `_mintDaoCoinToPayer`

- [x] 10.1 `_daoBenefitTransfer`：harness 预存 GLC，调用后断言 `DaoBenefitPoolAddress` 余额增加
- [x] 10.2 `_getBenefitByRate(1000, 70)` → `(70, 930)`
- [x] 10.3 `_getBenefitByRate(1000, 0)` → `(0, 1000)`
- [x] 10.4 `_getBenefitByRate(1000, 1000)` → `(1000, 0)`
- [x] 10.5 `_mintDaoCoinToPayer(payer, assets)`：断言 DaoCoin 的 `mintToUser` 被调用、payer 余额增加 assets

## 11. 单元测试 — `setChannelBenefitRate` / `setSellBenefitRate`

- [x] 11.1 `setChannelBenefitRate`：非 admin caller revert `AccessControlUnauthorizedAccount`
- [x] 11.2 `setChannelBenefitRate`：admin 调用 `setChannelBenefitRate(0)` revert `ErrorInvalidAmount(0)`
- [x] 11.3 `setChannelBenefitRate`：admin 调用 `setChannelBenefitRate(40)`：断言 `channelBenefitRate==40`、emit `ChannelBenefitRateChanged(40)`、返回值为 true
- [x] 11.4 `setSellBenefitRate`：非 admin caller revert `AccessControlUnauthorizedAccount`
- [x] 11.5 `setSellBenefitRate`：admin 调用 `setSellBenefitRate(0)` revert `ErrorInvalidAmount(0)`
- [x] 11.6 `setSellBenefitRate`：admin 调用 `setSellBenefitRate(80)`：断言 `sellBenefitRate==80`、emit `SellBenefitRateChanged(80)`、返回值为 true
- [x] 11.7 ABI surface 检查：harness 的 ABI MUST NOT 包含历史 `changeBenefitRate(uint8,uint16)` / `BenefitRateChanged(uint8,uint16)`

## 12. 单元测试 — `_distributeChannelAndDaoBenefits`

- [x] 12.1 channelId>0 + 渠道有效：harness 预存 GLC（≥ amountByCoin），调用 `(amount=10000, channel=valid)` 且 `channelBenefitRate=30, sellBenefitRate=70`；断言渠道余额 +300、DAO 余额 +700、harness 余额 -1000、返回值 9000
- [x] 12.2 channelId==0：harness 预存 GLC，调用 `(amount=10000, channel=0)`；断言渠道地址余额不变、DAO 余额 +1000、harness 余额 -1000、返回值 9000；事件 `ChannelBenefit*` 不应触发渠道分润相关副作用
- [x] 12.3 channelId>0 但 id 不存在（`status==false && chn==address(0)`）：调用 revert `SalesChannelInvalid(address(0))`；DAO 余额不变（整笔交易回滚）
- [x] 12.4 channelId>0 + 渠道已停用但有地址（`status==false && chn!=address(0)`）：调用不 revert；断言该地址余额 +channelBenefit、DAO 余额 +sellBenefit
- [x] 12.5 余额不足：harness 余额 < 应付分润总额，调用 revert `ErrorInsufficientBalance`
- [x] 12.6 两档 rate==0：用 fixture 重新部署一份初始 (channel=0, sell=0) 的 harness（注意 setter 不接受 0，必须走构造）；调用 helper：断言无任何 transfer、返回值 == amountByCoin
- [x] 12.7 整数除法边界：amountByCoin=1，channelRate=30 → channelBenefit=0（1*30/1000=0），sellRate=70 → sellBenefit=0；返回值=1；无 transfer 触发

## 13. 编译 / 覆盖率 / 合约大小回归

- [x] 13.1 `npx hardhat clean && npx hardhat compile` 全绿
- [x] 13.2 `npx hardhat test test/runTest/PrizePoolBase.test.js` 全部用例通过
- [x] 13.3 `npx hardhat coverage --testfiles "test/runTest/PrizePoolBase.test.js"` 显示 `PrizePoolBase.sol` 行覆盖率 ≥ 95%、分支覆盖率 ≥ 90%
- [x] 13.4 `contractSizer` 输出确认 `PrizePoolBaseHarness` 不超过 EIP-170 24 KiB；**注意**：harness 含 9 个 external wrapper，size 比 base 在下游 inherit 后的真实增量大若干 KB，该指标仅作绝对上限参考；下游真实增量在 Phase 2/3 单测
- [x] 13.5 既有 infra 测试套件全量回归 `npx hardhat test`，确认未影响其他基类（`AccessControlPartnerContract` 派生合约的 selector 集合无冲突）

## 14. 文档与 OpenSpec 收尾

- [x] 14.1 更新 `infrastructure/CLAUDE.md`：在 base 列表中添加 `PrizePoolBase`，简述提供的能力与下游集成方式
- [x] 14.2 在 `infrastructure/doc/prize-pool-base-migration-plan.md` 顶部加 "Phase 1 已完成" 标记 + 指向本 change 路径
- [x] 14.3 `openspec validate add-prize-pool-base --strict` 通过
- [x] 14.4 PR 描述中引用本 change 路径、design.md 决策表 D1–D11、并附测试覆盖率与合约大小输出截图
