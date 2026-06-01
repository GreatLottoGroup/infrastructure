## Context

`@greatlotto/infrastructure` 已经沉淀了 `AccessControlPartnerContract` / `BeneficiaryBase` / `BenefitPoolBase` / `DeadLine` / `EntropyConsumerBase` / `NoDelegateCall` / `SelfPermit` 等横向基础合约，下游的 `ScratchCard`、`GreatLottoCore` 都通过 npm 包 + pnpm 软链直接引用。

奖池合约（PrizePool）层目前缺这块抽象：

- `ScratchCard/contracts/base/PrizePoolBase.sol`：abstract 基类，`internal` helper，2 档分润率。
- `GreatLottoCore/contracts/PrizePool.sol`：concrete 合约，把同一组工具以 `private` 重新写了一遍，混进自己的"普通奖池 / 滚动奖池 / 投资 vault / 不变量校验"业务实现。

**两份实现的差异已经在产生维护代价**（详见 `infrastructure/doc/prize-pool-base-migration-plan.md` §2）：

- `_transferTo` 一边有 `ErrorPaymentUnsuccessful` 后置校验、一边没有；
- `_colletWithCoin` 一边 revert `amount==0`、一边把校验留给调用方；
- `_colletWithCoin` 返回值签名不一致；
- 默认分润率不一致（ScratchCard 30/70 vs GreatLottoCore 20/30）。

只读 / 视图一致性（`_getCoin` / `_getBenefitByRate`）和写路径一致性（分润 / 转账）是奖池合约审计的重点，不能继续让两份实现自由漂移。

**约束：**

- 不修改 `ScratchCard` / `GreatLottoCore` 仓的代码（下游适配作为单独 change 在各自仓提案）。
- 不引入新的外部依赖（仅复用 OZ v5 + infra 内已有接口）。
- 不破坏既有 `AccessControlPartnerContract` 派生合约的 storage layout 假设。

## Goals / Non-Goals

**Goals:**

- 在 infrastructure 仓落地一份**唯一的、严格安全语义统一**的抽象奖池基类 `PrizePoolBase`。
- 让 `ScratchCard.PrizePoolBase`（abstract）与 `GreatLottoCore.PrizePool`（concrete，未来）都能直接 `is PrizePoolBase`。
- 提供完备的单元测试（覆盖率 ≥ 95%），把每条 helper 路径与 revert 路径都钉死。
- 抽出 `IPrizePoolBase` 接口（事件 + `changeBenefitRate`），让下游可以稳定地依赖接口而非实现。

**Non-Goals:**

- 不抽 ScratchCard 单卡奖池 (`_prizePool[tokenId]`) / `_payBonus` / `_collectForIssue` / `_collectForBuy`——它们是 ScratchCard 专属业务结构。
- 不抽 GreatLottoCore 的 `_normalPool` / `_rollupBalance` / `_pending` / `_debt` / `_checkInvariant` / `lockPending` / `fulfillDraw` / `payDebt` / 投资存赎——它们是 GreatLotto 专属业务。
- 不把 `NoDelegateCall` / `DeadLine` 强制集成进 `PrizePoolBase`（这两者与奖池基础能力是组合关系而非父子关系，由下游 mix-in）。
- 不修改下游仓代码（属于 Phase 2 / Phase 3，独立提案）。
- 不强制统一两边 `changeBenefitRate` 的 rateType 编码（GreatLottoCore 历史是 1=invest/2=channel/3=sell，强制重排会破坏 governance 调用约定）。

## Decisions

### D1 — helper 可见性：`internal`

**选择：** 所有 helper 公开为 `internal`。

**理由：** ScratchCard 现行就是 `internal`；GreatLottoCore 的 `private` 是历史选择，并非有意约束。`internal` 是最小可工作范围（只对子类可见），不暴露 ABI，不影响 storage layout，对调用方无任何运行时差异。

**替代：** 保持 `private` 强制每个下游自己包一层——会让基类无法被 `ScratchCard.PrizePool` / `GreatLottoCore.PrizePool` 直接复用，违背抽象初衷，弃用。

### D2 — `_colletWithCoin` 返回 `ICoinBase`

**选择：** 两个重载都返回 `ICoinBase coin` 引用。

**理由：** 大多数调用现场紧接着需要 `coin.balanceOf` / `coin.getAmount` / `coin.safeTransfer`，让 helper 直接返回 coin 比让调用方再 `_getCoin()` 一次更紧凑。ScratchCard 已经是这种签名；GreatLottoCore 当前 `_colletWithCoin(token, coin, payer, amount)` 的写法是因为它在 `collect()` 入口已经 hold 了 coin，迁移时把 coin 参数改成返回值，调用点 diff 单行（`_colletWithCoin(token, coin, ...)` → `coin = _colletWithCoin(token, ...)`）。

**替代：** 不返回——下游每次都得 `coin = _getCoin()` + `_colletWithCoin(...)` 两行，且当前 ScratchCard 已经依赖返回值，会让 ScratchCard 适配反而更繁琐，弃用。

### D3 — `_colletWithCoin` 内部 revert `amount == 0`

**选择：** helper 入口先 revert `ErrorInvalidAmount(0)`，再走 GLC / 外币分支。

**理由：** 双层防御：上层 `collect` / `buy` 入口已经会 revert，但基类是审计的"最后一道工具"，重复一次成本几乎为零，可以防止任何未来调用点遗漏校验。GreatLottoCore 现行所有调用方都已上层校验，这条路径不可达，无副作用。

**替代：** 只信赖调用方——审计成本更高（每个调用点都得复查），弃用。

### D4 — `_transferTo` 严格不变量合并版（strict equality）

**选择：**

```solidity
function _transferTo(ICoinBase coin, address recipient, uint amount) internal {
    if (amount == 0) return;
    uint _balance = coin.balanceOf(address(this));
    if (_balance < amount) revert ErrorInsufficientBalance(...);
    coin.safeTransfer(recipient, amount);
    if (coin.balanceOf(address(this)) != _balance - amount) revert ErrorPaymentUnsuccessful();
}
```

**理由：** 把两边的安全语义合并并升级为更严格的不变量——

- `amount == 0` 早退：保留 GreatLottoCore 在 `_fulfillNormalAward` / `payDebt` 等场景下"`fromNormal == 0` 或 `fromRollup == 0` 时不该 revert"的行为。
- 余额前置检查：与现行两边一致。
- **后置 strict equality 校验**：要求 transfer 后合约余额**严格等于** `_balance - amount`，任何偏差都 revert。这同时 catch 两类异常代币：
  - **silent-fail token**（transfer 返回 true 但实际未扣款）：transfer 后余额 = `_balance` ≠ `_balance - amount` → revert ✓
  - **fee-on-transfer token**（transfer 中合约多扣了手续费）：transfer 后余额 = `_balance - amount - fee` ≠ `_balance - amount` → revert ✓

> **修正声明：** ScratchCard 当前生产代码 `if (_balance - amount < coin.balanceOf(address(this)))` 的方向只 catch silent-fail，**不 catch fee-on-transfer**（review 复盘所得）。base 升级为 `!=` 即 strict equality 后两类异常都被 catch，是从下游迁移到 base 的安全增强。两个下游主网均未部署，无兼容性问题。

**替代：**

- 只用 ScratchCard 历史方向（`<` 单向校验）：仅 catch silent-fail，留下 fee-on-transfer 漏洞，弃用。
- 反方向（`coin.balanceOf < _balance - amount`）：仅 catch fee-on-transfer，留下 silent-fail 漏洞，弃用。
- 用 ScratchCard 严格版（`amount==0` 也 transfer）：会让 GreatLottoCore 的零额支付路径意外触发 `safeTransfer(0)`（虽然多数 ERC20 允许零额转账，但 OZ v5 的 SafeERC20 在某些代理代币上会 revert），需要逐一审视所有 caller，弃用。
- GreatLottoCore 宽松版（无后置校验）：丢掉所有不变量保护，弃用。

### D5 — base 只持有 channel/sell 两档分润率

**选择：** `PrizePoolBase` 持有 `channelBenefitRate` 与 `sellBenefitRate` 两个 `uint16 public` storage；不引入 `investmentBenefitRate`。

**理由：** invest 档是 GreatLottoCore 的业务专属——ScratchCard 没有 ERC4626 投资 vault，强行上移会让 ScratchCard 多一个永远是 0 的死字段。base 守"两个项目都需要的最小公倍数"；invest 由 GreatLottoCore 自己声明 storage 与默认值。

**替代：** base 内置 invest 档但默认 0——污染 ScratchCard 的 storage layout 与事件语义，弃用。

### D6 — 拆分分润率 setter（每档一个独立函数 + 独立事件）

**选择：** base 提供两个独立 setter：

```solidity
event ChannelBenefitRateChanged(uint16 rate);
event SellBenefitRateChanged(uint16 rate);

function setChannelBenefitRate(uint16 rate) external virtual onlyRole(DEFAULT_ADMIN_ROLE) returns (bool);
function setSellBenefitRate(uint16 rate) external virtual onlyRole(DEFAULT_ADMIN_ROLE) returns (bool);
```

每个 setter 内部：`rate == 0` revert `ErrorInvalidAmount(0)`、写 storage、emit 对应事件、`return true`。

**理由：**

- **针对性更强**：调用方按需要更新的档单独发起交易，不再依赖 magic number `rateType`，调用现场自解释（`setChannelBenefitRate(40)` 而非 `changeBenefitRate(2, 40)`）。
- **下游扩展无需 override**：GreatLottoCore 想加 invest 档时，只需在自己合约里加一个 `setInvestmentBenefitRate(uint16)` + `InvestmentBenefitRateChanged` 事件，与 base 的两个 setter 并列，无需 override 已有函数、无需重新构造 dispatch 表。
- **事件订阅精确**：链下索引可只订阅 `ChannelBenefitRateChanged` 而不接收所有档变化的混合事件。
- **错位风险消失**：不再存在"调用方传错 rateType 导致改错档"这类潜在事故。

**替代：**

- 保留 `changeBenefitRate(rateType, rate)` 单函数 + dispatch + `virtual`：错位风险存在；下游加档要 override 整个函数；已被否。
- base 只暴露 `_setChannelBenefitRate` / `_setSellBenefitRate` internal、不暴露 external：下游每个都得自己包一层 + 写权限校验 + 写事件，重复成本不降反升，弃用。

**Breaking：** 取代历史 `changeBenefitRate(rateType, rate)` 函数与 `BenefitRateChanged(rateType, rate)` 事件。两个下游主网均未部署，仅影响测试网 / 测试用例 / 下游 governance UI；Phase 2 / 3 适配时同步切换。

### D11 — 抽象"渠道+DAO 两段分润"为基类 helper

**选择：** 新增

```solidity
/// @return netAmount = amountByCoin - 渠道分润 - sell 分润；caller 自由决定净值去向
function _distributeChannelAndDaoBenefits(
    ICoinBase coin,
    uint amountByCoin,
    uint256 channelId
) internal returns (uint netAmount) {
    (uint channelBenefit, ) = _getBenefitByRate(amountByCoin, channelBenefitRate);
    (uint sellBenefit, ) = _getBenefitByRate(amountByCoin, sellBenefitRate);

    uint daoBenefit;
    if (channelId > 0) {
        _channelBenefitTransfer(coin, channelBenefit, channelId);
        daoBenefit = sellBenefit;
    } else {
        // 无渠道时，名义渠道分润合并进 DAO
        daoBenefit = sellBenefit + channelBenefit;
    }

    if (daoBenefit > 0) {
        _daoBenefitTransfer(coin, daoBenefit);
    }

    netAmount = amountByCoin - channelBenefit - sellBenefit;
}
```

**理由：** 这段 pipeline 在 ScratchCard `_afterCollectForBuy` 与 GreatLottoCore `_collect` 中是**逐字一致**的：

- 都按相同 `amountByCoin` 基数计算 `channelBenefit` / `sellBenefit`；
- 都用 `channelId > 0` 决定渠道分润流向；
- 都在 `channelId == 0` 时把 channelBenefit 并入 DAO 一起打款。

唯一差异在 pipeline 末端：ScratchCard 用 net 打给 creator，GreatLottoCore 用 net 入 `_normalPool`。差异由 caller 接住返回的 `netAmount` 自行处置，helper 不耦合到下游业务结构。

GreatLottoCore 的 invest 档（基数也是原始 `amountByCoin`）由 caller 在调 helper **之前**先扣除并打款到 `InvestmentBenefitPoolAddress`，与 helper 解耦：

```solidity
// GreatLottoCore._collect
(uint _investmentBenefit,) = _getBenefitByRate(amountByCoin, investmentBenefitRate);
_transferTo(coin, InvestmentBenefitPoolAddress, _investmentBenefit);

uint netAfterChannelDao = _distributeChannelAndDaoBenefits(coin, amountByCoin, channelId);
uint netAmount = netAfterChannelDao - _investmentBenefit;
_normalPoolUp(netAmount);

_mintDaoCoinToPayer(payer, amountByCoin);
```

**关于事件：** helper 不 emit 单独的"分润金额"事件——两边现行实现都不 emit，链下从外币 transfer 事件推断；本次保持现状以避免事件 schema 与下游业务事件冲突。如有需要，下游可在调用 helper 后自行 emit。

**替代：**

- 不抽：两边维持 ~10 行重复代码、未来若改"无渠道时合并"的策略要双仓改两次，弃用。
- 把 invest 档也包进 helper：base 不持有 `investmentBenefitRate`，污染 ScratchCard，弃用（同 D5）。
- 在 helper 内 emit 通用 `BenefitDistributed(channelId, channelBenefit, daoBenefit, net)` 事件：会强加 schema 给所有下游，且当前两边都没需要，YAGNI，弃用。

### D7 — 保留 `_daoBenefitTransfer` / `_mintDaoCoinToPayer` 封装

**选择：** 两个 helper 都保留为 `internal`。

**理由：** 都只是对底层调用的语义化包装（`_daoBenefitTransfer` = `_transferTo(coin, DaoBenefitPoolAddress, amount)`，`_mintDaoCoinToPayer` = `IDaoCoin(DaoCoinAddress).mintToUser(...)`），但命名表达了"给 DAO 利润池打款" / "给买家增发治理币"的业务意图，让下游调用现场可读性更高，几乎零体积成本。

### D8 — `IPrizePoolBase` 接口放在 infrastructure

**选择：** 新增 `infrastructure/contracts/interfaces/IPrizePoolBase.sol`，下游删除自己仓的同名接口（Phase 2/3 处理）。

**理由：** 接口与基类同源，避免漂移；下游的 abstract `PrizePoolBase` 与 concrete `PrizePool` 都通过 `is IPrizePoolBase` 暴露事件与函数声明给前端 ABI 消费。

### D9 — 构造参数化分润率默认值

**选择：** `channelBenefitRate` / `sellBenefitRate` 不在 base 写死出厂值，构造函数收两个 `uint16 initialChannelRate, uint16 initialSellRate` 参数：

```solidity
constructor(
    address coin,
    address daoCoinAddr,
    address daoBenefitPoolAddr,
    address salesChannelAddr,
    address _owner,
    uint16 initialChannelRate,
    uint16 initialSellRate
) AccessControlPartnerContract(_owner) { ... }
```

**理由：** ScratchCard 当前默认 `(30, 70)`，GreatLottoCore 当前默认 `(20, 30)`——base 写死任一边都会让另一边偷偷变更默认值（要靠 `changeBenefitRate` 后置修复），是潜在事故源。构造参数化一次性解决。

**替代：** base 内 `= 30` / `= 70`，下游构造内 `channelBenefitRate = 20; sellBenefitRate = 30;` 覆盖——能 work 但 storage 写两次浪费 gas，且语义不直接，弃用。

### D10 — base 继承链：`AccessControlPartnerContract, IPrizePoolBase`

**选择：**

```solidity
abstract contract PrizePoolBase is AccessControlPartnerContract, IPrizePoolBase { ... }
```

**理由：**

- `AccessControlPartnerContract` 已经 `is AccessControl, IErrorsBase`，因此 `DEFAULT_ADMIN_ROLE` / `PARTNER_CONTRACT_ROLE` / `ErrorInvalidAmount` / `ErrorInsufficientBalance` / `ErrorPaymentUnsuccessful` / `ErrorZeroAddress` 全部直通可用。
- 不内置 `NoDelegateCall` / `DeadLine`：奖池基类的 helper 全部是 `internal`，由调用它的 `external` / `public` 函数决定是否需要 `noDelegateCall` / `checkDeadline`，在 base 强制一种会让下游失去灵活性。

## Risks / Trade-offs

| 风险 | 缓解 |
|---|---|
| Storage layout：base 持有 4 个 immutable + 2 个 storage（channelBenefitRate / sellBenefitRate）；下游 PrizePool 现行未启用代理升级，但 GreatLottoCore 适配时把这 2 个 storage 从 child 移到 parent 会改变 slot 位置 | Phase 3 任务 grep 确认无 Initializable / UUPS / Proxy；同时下游 PrizePool 是一次性部署合约，无 layout 兼容压力。Phase 1 不触及下游 → 风险延后到 Phase 3 处理 |
| `_transferTo` 后置校验在 GreatLottoCore 引入 false revert（如某些 ERC20 在 transfer 后 balanceOf 可能因第三方 mint/burn 出现意外漂移）| GLC 在 infra 内为标准 SafeERC20；Phase 1 单元测试覆盖正常 transfer 路径不 revert；Phase 3 任务再做端到端集成测试。后置校验是 ScratchCard 已生产使用过的语义，并非新增风险 |
| 拆分 setter 是 BREAKING，下游适配时若漏改 governance 调用现场会运行时 revert（unknown function selector）| 主网未部署，仅影响测试网与测试用例；Phase 2/3 grep 全部 `changeBenefitRate(` 调用点同步替换；前端 ABI 重新生成即可静态发现遗漏 |
| Base 体积膨胀进入下游 → 突破 EIP-170 24576 字节限制 | base 主要由 7 个 helper 组成（ScratchCard 当前编译合约大小约 17.4 KiB，base 抽出后下游净减；本次 base 新增的 only 是 IPrizePoolBase 接口元数据 + 严格 `_transferTo` 后置 check 两条 SLOAD）。Phase 1 任务中跑 contract sizer 验证；Phase 2/3 跑下游 contract sizer 回归 |
| 依赖循环：base 反向引用下游接口 | base 只引用 infra 内 `ICoinBase` / `IDaoCoin` / `ISalesChannel` / `IErrorsBase` / `IPrizePoolBase`，全部已在 infra 仓内，物理上不可能形成循环依赖 |
| 测试覆盖盲区：internal helper 不能直接从 JS 调 | 通过 `PrizePoolBaseHarness` 测试合约把每个 internal helper 包成 external wrapper；harness 在 `contracts/test/` 子目录与生产代码物理隔离 |

## Migration Plan

本提案只覆盖 Phase 1（infra 内部落地）。完成顺序：

1. 创建 `IPrizePoolBase.sol`（拷自 ScratchCard 现有接口，内容不变）。
2. 创建 `PrizePoolBase.sol`（移植 ScratchCard 实现 + 应用 D1–D10 决策）。
3. 创建 `PrizePoolBaseHarness.sol`（测试 only）。
4. 写 `PrizePoolBase.test.js` 全覆盖。
5. `npx hardhat compile` + `npx hardhat test` + `npx hardhat coverage` 全绿。
6. PR 合入 main → 工作区 pnpm 软链下游仓自动看到新基类（无需发版）。

下游 Phase 2 / 3 在各自仓单独提案，与本 change 解耦。

**Rollback：** Phase 1 PR 单独合入；若下游 Phase 2 / 3 在适配时发现基类设计有问题，可在 infra 仓发起 fix change 修补，不需要回滚整个 base。基类未被任何已部署合约引用之前，回滚等同于删除两份新文件 + 一份测试。

## Open Questions

- **是否同时提供 `_collectForIssue` / `_collectForBuy` 模板方法？** 当前 ScratchCard `PrizePool.sol`（concrete）持有这两个 `_collectForBuy` 重载，封装了"渠道分润 + 销售分润 + creator 打款 + DAO 治理币增发"的 pipeline。GreatLottoCore 的 `_collect` 末端去向不同（进 `_normalPool` 而非打给 creator），强行模板化会损可读性。**结论：保持 §6 后续可选优化，不在 Phase 1 范围**。
- **分润率上限是否应该 base 内置 cap（如 ≤ 1000 等于 100%）？** 当前两边都没有 cap，rate=1000 会让 net=0。**结论：保持当前行为，不在 Phase 1 加 cap**——这属于业务策略而非基础工具，加 cap 反而锁死下游灵活性；若需要 cap 后续作为独立 change 推进。
