# 销售分润机制改造：DAO → ERC4626 金库

> 状态：设计草案（待 `/flow-review-spec` 方案 review）
> 范围：**跨仓**（infrastructure 上游打穿 → ScratchCard + GreatLottoCore + interface）
> 日期：2026-06-22
> change-id 建议：`2026Q2-sales-vault-replace-dao`

---

## 1. 背景与目标

### 1.1 现状（要拆掉的 DAO 机制）

当前「销售利润」经一套 DAO 分红机制下发：

- **`DaoCoin`（GLDC，ERC20Votes）**：每次购买，奖池经 `PrizePoolBase._mintDaoCoinToPayer(payer, assets)` 给**买家**按 `assets / coinPrice` 增发治理币份额。
- **`BeneficiaryBase`**：维护「持有 ≥10k GLDC」的受益人列表（`_beneficiaryList`），每次 GLDC 转账经 `_update` 钩子动态增删。
- **`DaoBenefitPool`（`is BenefitPoolBase`）**：销售分润（sell 档）打入此池；任何人调 `executeBenefit(deadline)` 时，把池内全部 GLC 按 `balance / totalSupply` **遍历受益人列表** pro-rata 转出。
- **分润 pipeline `PrizePoolBase._distributeChannelAndDaoBenefits`**：把购买金额拆 `channelBenefit`（渠道）+ `sellBenefit`（销售→DAO 池），无渠道时渠道档并入 DAO 池。

涉及合约（infrastructure）：`DaoCoin.sol` / `DaoBenefitPool.sol` / `base/BenefitPoolBase.sol` / `base/BeneficiaryBase.sol` / `base/PrizePoolBase.sol` 及接口 `IDaoCoin` / `IBeneficiaryBase` / `IBenefitPoolBase`。

### 1.2 目标（4 条需求）

1. **去掉 DAO 机制**：购买时不再给买家增发 GLDC 份额。
2. **销售利润金库化**：把「销售利润」改造成一个继承 OZ **ERC4626** 的金库（vault）。
3. **所有销售分润打给该金库**：原先打入 `DaoBenefitPool` 的那一档（sell 档，无渠道时含 channel 档），改为打入金库。
4. **份额上限 1 亿 + owner 初始全持**：金库份额 totalSupply 上限 `100_000_000`（按 18 位小数），部署时 owner 一次性铸满全部份额。

### 1.3 一句话方案

用一个 **`SalesVault is ERC4626`** 合约替换 `DaoBenefitPool`，资产币为 GLC；销售分润直接 `safeTransfer` 进金库（= 给所有现存份额持有人按比例增值，无需主动分发）；份额在部署时一次性铸给 owner（固定 1 亿，之后增发入口关闭）；同时删除 `_mintDaoCoinToPayer` 调用与 GLDC 赠予逻辑。

---

## 2. 关键设计决策

### D1：金库的「分润」语义 —— 转入即增值，不主动分发

ERC4626 的核心恒等式是 `convertToAssets(shares) = shares * totalAssets / totalSupply`，其中 `totalAssets = asset.balanceOf(vault)`（默认实现）。

- **销售分润 = 直接把 GLC `safeTransfer` 进金库地址**。这会抬高 `totalAssets` 而不动 `totalSupply`，于是**每一份额对应的资产自动增值**。
- 份额持有人**无需** `executeBenefit` 这类主动分发；任何时候调 `redeem(shares)` / `withdraw(assets)` 即按当前比例取走对应 GLC。
- 这从根本上去掉了 `BenefitPoolBase` 的「遍历受益人列表逐个 transfer」模式（O(n) gas、列表维护、≥10k 门槛），换成 ERC4626 的纯比例账本（O(1)）。

> **结论**：金库不需要 `executeBenefit`。删除 `DaoBenefitPool` + `BenefitPoolBase` + `BeneficiaryBase` 整条链路。

### D2：份额硬上限 1 亿 + owner 初始全持 + 开放公众现价申购（offset=6 防护）

> **✅ 已定稿（用户决策 2026-06-22）**：开放标准 ERC4626 公众 `deposit`/`mint`，靠 `_decimalsOffset() = 6` 的 virtual shares 防 inflation attack。**不设 owner-only 补铸**——补回 supply 只能走「公众按现价存入 GLC」（含 owner 自己）。

落地规则：

- 部署时构造 `_mint(owner, MAX_SHARES)`，`MAX_SHARES = 100_000_000 * 1e18`，初始 `totalSupply == 1 亿`，owner 全持（满足原需求）。
- **公众 `deposit`/`mint` 开放**：任何人按 ERC4626 现价（`assets * totalSupply / totalAssets`）存 GLC 换份额。现价申购**不稀释**现有持有人、也**不白嫖**存量分润（比例账本保证），见下方 §「为什么开放申购在稳态安全」。
- **1 亿硬上限**：在申购路径 override `maxDeposit(addr)` / `maxMint(addr)` 返回「按当前比例还能再铸到 1 亿的额度」；顶满（`totalSupply == MAX_SHARES`）时返回 0 → OZ 的 `deposit`/`mint` 会因 `assets/shares > max` 而 revert（`ERC4626ExceededMaxDeposit`/`Mint`）。
  - ⚠️ **初始即满**：部署铸满 1 亿后 `maxDeposit == 0`，公众想存**必须先有人 redeem 腾出空间**。这是「硬上限」的预期行为，需在前端/文档明示，否则用户会困惑「为什么 deposit 总是 revert」。
- **`_decimalsOffset()` 返回 6**：开放公众申购的**强制安全前提**（见 D2b）。
- redeem/withdraw 标准开放（D3），赎回 `_burn` 减 supply、腾出申购额度。

#### D2b：为什么开放申购在稳态安全，以及 offset=6 防的是什么

- **稳态（supply 远大于 0）无套利**：`deposit` 按当前 `totalSupply/totalAssets` 比例给份额。若单份额已因分润值 1.5 GLC，存 1500 GLC 拿 1000 份额——正好等值，不白嫖存量分润、不稀释他人。这是 ERC4626 的设计目的。
- **风险只在 supply→极低时（inflation attack）**：攻击者抢首存 1 wei 拿极少份额，再向金库**直接捐赠**大额 GLC 抬高单份额价格，使后续正常存入者因取整 `shares==0`、本金被攻击者份额吞掉。
- **offset=6 的作用**：换算式 `shares = assets.mulDiv(totalSupply + 10**6, totalAssets + 1)` 里那 `10**6` virtual shares + `+1` virtual asset，相当于金库自带一个打不死的影子底仓，把捐赠抬价所需成本放大约 `10**6` 倍 → inflation attack 不可行。OZ 官方对开放申购金库即推荐此值。
- **本金库的额外缓冲**：初始 supply 即 1 亿、且公众申购前必有人先 redeem——supply 实际很难被拉到 0 附近（要先赎掉接近 1 亿份额）。offset=6 是叠加保险。

### D3：是否保留 ERC4626 的 `withdraw`/`redeem` 给 owner 提取？

需求只说「owner 拥有全部份额」，没说提取方式。两个选项：

- **选项 A（推荐）**：保留 ERC4626 标准 `redeem`/`withdraw`。owner（份额持有人）随时可按比例赎回 GLC。份额可转让（ERC20），天然支持「把销售收益权分给多个受益人 / 二级流转」。这正是金库化的意义。
- 选项 B：禁用 `redeem`/`withdraw`，只留 owner 专用 `sweep()`。更简单但放弃了「份额 = 可流转的收益权」这一 ERC4626 价值。

**✅ 已定稿（用户决策 2026-06-22）：选项 A —— 标准 `redeem`/`withdraw` 对所有份额持有人开放。** owner 及二级受让人凭份额按比例 `redeem` GLC；份额经 ERC20 transfer 自由二级流转。
>
> **金库为纯无特权 ERC4626**：`deposit`/`mint`/`redeem`/`withdraw` 全部公开（deposit 受 1 亿硬上限约束），**无 owner 后门、无 `topUp`、无 sweep/pause**（用户决策：删 topUp）。owner 的唯一特殊性是「部署时拿到全部初始份额」，运行期与任何持有人等权。

### D4：`PrizePoolBase` 分润 pipeline 改造

`_distributeChannelAndDaoBenefits` 现在把 sell 档（及无渠道时的 channel 档）打入 `DaoBenefitPoolAddress`。改造：

- 把 immutable `DaoBenefitPoolAddress` 改名/替换为 **`SalesVaultAddress`**（语义更准）。
- `_daoBenefitTransfer` → `_salesVaultTransfer`（仅改名 + 目标地址，仍是 `_transferTo(coin, SalesVaultAddress, benefit)`）。
- helper 名 `_distributeChannelAndDaoBenefits` → `_distributeChannelAndSalesBenefits`（或保留旧名减少下游改动——见 D7 权衡）。
- **删除** `DaoCoinAddress` immutable、`_mintDaoCoinToPayer` helper、`import IDaoCoin`。

### D5：构造函数签名变更（破坏性）

`PrizePoolBase` 构造参数从：

```
(coin, daoCoinAddr, daoBenefitPoolAddr, salesChannelAddr, owner_, initialChannelRate, initialSellRate)
```

改为：

```
(coin, salesVaultAddr, salesChannelAddr, owner_, initialChannelRate, initialSellRate)
```

去掉 `daoCoinAddr`（不再增发治理币）；`daoBenefitPoolAddr` → `salesVaultAddr`。

→ 下游两个 `PrizePool.sol`（ScratchCard + Core）构造调用必须同步改。

### D6：GLDC（DaoCoin）的去留

需求 1 只要求「购买时不发份额」，但 GLDC 还兼任**治理投票币（ERC20Votes）**。两个层次：

- **必做**：删除 `PrizePoolBase._mintDaoCoinToPayer` 调用链 →购买不再 mint GLDC。
- **可选（建议本次一并清理）**：若 GLDC 仅用于「分红资格门槛」（`BeneficiaryBase.MIN_BENEFIT_SHARES`），随 DAO 分红机制删除后 GLDC 失去主要用途，可考虑：
  - **保守**：保留 `DaoCoin` 合约本身（治理投票仍可能用到），仅切断奖池增发路径（删 `mintToUser` 的调用方，`DaoCoin` 自身保留 `mint`(onlyAdmin)）。
  - **激进**：若确认治理也不用 GLDC，删 `DaoCoin` + `BeneficiaryBase`。

**✅ 已定稿（用户决策 2026-06-22）：激进方案——连 `DaoCoin` 一起删。** 确认治理不再使用 GLDC。因此删除 `DaoCoin.sol` + `DaoBenefitPool.sol` + `BenefitPoolBase.sol` + `BeneficiaryBase.sol` 及接口 `IDaoCoin` / `IBeneficiaryBase` / `IBenefitPoolBase`，整条 DAO 治理币 + 分红链路从 infrastructure 移除。

> 连带影响：
> - `PrizePoolBase` 删 `DaoCoinAddress` immutable + `import IDaoCoin` + `_mintDaoCoinToPayer`。
> - 部署模块删 `DaoCoin` / `DaoBenefitPool` 部署 + `daoCoinAccess`（给奖池授 GLDC PARTNER 角色）接线。
> - 任何曾 `import "@greatlotto/infrastructure/.../DaoCoin.sol"` 或读 GLDC 余额的下游/前端必须清除（前端见记忆 `interface-abi-drift-dao-benefit.md`）。
> - ⚠️ **回退成本高**：删合约是不可逆的语义收窄；若未来需链上治理须重新引入治理币。已确认不需要，方可推进。

### D7：兼容性权衡 —— 是否保留旧 helper/事件名

为减少下游 churn，可让 `PrizePoolBase` 保留旧 helper 名 `_distributeChannelAndDaoBenefits`（内部打金库），但语义已变。**不推荐**——名字含「Dao」会误导后人。本次是上游打穿的破坏性变更，下游本就要改构造函数，顺手改 helper 名更干净。

---

## 3. 改造范围（按仓）

### 3.1 infrastructure（上游，核心改动）

| 文件 | 改动 |
|---|---|
| `contracts/SalesVault.sol` | **新增**：`is ERC4626, AccessControlPartnerContract`（或仅 Ownable），资产币 GLC，构造铸 1 亿份给 owner |
| `contracts/base/PrizePoolBase.sol` | 改构造签名（去 `daoCoinAddr`，`daoBenefitPool`→`salesVault`）；删 `_mintDaoCoinToPayer` / `DaoCoinAddress` / `import IDaoCoin`；`_daoBenefitTransfer`→`_salesVaultTransfer`；helper 改名 |
| `contracts/interfaces/IPrizePoolBase.sol` | 若分润事件有变则同步（当前 helper 不 emit，链下从 ERC20 Transfer 推断，**无需改事件**） |
| `contracts/DaoBenefitPool.sol` | **删除** |
| `contracts/base/BenefitPoolBase.sol` | **删除** |
| `contracts/base/BeneficiaryBase.sol` | **删除**（依赖 D6 确认；若删则 `DaoCoin` 改纯 ERC20Votes） |
| `contracts/DaoCoin.sol` | 删 `mintToUser`（奖池增发入口）；按 D6 决定是否解除 `BeneficiaryBase` |
| `contracts/interfaces/{IDaoCoin,IBeneficiaryBase,IBenefitPoolBase}.sol` | 按上面删除对应声明/文件 |
| `ignition/modules/infrastructure.js` | 删 `DaoBenefitPool` 部署，新增 `SalesVault`（构造传 GLC + owner）；`DaoCoin` 按 D6 去留 |
| `test/foundry/*` | 删 DaoBenefitPool/Beneficiary 相关测试，新增 SalesVault 测试：初始铸满 1 亿 / 分润转入抬升单份额价值 / redeem 按比例 / **deposit 受 1 亿硬上限（初始即满→revert，redeem 后可 deposit）** / **inflation-attack 序列（大额 redeem→supply 极低→恶意 deposit+捐赠→后续存入者份额不被吞，验证 offset=6 防护）** / maxDeposit 换算取整不超限（fuzz） |

### 3.2 ScratchCard（下游）

| 文件 | 改动 |
|---|---|
| `contracts/PrizePool.sol` | 构造调用对齐新签名（去 daoCoin 参数，传 salesVault 地址）；`_afterCollectForBuy` 删 `_mintDaoCoinToPayer(buyer, amountByCoin)`；helper 改名同步 |
| `ignition/modules/ScratchCard*.js` | 传 SalesVault 地址替代 DaoBenefitPool；去 DaoCoin 接线（`daoCoinAccess` PARTNER 授权可删） |
| `test/foundry/PrizePool.t.sol` 等 | 删「购买后 buyer 持有 GLDC」断言；分润断言改为「金库 GLC 余额 += sellBenefit」 |
| `CLAUDE.md` | 更新分润机制描述 |

### 3.3 GreatLottoCore（下游）

| 文件 | 改动 |
|---|---|
| `contracts/PrizePool.sol` | 同 ScratchCard：构造对齐、删 `_mintDaoCoinToPayer`、helper 改名。注意其 `_collect` 还有 INVESTOR 68% 档，**不受影响**（投资分润是独立机制，走 `_accrueInvestorBenefit`，与本次 DAO 改造正交） |
| `ignition/modules/GreatLottoCore*.js` | 同 ScratchCard |
| `test/runTest/*` | 同步断言 |

### 3.4 interface（前端）

| 改动 |
|---|
| 删除 DAO 分红相关页面/hook（`executeBenefit`、GLDC 余额展示、受益人列表）——参见记忆 `interface-abi-drift-dao-benefit.md`（这些 hook 已多次与 ABI 漂移） |
| 同步新 ABI：`SalesVault.json`（替代 `DaoBenefitPool.json`）、更新 `PrizePool.json` / `DaoCoin.json` |
| `address.json` 加 `SalesVault` 地址 |
| 若产品需要：新增金库视图（owner 可见累积分润 = `convertToAssets(balanceOf(owner))`、redeem 入口） |

---

## 4. SalesVault 合约草图

```solidity
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title SalesVault
/// @notice 销售利润金库。资产币为 GLC；份额硬上限 1 亿，部署时全部铸给 owner。
///         销售分润由各 PrizePool 直接 `safeTransfer` GLC 进本合约 —— 抬高 totalAssets、
///         不动 totalSupply，使每份额按比例增值。份额持有人凭 ERC4626 `redeem`/`withdraw`
///         按比例提走累积的 GLC。
/// @dev    **纯无特权 ERC4626**：deposit/mint/redeem/withdraw 全公开、无 owner 后门。
///         deposit/mint 受 1 亿硬上限约束（maxDeposit/maxMint 返回剩余额度，顶满即 0 → OZ revert）。
///         `_decimalsOffset()=6` 提供 virtual shares 防 inflation attack（开放申购的强制前提）。
///         owner 仅在部署时拿到全部初始份额，运行期与任意持有人等权。
contract SalesVault is ERC4626 {

    uint256 public constant MAX_SHARES = 100_000_000 * 1e18; // 1 亿份硬上限

    constructor(address asset_, address owner_)
        ERC20("GreatLotto Sales Vault", "GLSV")
        ERC4626(IERC20(asset_))
    {
        _mint(owner_, MAX_SHARES);
    }

    /// @dev virtual shares 防 inflation attack —— 开放公众申购的强制安全前提。
    function _decimalsOffset() internal pure override returns (uint8) {
        return 6;
    }

    // —— 1 亿硬上限：把「还能再铸多少份额」换算成 assets/shares 额度 ——
    //     顶满（remaining==0）时返回 0 → OZ deposit/mint 因超 max 而 revert
    //     ERC4626ExceededMaxDeposit / ExceededMaxMint。
    function maxMint(address) public view override returns (uint256) {
        uint256 supply = totalSupply();
        return supply >= MAX_SHARES ? 0 : MAX_SHARES - supply;
    }

    function maxDeposit(address) public view override returns (uint256) {
        return _convertToAssets(maxMint(address(0)), Math.Rounding.Floor);
    }

    // redeem / withdraw 保留 ERC4626 默认实现（份额持有人按比例提走 GLC，无门槛）
}
```

> 说明：
> - **上限锚定 shares 而非 assets**：`maxMint` 直接用 `MAX_SHARES - totalSupply()`（份额是被限的量），`maxDeposit` 再换算成对应 assets。这样无论金库累积多少分润（totalAssets 抬升），上限始终精确卡在 1 亿**份额**。
> - `Math` 需 `import "@openzeppelin/contracts/utils/math/Math.sol"`（与 ERC4626 内部同源）。
> - **初始即满 → `maxDeposit == 0`**：部署后公众无法立即 deposit，须先有人 redeem。前端须明示此行为（见 D2）。
> - 无 `Ownable`、无自定义 error——deposit 顶满走 OZ 原生 `ERC4626ExceededMaxDeposit` revert。
> - `MAX_SHARES` 与 GLC 小数（18）一致；若 GLC underlying 实际是 USDC(6) 经 `getAmount` 放大为 18，资产侧已统一 18 位，`convertTo*` 比例计算无误差风险——但需在测试中验证 `getAmount` 单位贯通（金库收的是 wei 级 GLC）。

---

## 5. 风险与边界

| 风险 | 说明 | 缓解 |
|---|---|---|
| **构造签名破坏性变更** | 上游打穿，两下游 PrizePool + 三仓部署模块必须同步，漏改即编译失败/部署错配 | 跨仓流程 + 一次性原子推进；CI 全绿门 |
| **GLDC 语义残留** | 若前端/治理仍读 GLDC 余额做权限，删 `mintToUser` 后用户余额冻结在历史值 | D6 确认治理去留；前端清理 DAO hook |
| **金库单位贯通** | PrizePool 转入的是 `getAmount` 放大后的 wei 级 GLC；ERC4626 `asset` 必须是同一 GLC 地址 | 测试断言金库余额 = 转入 wei；不在金库内再做 getAmount |
| **ERC4626 inflation attack** | 开放公众 deposit 后，supply 被赎到极低时攻击者可抢首存 + 捐赠抬价、吞掉后续存入者本金 | `_decimalsOffset()=6` virtual shares（OZ 推荐值）+ 初始 supply 1 亿（公众申购前须先大额 redeem 才可能逼近 0）。**测试必须覆盖 supply→极小 的 redeem→deposit 攻击序列** |
| **初始即满致 deposit 总 revert** | 部署铸满 1 亿 → `maxDeposit==0`，公众 deposit 立即 revert，易被误判为 bug | 前端/文档明示「须先有人 redeem 腾出额度」；属硬上限的预期行为 |
| **上限换算精度** | `maxDeposit` 由 `maxMint` 经 `_convertToAssets` 换算，取整可能让 deposit 极限附近差 1 wei | 上限锚定 shares（`MAX_SHARES - totalSupply`）精确；assets 侧 floor 取整偏保守（宁可少铸不超限），不破坏 1 亿硬上限 |
| **首存比例锚定** | owner 持全部份额、首次转入前 totalAssets 可能为 0 | 部署即铸满 → totalSupply 从一开始就是 1 亿，无 0 supply 窗口；首笔分润转入即正常增值 |
| **已部署网络迁移** | 31337/sepolia/holesky 已部署旧 DaoBenefitPool | 本套合约重新部署；旧部署作废（与既往 feature 分支重部署一致） |

---

## 6. 决策记录（已定稿 2026-06-22）

1. **GLDC（DaoCoin）治理是否保留？** → **激进：连 `DaoCoin` 一起删**。治理不再用 GLDC，删整条治理币 + 分红链路（`DaoCoin` / `DaoBenefitPool` / `BenefitPoolBase` / `BeneficiaryBase` + 接口）。
2. **金库提取/治理模型？** → **纯无特权 ERC4626**：deposit/mint/redeem/withdraw 全公开，无 owner 后门、无 topUp、无 sweep。
3. **`redeem`/`withdraw` 开放对象？** → 对所有份额持有人开放（D3 选项 A）。
4. **份额可转让性？** → 允许 ERC20 二级流转（不加转让限制）。
5. **1 亿上限怎么守？** → **硬上限 + 开放公众现价申购**：`deposit`/`mint` 公开但受 `maxDeposit`/`maxMint` 卡在 1 亿份额；redeem 腾出空间后任何人可按现价补回（含 owner）。无 owner-only 补铸。
6. **开放申购的安全前提？** → `_decimalsOffset() = 6` 防 inflation attack（强制）；部署即铸满 1 亿，公众须先 redeem 才能 deposit。

> 全部待确认项已锁定，方案可进入 `/flow-review-spec`。

---

## 7. 实施顺序（建议）

1. infrastructure：新增 `SalesVault.sol` + 改 `PrizePoolBase` + 删 DAO 分红链路 + 测试 → 本仓 `forge test` 绿。
2. 发包/更新 symlink（下游消费新 `PrizePoolBase`）。
3. ScratchCard + Core：对齐构造、删 `_mintDaoCoinToPayer`、改部署模块、改测试 → 各仓测试绿。
4. interface：删 DAO hook、同步 ABI、加金库视图。
5. 三道 review 门：`/flow-review-spec` → `requesting-code-review` → `/security-review`（合约仓必跑）。
```
