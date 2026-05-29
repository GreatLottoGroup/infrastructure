## Why

业务侧已决定下线 ETH 支付通道，仅保留稳定币（GLC）一条轨道，并且 **同步下线 DAI**——稳定币列表收敛为 USDT + USDC。基础设施层是依赖根，需要先把 `GreatLottoEth` / 双轨 `DaoBenefitPool` / `DaoCoin` 双价格 / `GreatLottoCoin` DAI 入金分支 / `SelfPermit` 中的 DAI permit 接口五个组件一次性收敛，下游 `GreatLottoCore` 与 `ScratchCard` 才能跟进。完整跨仓方案见 [`doc/remove-eth-support-plan.md`](../../../doc/remove-eth-support-plan.md)（v2 已纳入 DAI 下线）。

新链全新部署，没有需要迁移的链上 GLETH / GLDC / DAI 入金历史余额，因此本次按 **Breaking Change** 处理，不保留兼容字段。

## What Changes

### 删除（彻底下线）

- `contracts/GreatLottoEth.sol`、`contracts/interfaces/IGreatLottoEth.sol`、`contracts/test/GreatLottoEthTest.sol`
- `contracts/test/PartnerTest.sol` 中所有 GLETH mint 入口
- `contracts/interfaces/IERC20PermitAllowed.sol`（DAI/CHAI permit 专用接口，已无消费方）
- `test/utils/getCoin.js` 中 `DAI_ADDRESS` / `getDAICoin` / `approveDAICoin` / `DAI_DECIMALS` / `DAI_ABI` 等 helper；`test/utils/permitUtils.js` 中针对 DAI 的分支；`test/scripts/initTestCoin.js` / `approveTestCoin.js` 中 DAI 调用；`test/abi/dai_abi.json` 与 `test/abi/weth_abi.json`（GLETH 下线后 WETH ABI 也无消费方）

### 接口收敛（**BREAKING**）

- `DaoCoin`：删除 `coinPriceEth` 状态、`mintToUser(... bool isEth)` / `changePrice(... bool isEth)` 的 isEth 分支与第二个参数；`event PriceChanged(price, isEth)` → `PriceChanged(price)`。
- `IDaoCoin`：同步签名。
- `BenefitPoolBase`：删除 `GreatLottoEthAddress` / `GovernEthAddress` immutable；`executeBenefit(bool isEth, uint deadline)` → `executeBenefit(uint deadline)`；`event BenefitExecuted(executor, isEth, total)` → `BenefitExecuted(executor, total)`。
- `IBenefitPoolBase`：同步签名。
- `DaoBenefitPool`：构造函数从 `(coin, eth, dao)` → `(coin, dao)`。
- `GreatLottoCoin._tokens`：mainnet / sepolia 两套数组都从 `[USDT, USDC, DAI]` 收敛为 `[USDT, USDC]`；`mint(token, amount, payer, deadline, v, r, s)` 中 `if(token == _tokens[2]) selfPermitAllowedIfNecessary(...)` 分支删除，permit 路径仅保留标准 EIP-2612 `selfPermitIfNecessary` 一条线。
- `SelfPermit`：删除 `selfPermitAllowed` 与 `selfPermitAllowedIfNecessary` 两个函数，删除 `import '../interfaces/IERC20PermitAllowed.sol'`。
- `ISelfPermit`：同步删除两个 DAI/CHAI 风格函数声明。
- `ignition/modules/infrastructure.js`：不再部署 `GreatLottoEth(Test)`；`DaoBenefitPool` 构造收敛；`return` 中移除 `greatLottoEth`。
- `test/runTest/*.js`：删除 / 改写所有 ETH wrap/unwrap、`isEth = true`、DAI permit 用例；为旧 ETH / DAI 路径补"应不存在"或"应 revert `ErrorUnsupportedToken`"的负向用例；`selfPermitAllowed*` selector 调用应触发 fallback 失败的断言。

### 保留

- `SelfPermit.selfPermit` / `selfPermitIfNecessary`：USDC（标准 ERC20Permit）仍依赖该路径。USDT 主网无 permit，沿用 `approve` + `mint` 两步流程。
- `AccessControlPartnerContract` / `BeneficiaryBase` / `NoDelegateCall` / `DeadLine`：与币种轨道无关。

### 非目标

- 不引入新代币（USDT + USDC 之外）。
- 不做存储升级或代理合约迁移；按全新部署执行。
- 不修改 interface 前端仓库（前端下线由该仓库另起 change）。

## Impact

- **下游仓库**：`GreatLottoCore` / `ScratchCard` 必须在本 change 合并并发布到 pnpm workspace 之后才能跟进各自的 change（参见跨仓方案 §3）。
- **ABI**：`DaoCoin` / `DaoBenefitPool` / `IBenefitPoolBase` / `GreatLottoCoin`（permit 入口签名不变但行为改变） / `ISelfPermit`（少两个 selector）全部变更；下游仓库需重编译。
- **部署参数**：`infrastructure.js` 入参收敛；deployer 与 owner 无需变更。
- **合约大小**：`DaoBenefitPool` / `BenefitPoolBase` / `GreatLottoCoin`（无 DAI 分支）/ `SelfPermit`（无 allowed 函数）体积全部下降；不影响 EIP-170。
- **支持币种**：USDT + USDC；接受 DAI 的所有路径（`mint` / `withdraw` / `recover`）SHALL 因白名单不命中而 revert。
- **白皮书**：`WhitePaper_EN.md` / `WhitePaper_ZH.md` 中 DAI 表述需在 tasks 中刷新。
