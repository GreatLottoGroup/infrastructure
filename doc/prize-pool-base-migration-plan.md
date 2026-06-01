# PrizePoolBase 迁移方案 — 抽象到 infrastructure，复用至 ScratchCard / GreatLottoCore

> **Status — Phase 1 已完成**（infrastructure 仓内 `PrizePoolBase` + `IPrizePoolBase` + `PrizePoolBaseHarness` + 36 用例单元测试落地）。OpenSpec change 见 [openspec/changes/add-prize-pool-base/](../openspec/changes/add-prize-pool-base/)。Phase 2 / Phase 3 待启动。

> **目标**：把 `ScratchCard/contracts/base/PrizePoolBase.sol` 中与具体业务无关的"奖金池收款 / 分润 / 转账 / 治理币增发"基础能力上移到 `@greatlotto/infrastructure`，让 `ScratchCard` 与 `GreatLottoCore` 的奖池合约同时复用，消除重复实现并统一安全语义。

**Tech Stack:** Solidity ^0.8.24 · `@greatlotto/infrastructure` · Hardhat · OpenZeppelin v5

**Working directories:**
- 主体改动：`/Users/tongren/Documents/github/GreatLottoGroup/infrastructure`
- 下游适配：`/Users/tongren/Documents/github/GreatLottoGroup/ScratchCard`、`/Users/tongren/Documents/github/GreatLottoGroup/GreatLottoCore`

**Prerequisites:**
- 工作区已用 pnpm 软链 `@greatlotto/infrastructure`（无需发版）
- 三仓 Solidity / OZ / Hardhat 版本一致

**OpenSpec 关联：**
- Phase 1 已建立 OpenSpec 提案：[`infrastructure/openspec/changes/add-prize-pool-base/`](../openspec/changes/add-prize-pool-base/)（proposal / design / specs / tasks 全部通过 strict validate）
- Phase 2 / 3 待在各自下游仓单独立提案

---

## 1. 背景与动机

两个下游仓的奖池合约都重复实现了几乎完全一致的"收款 + 分润 + 转账"工具集：

| Helper | ScratchCard `PrizePoolBase` | GreatLottoCore `PrizePool` | 差异 |
|---|---|---|---|
| `_getCoin()` | internal view | private view | 仅可见性 |
| `_colletWithCoin(token, payer, amount)` | internal，**返回 `ICoinBase`**，**revert amount==0** | private，无返回，由调用者保证 amount>0 | 签名 + 入口防御 |
| `_colletWithCoin(... , v, r, s)`（permit 版） | 同上 | 同上 | 同上 |
| `_channelBenefitTransfer(coin, benefit, chnId)` | internal | private | 实现一致 |
| `_transferTo(coin, to, amount)` | internal，**严格**：amount==0 不早退、有 `ErrorPaymentUnsuccessful` 后置校验 | private，**宽松**：amount==0 早退、无后置校验 | 安全语义 |
| `_getBenefitByRate(amount, rate)` | internal pure | private pure | 完全一致 |
| `_daoBenefitTransfer(coin, benefit)` | internal | 内联为 `_transferTo(coin, DaoBenefitPoolAddress, ...)` | 仅是否封装 |
| `_mintDaoCoinToPayer(payer, assets)` | internal | 内联为 `IDaoCoin(...).mintToUser(...)` | 仅是否封装 |
| 渠道+DAO 分润 pipeline（`_afterCollectForBuy` / `_collect` 中的 `_channelBenefit` + `_sellBenefit` + channelId==0 时合并打 DAO） | 内联在 `_afterCollectForBuy` | 内联在 `_collect` | **逻辑一致但未抽 helper** |
| `changeBenefitRate` | rateType: 1=sell, 2=channel（2 档） | rateType: 1=invest, 2=channel, 3=sell（3 档） | 维度不同；新方案改为按档独立 setter，详见 §2.2 D6 |

约 **80% 的 helper 代码重复**，且当前两份实现的安全后置校验不一致——抽象之后可以统一为更严格的版本。

---

## 2. 复用面与差异调和

### 2.1 可直接复用的（无差异或差异可忽略）

- 4 个 immutable：`GreatLottoCoinAddress` / `DaoCoinAddress` / `DaoBenefitPoolAddress` / `SalesChannelAddress`
- 2 档共有分润率：`channelBenefitRate` / `sellBenefitRate`
- 7 个 helper：`_getCoin` / `_colletWithCoin × 2` / `_channelBenefitTransfer` / `_transferTo` / `_getBenefitByRate` / `_mintDaoCoinToPayer` / `_daoBenefitTransfer`
- 1 个新增 pipeline helper（**本次新增**，详见 §2.2 D11）：`_distributeChannelAndDaoBenefits(coin, amountByCoin, channelId) → netAmount`，封装"渠道+DAO 两段分润 + channelId==0 合并"逻辑
- `IPrizePoolBase` 接口：`ChannelBenefitRateChanged` / `SellBenefitRateChanged` 两个事件 + `setChannelBenefitRate` / `setSellBenefitRate` 两个函数（**取代历史的 `BenefitRateChanged` / `changeBenefitRate`**）
- `AccessControlPartnerContract` 集成（两个 setter 都用 `onlyRole(DEFAULT_ADMIN_ROLE)`）

### 2.2 必须明确决策的差异点

| # | 差异 | 决策 | 理由 |
|---|---|---|---|
| D1 | helper 可见性 `internal` vs `private` | **`internal`** | GreatLottoCore 的 `private` 是历史选择；切到 `internal` 不改变外部 ABI，只放宽对子类可见，安全 |
| D2 | `_colletWithCoin` 是否返回 `ICoinBase` | **返回 `ICoinBase`** | 调用方多数情形都需要 coin 引用；GreatLottoCore 既有调用点会丢一个局部变量但简化签名 |
| D3 | `_colletWithCoin` 是否内部 revert `amount==0` | **保留 revert** | 入口防御，深一层兜底；GreatLottoCore 当前所有 caller 都已上层校验，重复 revert 路径不可达，无副作用 |
| D4 | `_transferTo` 严格 vs 宽松 | **base 版本：amount==0 早退 + 余额检查 + 后置 strict equality 校验 `balanceOf == _balance - amount`** | 早退保证 GreatLottoCore 的 `fromNormal == 0` / `fromRollup == 0` 调用不 revert；strict equality 同时 catch silent-fail token（transfer 不扣款）与 fee-on-transfer token（transfer 多扣手续费）。**注意**：ScratchCard 现行 `<` 单向校验只 catch silent-fail、不 catch fee-on-transfer，base 升级为 `!=` 是从下游迁移到 base 的安全增强（review 复盘所得） |
| D5 | 分润档位维度 2 vs 3 | **base 只持有 channel/sell 两档；GreatLottoCore 自己保留 `investmentBenefitRate`，并 override `changeBenefitRate`** | base 只承诺最小公倍数；invest 档是 GreatLotto 业务专属，不上移 |
| D6 | 分润率治理 setter 形态 | **拆分为 `setChannelBenefitRate(uint16)` + `setSellBenefitRate(uint16)` 两个独立函数 + 两个独立事件**（`ChannelBenefitRateChanged` / `SellBenefitRateChanged`），取代历史 `changeBenefitRate(rateType, rate)` | 调用现场自解释、无 magic number；下游加新档（如 invest）只需自加同形 setter，无需 override base；事件链下精确订阅。两个下游主网均未部署，BREAKING 仅影响测试网 / 测试用例 / governance UI |
| D7 | `_daoBenefitTransfer` / `_mintDaoCoinToPayer` 是否封装 | **保留封装** | 语义化命名，GreatLottoCore 适配时把内联调用替换为 helper 调用，可读性提升 |
| D8 | `IPrizePoolBase` 放在哪 | **infrastructure/contracts/interfaces/IPrizePoolBase.sol**；下游删除自己的副本 | 防止接口漂移 |
| D11 | 是否抽出"渠道+DAO 两段分润" pipeline helper | **抽出 `_distributeChannelAndDaoBenefits(coin, amountByCoin, channelId) → netAmount`**：基类内部完成 `channelId>0` 时分别打款 / `channelId==0` 时合并打 DAO；返回 `netAmount = amountByCoin − channelBenefit − sellBenefit`，caller 自行处置净值 | ScratchCard `_afterCollectForBuy` 与 GreatLottoCore `_collect` 中这段逻辑逐字一致；末端去向不同（前者打给 creator、后者入 `_normalPool`）由返回值解耦，不污染 base。GreatLottoCore 的 invest 档由 caller 在调 helper 之前自行扣除并打款 |

### 2.3 故意不上移的

- GreatLottoCore 的 `_normalPool` / `_rollupBalance` / `_pending` / `_debt` / `_totalDebt` / `_checkInvariant` / `lockPending` / `fulfillDraw` / `payDebt` / 投资存赎逻辑 → **业务专属**，留在 GreatLottoCore
- ScratchCard 的 `_prizePool[tokenId]` 单卡奖池 / `_collectForIssue` / `_collectForBuy` / `_payBonus` → **业务专属**，留在 ScratchCard 自己的 `PrizePool.sol`
- `NoDelegateCall` / `DeadLine` → 已经在 infrastructure，但与 PrizePoolBase 是组合关系而非继承，由各下游合约按需 mix-in

---

## 3. 目标产物（infrastructure 仓）

### 3.1 新增文件

```
infrastructure/contracts/
├── base/
│   └── PrizePoolBase.sol            ← 新增（abstract）
└── interfaces/
    └── IPrizePoolBase.sol           ← 新增
```

### 3.2 `IPrizePoolBase.sol` 接口（最终形态）

```solidity
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

interface IPrizePoolBase {
    event ChannelBenefitRateChanged(uint16 rate);
    event SellBenefitRateChanged(uint16 rate);

    /// @notice 调整渠道分润比例（千分比，>0）
    function setChannelBenefitRate(uint16 rate) external returns (bool);

    /// @notice 调整 sell（→ DAO 利润池）分润比例（千分比，>0）
    function setSellBenefitRate(uint16 rate) external returns (bool);
}
```

> **不再包含** `BenefitRateChanged(uint8, uint16)` 事件与 `changeBenefitRate(uint8, uint16)` 函数；历史聚合 dispatch 已被 D6 拆分取代。

### 3.3 `PrizePoolBase.sol` API 表

| 元素 | 可见性 | 说明 |
|---|---|---|
| `GreatLottoCoinAddress` | `address public immutable` | 资产币 |
| `DaoCoinAddress` | `address public immutable` | DAO 治理币 |
| `DaoBenefitPoolAddress` | `address public immutable` | DAO 分润池 |
| `SalesChannelAddress` | `address public immutable` | 销售渠道注册表 |
| `channelBenefitRate` | `uint16 public` | 默认 30（3%） |
| `sellBenefitRate` | `uint16 public` | 默认 70（7%）— 注：当前 ScratchCard 默认是 70（7%），GreatLottoCore 是 30（3%）。**base 不强加默认值**，由子类构造时显式设置；详见任务 1.2 |
| `_getCoin()` | `internal view` | 返回 `ICoinBase(GreatLottoCoinAddress)` |
| `_colletWithCoin(token, payer, amount) → ICoinBase` | `internal` | revert amount==0；GLC 走 transferFrom，外币走 mint |
| `_colletWithCoin(token, payer, amount, deadline, v, r, s) → ICoinBase` | `internal` | permit 版 |
| `_transferTo(coin, to, amount)` | `internal` | amount==0 早退；余额检查；safeTransfer；后置 `ErrorPaymentUnsuccessful` 校验 |
| `_channelBenefitTransfer(coin, benefit, chnId)` | `internal` | 走 `ISalesChannel.getChannelById`，失败 revert `SalesChannelInvalid` |
| `_daoBenefitTransfer(coin, benefit)` | `internal` | sugar over `_transferTo` |
| `_getBenefitByRate(amount, rate) → (benefit, after)` | `internal pure` | `benefit = amount * rate / 1000` |
| `_mintDaoCoinToPayer(payer, assets)` | `internal` | `IDaoCoin(DaoCoinAddress).mintToUser` |
| `_distributeChannelAndDaoBenefits(coin, amountByCoin, channelId) → netAmount` | `internal` | channelId>0：渠道打 channelBenefit、DAO 打 sellBenefit；channelId==0：合并打 DAO；返回 `netAmount = amountByCoin − channelBenefit − sellBenefit` |
| `setChannelBenefitRate(rate)` | `public virtual onlyRole(DEFAULT_ADMIN_ROLE)` | rate==0 revert `ErrorInvalidAmount(0)`；写入 `channelBenefitRate`；emit `ChannelBenefitRateChanged(rate)` |
| `setSellBenefitRate(rate)` | `public virtual onlyRole(DEFAULT_ADMIN_ROLE)` | rate==0 revert `ErrorInvalidAmount(0)`；写入 `sellBenefitRate`；emit `SellBenefitRateChanged(rate)` |

构造函数：

```solidity
constructor(
    address coin,
    address daoCoinAddr,
    address daoBenefitPoolAddr,
    address salesChannelAddr,
    address _owner,
    uint16 initialChannelRate,
    uint16 initialSellRate
) AccessControlPartnerContract(_owner) {
    GreatLottoCoinAddress = coin;
    DaoCoinAddress = daoCoinAddr;
    DaoBenefitPoolAddress = daoBenefitPoolAddr;
    SalesChannelAddress = salesChannelAddr;
    channelBenefitRate = initialChannelRate;
    sellBenefitRate = initialSellRate;
}
```

> 把默认值挪到构造参数后，两个下游可以各自维持现有的"出厂值"：ScratchCard `(30, 70)`，GreatLottoCore `(20, 30)`。避免 base 写死任意一边的默认导致另一边迁移时偷偷改默认值。

继承：`abstract contract PrizePoolBase is AccessControlPartnerContract, IPrizePoolBase`（`AccessControlPartnerContract` 已 `is IErrorsBase`，因此 `ErrorInvalidAmount` / `ErrorInsufficientBalance` / `ErrorPaymentUnsuccessful` 都可用）。

---

## 4. 迁移阶段

按"先写基类 + 测试 → ScratchCard 适配 → GreatLottoCore 适配"三阶段，每阶段独立可合可回滚。

### Phase 1 — infrastructure 落地基类

**Files:**
- Add: `infrastructure/contracts/base/PrizePoolBase.sol`
- Add: `infrastructure/contracts/interfaces/IPrizePoolBase.sol`
- Add: `infrastructure/contracts/test/PrizePoolBaseHarness.sol`（仅测试用，把 internal helper 暴露为 external）
- Add: `infrastructure/test/runTest/PrizePoolBase.test.js`

**Tasks（详细任务清单见 OpenSpec change [`add-prize-pool-base/tasks.md`](../openspec/changes/add-prize-pool-base/tasks.md)，共 13 组任务）：**

- [ ] 1.1 写 `IPrizePoolBase.sol`：声明 `ChannelBenefitRateChanged` / `SellBenefitRateChanged` 事件 + `setChannelBenefitRate` / `setSellBenefitRate` 函数（不含历史聚合 setter）
- [ ] 1.2 写 `PrizePoolBase.sol`：移植 ScratchCard 现有实现 + 应用 §2.2 决策（D2 返回 coin / D3 amount==0 revert / D4 早退+后置校验 / D6 拆分 setter / D11 新增分润 pipeline helper / 构造参数化默认值）
- [ ] 1.3 写 `PrizePoolBaseHarness`：给 9 个 internal helper 加 external wrapper（含 `_distributeChannelAndDaoBenefits`）
- [ ] 1.4 单元测试覆盖：
  - [ ] `_colletWithCoin` GLC 路径 / 外币路径 / amount==0 revert / permit 路径（allowance 足/不足两条分支）
  - [ ] `_transferTo` amount==0 早退 / 余额不足 revert / fee-on-transfer 假币触发 `ErrorPaymentUnsuccessful`
  - [ ] `_channelBenefitTransfer` 渠道无效 revert / 正常打款
  - [ ] `_daoBenefitTransfer`、`_getBenefitByRate` 边界（rate=0 / rate=1000）、`_mintDaoCoinToPayer`
  - [ ] **`_distributeChannelAndDaoBenefits`**：channelId>0 + 有效渠道 / channelId==0 合并 / channelId>0 + 渠道无效 revert / 余额不足 revert / 两档 rate==0 / 整数除法边界
  - [ ] **`setChannelBenefitRate` / `setSellBenefitRate`**：非 admin revert / rate==0 revert / 成功更新 + 独立事件；ABI surface 检查不含历史 `changeBenefitRate(uint8,uint16)`
- [ ] 1.5 `npx hardhat compile` + `npx hardhat test test/runTest/PrizePoolBase.test.js` 全绿
- [ ] 1.6 `npx hardhat coverage` 覆盖率 ≥ 95%

**Acceptance:** infra CI 全绿，新增基类与接口正确导出；OpenSpec change `add-prize-pool-base` 通过 `--strict` validate。

---

### Phase 2 — ScratchCard 适配

**Files:**
- Delete: `ScratchCard/contracts/base/PrizePoolBase.sol`
- Delete: `ScratchCard/contracts/interfaces/IPrizePoolBase.sol`
- Modify: `ScratchCard/contracts/base/PrizePool.sol`（import 改到 infra；构造转发参数）
- Modify: 任何 import 上述两文件的地方（grep 一次确认）

**Tasks:**
- [ ] 2.1 `grep -r "base/PrizePoolBase\|interfaces/IPrizePoolBase\|changeBenefitRate\|BenefitRateChanged" contracts/ test/` 列出所有引用点（含历史聚合 setter / 事件的调用与断言）
- [ ] 2.2 `ScratchCard/contracts/base/PrizePool.sol`：
  - import 改为 `@greatlotto/infrastructure/contracts/base/PrizePoolBase.sol` + `@greatlotto/infrastructure/contracts/interfaces/IPrizePoolBase.sol`
  - 添加构造函数转发 7 参数到 base（`coin / daoCoin / daoBenefitPool / salesChannel / owner / 30 / 70`）— 或如果 ScratchCard 主合约 ScratchCard.sol 已经 cascading 构造参数，把这两个默认值作为常量传入
  - **重写 `_afterCollectForBuy`**：用 `uint netAmount = _distributeChannelAndDaoBenefits(coin, amountByCoin, channelId);` 替代原来的渠道+DAO 两段计算与转账；保留打给 `creator` 与 `_mintDaoCoinToPayer` 两步（caller 责任）
- [ ] 2.3 删除 `ScratchCard/contracts/base/PrizePoolBase.sol` 与 `ScratchCard/contracts/interfaces/IPrizePoolBase.sol`
- [ ] 2.4 **测试 / governance 调用迁移**：把 `ScratchCard.test.js` / `M2Features.test.js` 中所有 `changeBenefitRate(rateType, rate)` 调用改为对应的 `setChannelBenefitRate(rate)` / `setSellBenefitRate(rate)`；事件断言 `BenefitRateChanged` → `ChannelBenefitRateChanged` / `SellBenefitRateChanged`
- [ ] 2.5 全量编译：`npx hardhat clean && npx hardhat compile`
- [ ] 2.6 跑现有测试套件：`npx hardhat test test/runTest/DrawAlgo.test.js test/runTest/ScratchCard.test.js test/runTest/M2Features.test.js`（共 63 用例，必须全部通过）
- [ ] 2.7 合约大小回归（`ScratchCard ≈ 17.4 KiB` 不应显著膨胀）
- [ ] 2.8 更新 `ScratchCard/CLAUDE.md`：依赖新版基类，删除 PrizePoolBase 本地条目；治理章节同步把 `changeBenefitRate` 改为两个 setter

**Acceptance:** ScratchCard 全测试绿、合约 size 不超 EIP-170、`_afterCollectForBuy` 行为等价于改造前（事件发射顺序与金额一致）；ABI diff 允许范围：①PrizePool 构造函数 inputs 增加；②`changeBenefitRate(uint8,uint16)` / `BenefitRateChanged(uint8,uint16)` 移除；③`setChannelBenefitRate(uint16)` / `setSellBenefitRate(uint16)` / `ChannelBenefitRateChanged(uint16)` / `SellBenefitRateChanged(uint16)` 新增。

---

### Phase 3 — GreatLottoCore 适配

GreatLottoCore 改造范围比 ScratchCard 大：当前 `PrizePool.sol` 是 concrete 合约，所有 helper 是 `private` 直接内嵌，需要拆出去 inherits。

**Files:**
- Modify: `GreatLottoCore/contracts/PrizePool.sol`（改成 `is PrizePoolBase, NoDelegateCall, DeadLine, IPrizePool, IErrors`）
- Modify: `GreatLottoCore/contracts/interfaces/IPrizePool.sol`（继承 `IPrizePoolBase`，去掉重复的 `BenefitRateChanged` / `changeBenefitRate` 声明，如有）
- Modify: `GreatLottoCore/test/...`（事件签名 import 路径若有变）

**Tasks:**
- [ ] 3.1 `IPrizePool` 让其 `is IPrizePoolBase`；删除本地重复声明（若有）
- [ ] 3.2 `PrizePool.sol` 继承链改为 `PrizePoolBase, NoDelegateCall, DeadLine, IErrors, IPrizePool`
- [ ] 3.3 删除 `PrizePool.sol` 中的：
  - 4 个公共 immutable（GLC / DaoCoin / DaoBenefitPool / SalesChannel）→ 由 base 持有
  - `channelBenefitRate` / `sellBenefitRate` storage → 由 base 持有
  - `_getCoin`、`_colletWithCoin × 2`、`_channelBenefitTransfer`、`_transferTo`、`_getBenefitByRate` 6 个私有 helper
- [ ] 3.4 调用点重写：
  - `_colletWithCoin(token, coin, payer, amount[, perm])` → `coin = _colletWithCoin(token, payer, amount[, perm])`（去掉显式传 coin 的位置参数；接住返回值）
  - `_transferTo(coin, recipient, 0)` 调用现在仍是 no-op（base 早退），保持原行为
  - **`_collect` 渠道+DAO 两段重写**：用 `uint netAfterChannelDao = _distributeChannelAndDaoBenefits(coin, amountByCoin, ticketParams.issueParam.channelId);` 替代原来的渠道+DAO 两段计算与 `_transferTo`；invest 档保留在 helper 调用之**前**自行扣除：

    ```solidity
    // invest 档（业务专属，留在子类）
    (uint _investmentBenefit,) = _getBenefitByRate(amountByCoin, investmentBenefitRate);
    _transferTo(coin, InvestmentBenefitPoolAddress, _investmentBenefit);

    // 渠道 + DAO 两段（base helper）
    uint netAfterChannelDao = _distributeChannelAndDaoBenefits(coin, amountByCoin, ticketParams.issueParam.channelId);

    // 真正进 normalPool 的净值
    uint netAmount = netAfterChannelDao - _investmentBenefit;
    _normalPoolUp(netAmount);

    // mint DaoCoin
    _mintDaoCoinToPayer(ticketParams.payer, amountByCoin);
    ```
- [ ] 3.5 新增 `investmentBenefitRate` 单独保留为 storage（默认 50），并 emit `event InvestmentBenefitRateChanged(uint16 rate)`
- [ ] 3.6 **新增独立 setter `setInvestmentBenefitRate(uint16 rate)`**（取代历史聚合 `changeBenefitRate(rateType, rate)`）：

  ```solidity
  event InvestmentBenefitRateChanged(uint16 rate);

  function setInvestmentBenefitRate(uint16 rate)
      public onlyRole(DEFAULT_ADMIN_ROLE) returns (bool)
  {
      if (rate == 0) revert ErrorInvalidAmount(rate);
      investmentBenefitRate = rate;
      emit InvestmentBenefitRateChanged(rate);
      return true;
  }
  ```

  > **不再 override base 的 `setChannelBenefitRate` / `setSellBenefitRate`**——三档 setter 各自独立、并列存在；前端按 setter 名调用即可。GreatLottoCore 历史的 `changeBenefitRate(uint8, uint16)` 与 `BenefitRateChanged(uint8, uint16)` 全部移除（**BREAKING**，但主网未部署，仅影响测试网 / 测试用例 / governance UI）。
- [ ] 3.7 构造函数：把 4 个公共 immutable 的赋值挪到 `super` 构造调用：
  ```solidity
  constructor(
      address coin,
      address investmentCoinAddr,
      address investmentBenefitPoolAddress,
      address daoCoinAddress,
      address daoBenefitPoolAddress,
      address chn,
      address _owner
  )
      PrizePoolBase(coin, daoCoinAddress, daoBenefitPoolAddress, chn, _owner, 20, 30)
  {
      InvestmentCoinAddress = investmentCoinAddr;
      InvestmentBenefitPoolAddress = investmentBenefitPoolAddress;
  }
  ```
- [ ] 3.8 `_collect` 里的 `IDaoCoin(DaoCoinAddress).mintToUser(...)` → `_mintDaoCoinToPayer(...)`
- [ ] 3.9 **测试 / governance 调用迁移**：所有 `changeBenefitRate(rateType, rate)` → `setInvestmentBenefitRate` / `setChannelBenefitRate` / `setSellBenefitRate`；事件断言 `BenefitRateChanged` → 三个独立事件
- [ ] 3.10 全量编译 + 现有测试套件全绿
- [ ] 3.11 不变量保护性回归：base `_transferTo` 后置校验对 `_normalPool + _rollupPool == coin.balanceOf(this)` 不变量是否仍 hold（base 后置校验更严格，应不会破坏，但要测）
- [ ] 3.12 合约 size 回归
- [ ] 3.13 更新 `GreatLottoCore/CLAUDE.md`

**Acceptance:** GreatLottoCore 全测试绿、`getRollupBalance` / `getNormalPool` / `getTotalDebt` / `getPending` / `getDebt` ABI 不变、不变量未破坏、`_collect` 行为等价（事件发射顺序与金额一致）、合约 size 在限。

---

## 5. 风险与回滚

| 风险 | 影响 | 缓解 |
|---|---|---|
| **Storage layout 变化**（GreatLottoCore 4 immutable 由本合约移到父合约）| immutable 不占 storage slot，无影响；非 immutable storage（`channelBenefitRate` / `sellBenefitRate`）从 child 移到 parent 会**改变 slot 位置** | GreatLottoCore PrizePool **未启用代理升级**（构造一次性部署），因此 layout 不需要保持兼容；CI grep 确认无 `Initializable` / `UUPS` / Proxy |
| `_transferTo` 后置校验在 GreatLottoCore 引入 false revert | 关键路径全部回归 | Phase 3 任务 3.11 显式覆盖 |
| **拆分 setter 是 BREAKING**：调用方若漏改 governance / 测试现场会运行时 revert（unknown function selector）或事件断言失败 | 测试网 / 测试用例 / governance UI | 主网未部署；Phase 2/3 任务 grep `changeBenefitRate(` / `BenefitRateChanged` 全部替换；前端 ABI 重新生成静态发现遗漏 |
| **`_distributeChannelAndDaoBenefits` 行为漂移**：调用方传错 `amountByCoin` 基数（如误传扣完 invest 后的金额）| 渠道/DAO 分润金额错算 | NatSpec 明确"基数为收款总额，invest 等业务专属档由 caller 在调 helper 之外另行处理"；Phase 2/3 端到端测试断言事件金额 |
| ScratchCard 测试硬编码 default rate（70 / 30）| 构造参数化后值不变，应无影响 | Phase 2 任务 2.6 跑全套测试 |
| 双向依赖 / 循环 import | infra 不应反向依赖下游 | base 只引用 `ICoinBase` / `IDaoCoin` / `ISalesChannel` 等已在 infra 的接口 |

**回滚策略**：每个 Phase 在独立分支，PR 单独合入；任一阶段失败仅回滚该阶段，前序阶段已上的基类不影响下游（下游未升级 dep 之前对它无感）。

---

## 6. 验收标准（汇总）

- [ ] infrastructure: `PrizePoolBase` + `IPrizePoolBase` 测试覆盖率 ≥ 95%；OpenSpec change `add-prize-pool-base` 通过 `--strict` validate
- [ ] ScratchCard: 63 测试用例全绿，合约 size 不超 EIP-170，`_afterCollectForBuy` 行为等价于改造前；ABI diff 在允许范围内（构造参数 + setter 拆分 + 事件拆分，详见 Phase 2 Acceptance）
- [ ] GreatLottoCore: 现有测试套件全绿，`_checkInvariant` 不变量未破坏，`_collect` 行为等价；三档 setter（invest / channel / sell）独立可调用；历史 `changeBenefitRate(uint8,uint16)` / `BenefitRateChanged(uint8,uint16)` 已移除
- [ ] 三仓 CLAUDE.md 同步更新（含治理章节 setter 名称替换）
- [ ] 重复代码计数：infrastructure 净增 ~150 行（含 `_distributeChannelAndDaoBenefits` ~20 行）；ScratchCard 净减 ~135 行（PrizePoolBase 全删 + `_afterCollectForBuy` 简化）；GreatLottoCore 净减 ~70 行（私有 helper 删除 + `_collect` 渠道/DAO 段简化）

---

## 7. 后续可选优化（不在本次范围）

- `_colletWithCoin` 两个重载之间逻辑高度重复，可进一步内部下沉到一个 private helper（permit 是否带签名作为可选参数）；本次保持原签名以减小 diff。
- ScratchCard 后续如果引入 invest 档，可把 `investmentBenefitRate` 也提到 base，统一三档结构（届时 base 同时持有 `setInvestmentBenefitRate`，GreatLottoCore 删除自己的同名 setter 改用 base 版）。
- 若未来"无渠道时 channelBenefit 合并进 DAO"的策略要修改（如改为退给买家），仅需改 base `_distributeChannelAndDaoBenefits` 一处，下游零改动——这是本次抽 helper 的直接收益。
