# Tasks

> 本 change 仅覆盖 **infrastructure** 仓（任务组 1–5）。下游 ScratchCard / GreatLottoCore / interface 适配各自单独 change，见任务组 6 的协调清单与 `.claude-workspace/coordination/2026Q2-sales-vault-replace-dao.md`。

## 1. SalesVault 合约（新增）

- [x] 1.1 新增 `contracts/SalesVault.sol`：`is ERC4626`，构造 `(address asset_, address owner_)`，`ERC20("GreatLotto Sales Vault","GLSV")` + `ERC4626(IERC20(asset_))`，构造内 `_mint(owner_, MAX_SHARES)`，`MAX_SHARES = 100_000_000 * 1e18`。
- [x] 1.2 override `_decimalsOffset()` 返回 `6`（virtual shares 防 inflation attack）。
- [x] 1.3 override `maxMint(address)` 返回 `totalSupply() >= MAX_SHARES ? 0 : MAX_SHARES - totalSupply()`；override `maxDeposit(address)` 返回 `_convertToAssets(maxMint(address(0)), Math.Rounding.Floor)`（import `@openzeppelin/.../utils/math/Math.sol`）。
- [x] 1.4 不继承 Ownable/AccessControl，不加 topUp/sweep/pause——保持纯无特权 ERC4626。
- [x] 1.5 确认合约体积在 EIP-170 限制内（`npx hardhat compile` + contractSizer）。

## 2. PrizePoolBase 改造（破坏性）

- [x] 2.1 构造签名 `(coin, daoCoinAddr, daoBenefitPoolAddr, salesChannelAddr, owner_, chRate, sellRate)` → `(coin, salesVaultAddr, salesChannelAddr, owner_, chRate, sellRate)`；删 `DaoCoinAddress` immutable，`DaoBenefitPoolAddress` 改名为 `SalesVaultAddress`。
- [x] 2.2 删 `import "../interfaces/IDaoCoin.sol"` 与 `_mintDaoCoinToPayer(address,uint256)` helper。
- [x] 2.3 `_daoBenefitTransfer` → `_salesVaultTransfer`（仅改名 + 目标 `SalesVaultAddress`，逻辑不变）。
- [x] 2.4 `_distributeChannelAndDaoBenefits` → `_distributeChannelAndSalesBenefits`（计算与渠道档逐字不变，sell 档目标改 `_salesVaultTransfer`）。
- [x] 2.5 核对 `IPrizePoolBase`：本次不增删事件（分润不 emit 独立事件，链下从 ERC20 Transfer 推断）；确认无遗留 DAO 相关声明。
- [x] 2.6 更新 `PrizePoolBase` / 相关接口的 NatSpec 注释（DAO → 销售金库语义）。

## 3. 删除 DAO 治理币 + 分红链路

- [x] 3.1 删除 `contracts/DaoCoin.sol` + `contracts/interfaces/IDaoCoin.sol`。
- [x] 3.2 删除 `contracts/DaoBenefitPool.sol` + `contracts/interfaces/IBenefitPoolBase.sol`。
- [x] 3.3 删除 `contracts/base/BenefitPoolBase.sol`。
- [x] 3.4 删除 `contracts/base/BeneficiaryBase.sol` + `contracts/interfaces/IBeneficiaryBase.sol`。
- [x] 3.5 全仓 grep 确认无残留 import / 引用（`DaoCoin` / `DaoBenefitPool` / `BenefitPoolBase` / `BeneficiaryBase` / `IDaoCoin` / `IBeneficiaryBase` / `IBenefitPoolBase`）。

## 4. 部署模块

- [x] 4.1 `ignition/modules/infrastructure.js`：删 `DaoCoin` / `DaoBenefitPool` 部署；新增 `SalesVault`（构造 `[greatLottoCoin, owner]`）；从返回对象移除 daoCoin/daoBenefitPool、加入 salesVault。
- [x] 4.2 删除任何对 `DaoCoin` 授 `PARTNER_CONTRACT_ROLE` 的接线（daoCoinAccess 之类）。N/A：infrastructure.js 原本无此接线（daoCoinAccess 在下游 ScratchCard/Core local 模块，归各自下游 change）。
- [x] 4.3 更新 `ignition/parameters/*.json` 注释 / README（不再需要 daoCoin/daoBenefitPool 相关参数）。

## 5. Foundry 测试

- [x] 5.1 删除 DaoBenefitPool / DaoCoin / BeneficiaryBase 相关测试用例。
- [x] 5.2 新增 `SalesVault.t.sol`：初始铸满 1 亿给 owner / `asset()` 与 GLC 对齐 / 转入抬升单份额价值 / `redeem` 按比例 / 份额可转让。
- [x] 5.3 新增上限测试：初始即满 → `deposit`/`mint` revert；`redeem` 后可 `deposit`；`maxDeposit`/`maxMint` 换算正确；铸后不超 `MAX_SHARES`（fuzz 极限附近）。
- [x] 5.4 新增 **inflation-attack 序列测试**：大额 `redeem` → supply 极低 → 恶意 `deposit` 极小额 + 直接捐赠抬价 → 验证正常用户随后 `deposit` 份额不被吞为 0、攻击者不净获利（offset=6 防护生效）。
- [x] 5.5 更新依赖 `PrizePoolBase` 的现有测试（构造签名 + helper 改名 + 分润目标改金库；断言「分润后金库 GLC 余额 += sellBenefit」替代「DAO 池余额 += sellBenefit」；删「买家持有 GLDC」断言）。
- [x] 5.6 `forge test` 全绿（123 passed / 0 failed）；`npx hardhat compile` 通过、SalesVault 体积 4.175 KiB（EIP-170 内）。`forge coverage` 报告留待安全 review 前补跑。

## 6. 跨仓协调（本 change 不落下游代码，仅锁清单与顺序）

- [x] 6.1 创建协调文档 `.claude-workspace/coordination/2026Q2-sales-vault-replace-dao.md`：列依赖顺序 infrastructure → 发包/symlink → {ScratchCard, GreatLottoCore} → interface，及每仓 change-id 占位。
- [x] 6.2 ScratchCard 下游 change：**移交协调文档跟踪**（独立仓 change，不在本 infra change 落代码）。清单：`PrizePool.sol` 构造对齐、删 `_mintDaoCoinToPayer`、helper 改名；部署模块去 DaoCoin、传 SalesVault 地址；测试断言改动；`CLAUDE.md` 分润机制描述更新。
- [x] 6.3 GreatLottoCore 下游 change：**移交协调文档跟踪**。同 ScratchCard；显式记录 INVESTOR 68% 档正交不动。
- [x] 6.4 interface 下游 change：**移交协调文档跟踪**。删 DAO 分红 hook、同步 ABI（加 `SalesVault.json`、删 `DaoCoin.json`/`DaoBenefitPool.json`、更新 `PrizePool.json`）、`address.json` 加 SalesVault、可选金库视图。

## 7. 收尾门

- [x] 7.1 `openspec validate sales-vault-replace-dao --strict` 通过。
- [x] 7.2 三道 review 门全过：方案 `/flow-review-spec`（approved 6/6 PASS，修一处 delta 结构瑕疵）→ 代码 `/code-review`（无真实 bug，cap-over-mint 经证明 REFUTED）→ 安全 `/security-review`（无 HIGH/MEDIUM）。
