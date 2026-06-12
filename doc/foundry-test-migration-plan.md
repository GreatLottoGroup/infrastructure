# Foundry 测试迁移方案（infrastructure 先行）

> 状态：**infrastructure 已落地完成（commit 2c2bc1a，2026-06-12）** · 适用仓：先 `infrastructure`，验证后复制到 `ScratchCard` / `GreatLottoCore`
>
> **完成情况**：`test/foundry/` 共 133 tests 全绿（9 单测 + 2 invariant）；生产合约行覆盖率多在 88%+（AccessControlPartnerContract/DeadLine/SelfPermit 100%，GreatLottoCoin 96.8%、SalesChannel 96.2%、EntropyConsumerBase 94%）。**GreatLottoCoin 用 6 位 ERC20Permit mock 全本地化、未用 fork**（原 fork 计划作罢，整套 ~1.4s 零外网依赖）。
>
> **最终清理（含实战修正，见文末「实战修正」）**：
> - `test/` 只剩 `test/foundry/`——`test/runTest`(8 mocha) + `test/utils` + `test/scripts`(运维脚本，部署已由 Ignition 承接) + `test/abi` + `.mocharc.json` **全部删除**。
> - `contracts/test/` 现**只剩 `GreatLottoCoinTest`**：它被 ScratchCard(`InfraImports.sol`) 与 GreatLottoCore(`GreatLottoCoinTest2.sol`) **跨仓 import**，是发布给下游的 Test 合约、必须留原路径。5 个纯 infra-test mock 已**迁入 `test/foundry/`**：mock 类（MockEntropyWithFee/FeeOnTransfer/SilentFail）入 `test/foundry/mocks/`、harness 类（MockEntropyConsumer/PrizePoolBaseHarness，具体化/暴露抽象基类）入 `test/foundry/harness/`——hardhat 自此不再编译它们（`hardhat compile` 66 files）。`PartnerTest` + `RejectingReceiver(Caller)` 死桩已删。
> - `hardhat.config`：去掉 mocha/coverage/standalone gas-reporter require；**`gasReporter` 保留键但 `enabled:false`**（toolbox 加载会写该键、缺键 TypeError；但 mocha 已删它出不了数，无意义故关）。`package.json`：`test`→`forge test`、`gas`→`forge test --gas-report`（Foundry 才是 gas 工具）、`coverage`→`forge coverage --ir-minimum`、`compile`→`hardhat compile`。
>
> **复制到下游时的环境注意**：本机到 github/paradigm/soliditylang 网络不稳——solc 从 Hardhat 缓存拷进 `~/.svm/`、forge-std 用 `git clone --depth 1`（见步骤 1）。GreatLottoCore 是 **viaIR 无 optimizer**，foundry.toml profile 不可照抄 infrastructure。

## Context（为什么做）

当前全工作区合约测试用 **Hardhat + Mocha/Chai + ethers**（JS），缺少 **fuzzing / invariant** 能力——而本工作区的核心风险恰恰在数值不变量：`PrizePoolBase` 的奖池清零与渠道/DAO 两段分润、`GreatLottoCoin` 多稳定币白名单收付、`EntropyConsumerBase` 的请求/回调/重试状态机。这些手写固定用例难以穷举调用序列。

目标：**测试全部迁到 Foundry**（`forge test`，Solidity 写测试，原生 fuzz/invariant + 更快），**Hardhat 只保留部署（Ignition）与 ABI 产出**。本次先在 `infrastructure` 落地，建立可复制的配置与模式范本，再推广到另两个合约仓。

## 既定决策（已与用户确认）

1. **旧 mocha 测试并行保留**：先让 Foundry 测试全绿且覆盖率不低于现状，确认对等后**在同一 change 内**删除 `test/runTest/*.js`。
2. **单一编译 profile，始终对齐生产**：viaIR=true、optimizer enabled runs=200、solc 0.8.24、EVM cancun（与 `hardhat.config.js` 完全一致）。
3. **fork 优先 `deal()` 充值，必要时才 fork**：能用 `deal()` 直接铸稳定币余额的就不 fork；仅 `GreatLottoCoin`（真实 USDT/USDC + EIP-2612 permit 行为）保留 Arbitrum 主网 fork。
4. **以合约为本、全新视角设计用例，不照搬 mocha**：测试设计**不以「翻译现有 mocha 用例」为目标**，而以**完整覆盖 `contracts/` 中除 `contracts/test/` 外所有生产合约的每个细节**为目标（每个 external/public 函数、每个 revert 分支与 custom error、每条事件、每个状态转移、边界与权限门）。现有 mocha 用例**仅作参照与查漏**（确保不遗漏已覆盖的场景），不作模板——可重新组织、补足 mocha 未覆盖的分支，并叠加 fuzz/invariant。

   **待全覆盖的生产合约清单**（`contracts/` 除 `test/`、`interfaces/` 外）：
   - 顶层：`GreatLottoCoin` / `DaoCoin` / `DaoBenefitPool` / `SalesChannel`
   - 基类（`base/`）：`PrizePoolBase` / `EntropyConsumerBase` / `AccessControlPartnerContract` / `BeneficiaryBase` / `BenefitPoolBase` / `DeadLine` / `NoDelegateCall` / `SelfPermit`
   - 抽象基类（PrizePoolBase / EntropyConsumerBase / BeneficiaryBase / BenefitPoolBase / NoDelegateCall / DeadLine / SelfPermit）经各自 harness/具体子类落地后测，覆盖率按 harness 间接计入基类。

## 调研结论（现状关键事实）

- `forge` **未安装**，需先 `foundryup`。
- solc 配置（`hardhat.config.js:20-30`）：`0.8.24` / `cancun` / `viaIR:true` / optimizer `runs:200`。
- 依赖经 **pnpm 软链**：`node_modules/@openzeppelin/contracts`、`node_modules/@pythnetwork/entropy-sdk-solidity`（remappings 指向 node_modules 即可，Foundry 能穿透软链）。
- **8 个生产合约 import `hardhat/console.sol`**（`GreatLottoCoin/DaoCoin/DaoBenefitPool/SalesChannel/base:BenefitPoolBase,SelfPermit,NoDelegateCall,AccessControlPartnerContract`）。`node_modules/hardhat/console.sol` 存在 → 用 remapping `hardhat/=node_modules/hardhat/` 即可让 Foundry 编译，不必改合约（清理 console 留待独立 follow-up）。
- Mock/Harness **已是 Solidity**（`contracts/test/`：`MockEntropyWithFee` `MockEntropyConsumer` `MockFeeOnTransferCoin` `MockSilentFailCoin` `GreatLottoCoinTest` `PartnerTest` `PrizePoolBaseHarness` `RejectingReceiver*`）→ Foundry 直接复用，无需重写。
- 8 个 mocha 测试（~1900 行）。需 fork：`GreatLottoCoin.js`、`PrizePoolBase.test.js`（真实 USDT/USDC + impersonation）。
- JS fixtures：`test/utils/deployTool.js`（`deploy()`/`initContract()`）、`deployPrizePoolBaseFixture.js`、`deployEntropyFixture.js`、`getCoin.js`、`permitUtils.js` → 在 Foundry 中改写为 `BaseTest` 抽象基类 + `setUp()`。

## 实施步骤

### 1. 安装 & 工程脚手架 ✅（已落地）
- 安装 Foundry：`curl -L https://foundry.paradigm.xyz | bash && foundryup`（或 `brew install foundry`）。本机已装 **forge 1.7.1**。
- **forge-std 不提交、每次重装**（已决策）：`lib/` 已加入 `.gitignore`（连同 `out`/`cache_forge`）。checkout / CI 后用以下任一命令重装：
  - 规范：`forge install foundry-rs/forge-std`（git submodule，默认方式）
  - 断网/submodule 报错时回退：`git clone --depth 1 https://github.com/foundry-rs/forge-std lib/forge-std`
- `.gitignore` 提交项：忽略 `out`、`cache_forge`（用 `cache_path` 避开与 hardhat `cache` 冲突）、`lib`。
- 新增并提交 `foundry.toml` + `remappings.txt`。
- **本机网络绕过（环境注意，非方案的一部分）**：到 github / paradigm / soliditylang 不稳，需要时——
  - solc 0.8.24：forge 默认从 `binaries.soliditylang.org` 下载会超时；从 Hardhat 缓存复制原生二进制即可：
    `cp ~/Library/Caches/hardhat-nodejs/compilers-v2/macosx-amd64/solc-macosx-amd64-v0.8.24+commit.e11b9ed9 ~/.svm/0.8.24/solc-0.8.24 && chmod +x ~/.svm/0.8.24/solc-0.8.24`
  - forge-std：`forge install` 的 submodule clone 易半途断网留空壳，改用上面的 `git clone --depth 1`。

### 2. `foundry.toml`（对齐生产，单 profile）
```toml
[profile.default]
src = "contracts"
test = "test/foundry"
out = "out"
cache_path = "cache_forge"          # 避开 hardhat 的 cache/
libs = ["lib", "node_modules"]
solc_version = "0.8.24"
evm_version = "cancun"
via_ir = true
optimizer = true
optimizer_runs = 200
fs_permissions = [{ access = "read", path = "./"}]

[profile.default.fuzz]
runs = 256

[profile.default.invariant]
runs = 256
depth = 50
fail_on_revert = false

[rpc_endpoints]
arbitrum = "${ARBITRUM_RPC_URL}"     # fork 用，复用 .env 的 ALCHEMY
```

### 3. `remappings.txt`
```
forge-std/=lib/forge-std/src/
@openzeppelin/contracts/=node_modules/@openzeppelin/contracts/
@pythnetwork/entropy-sdk-solidity/=node_modules/@pythnetwork/entropy-sdk-solidity/
hardhat/=node_modules/hardhat/
```
- 验证编译：`forge build`（必须先于写测试通过，确认 8 个 console.sol 合约 + Pyth + OZ 全部解析）。

### 4. 测试目录结构（`test/foundry/`）
```
test/foundry/
  base/BaseTest.sol            ← 抽象基类：部署 GLC/DaoCoin/DaoBenefitPool/SalesChannel/PartnerTest + 授 PARTNER_CONTRACT_ROLE（替代 deployTool.js）
  base/PermitHelper.sol        ← EIP-2612 签名（vm.sign）替代 permitUtils.js
  AccessControlPartnerContract.t.sol
  BeneficiaryBase.t.sol
  BenefitPoolBase.t.sol
  DaoCoin.t.sol
  SalesChannel.t.sol
  EntropyConsumerBase.t.sol    ← 复用 MockEntropyConsumer/MockEntropyWithFee；建模 request→callback→retry
  PrizePoolBase.t.sol          ← 复用 PrizePoolBaseHarness；分润/付奖/claimPayout 兜底
  GreatLottoCoin.t.sol         ← fork：vm.createSelectFork("arbitrum", BLOCK)，真实 USDT/USDC + permit
  invariant/                   ← 新增价值点（见步骤 6）
    PrizePoolInvariant.t.sol
    GreatLottoCoinInvariant.t.sol
```
- **每个 `.t.sol` 以「目标合约的细节全覆盖」为纲自上而下设计**（逐 external/public 函数 × 正常路径 + 每个 revert 分支 + 事件 + 状态转移 + 权限门 + 边界值），**不照搬 mocha**；写完后再拿对应 mocha 文件查漏，补回任何遗漏场景。常用映射：`expect().to.equal` → `assertEq`；`revertedWithCustomError` → `vm.expectRevert(Selector.selector)`；`loadFixture` → `setUp()`；`getImpersonatedSigner`→`vm.prank`；token 充值优先 `deal(token, to, amt)`，仅 GreatLottoCoin 保留 fork。
- 事件断言用 `vm.expectEmit`。

#### 测试桩处理清单（`contracts/test/` → `test/foundry/`）

原则：**Foundry 不消除「链上需要一个表现得像 X 的合约」这一需求**，但提供三个机制让桩缩小/消失——① 测试合约直接 `is XxxBase` 继承被测合约后**直调 internal**（无需 external wrapper）；② cheatcode（`vm.mockCall` / `vm.etch` / `deal`）；③ **测试合约本身就是合约**（可被授 PARTNER_CONTRACT_ROLE）。cheatcode 替代不了「跨调用维持 EVM 状态」的桩（有状态生命周期、与 balanceOf 耦合的记账）——这些保留为真实 mock。

**净目标（已据实落地）：`contracts/test/` 只保留被下游跨仓 import 的 Test 合约（本仓即 `GreatLottoCoinTest`）；纯 infra-test 的 mock/harness 全部迁入 `test/foundry/{mocks,harness}/`（hardhat 不再编译，生产树更干净）；死桩删除。⚠️ 删/迁任何 `contracts/test/*.sol` 前，必须 grep 下游仓 `@greatlotto/infrastructure/contracts/test/` 的 import——被 import 的不能动路径。**

| 现有桩 | 存在原因 | Foundry 处置 |
|--------|---------|------------|
| `PrizePoolBaseHarness.sol` | 具体化抽象 `PrizePoolBase` + 暴露 ~12 个 internal | **大幅瘦身**：测试合约直接 `is PrizePoolBase` 调 `_distributeChannelAndDaoBenefits()` 等 internal；删掉全部 external wrapper，只留必要抽象方法实现，内联进 `test/foundry/`（或 `base/BaseTest.sol`） |
| `MockEntropyConsumer.sol` | 具体化抽象 `EntropyConsumerBase` + 记录回调状态 | **内核保留**（钩子 `_onRequestFulfilled`/`_postRequest`/`_beforeRetry` 实现必需），public wrapper 由继承直调取代；迁入 `test/foundry/` |
| `MockEntropyWithFee.sol` | 有状态 IEntropyV2（序列号+请求存储+reveal/CALLBACK_FAILED 生命周期） | ✅ **保留为真实 mock**（cheatcode 最难替代的跨调用状态机），迁入 `test/foundry/`。核心资产 |
| `MockFeeOnTransferCoin.sol` | fee-on-transfer，balanceOf 须真实反映扣费（被 `_transferTo` 严格等式后置检查读取） | ✅ **保留为真实 mock**，迁入 `test/foundry/` |
| `MockSilentFailCoin.sol` | transfer 返 true 但不动余额 | ❌ **可删**：`vm.mockCall(token, transfer.selector, abi.encode(true))` 一行替代 |
| `RejectingReceiver.sol` / `RejectingReceiverCaller.sol` | 拒收 ETH，测 `_refundFee` / `ErrorRefundFailed` 分支 | ⚠️ **简化/保留**：可用 `vm.etch` 塞 revert 字节码；但极小且语义清晰，内联进 `test/foundry/` 亦可 |
| `GreatLottoCoinTest.sol` | 免费 `mintFor`/`burnFrom` | ⚠️ **免费铸币部分可删**（`deal(glc, user, amt)` 替代）；测真实 `mint()`（白名单+decimals+permit）路径时仍部署真实 `GreatLottoCoin` |
| `PartnerTest.sol` | 假 PARTNER 合约调 `mint`/`mintToUser`（角色限 `_isContract`） | ✅ **可折叠进测试合约**：测试合约本身是合约，给 `address(this)` 授 PARTNER_CONTRACT_ROLE 后直调，删除独立桩 |

> 同理适用于 ScratchCard 仓 `contracts/test/`（如 `PrizePoolPartnerMock.sol`）与 GreatLottoCore 仓 `contracts/test/`（迁该仓时按本清单同款判定，注意 GreatLottoCore 是 viaIR 无 optimizer，`MockEntropyTest` 注释已记录）。

### 5. fork 处理
- 仅 `GreatLottoCoin.t.sol` fork Arbitrum（真实 USDC 支持 permit，USDT 不支持 → 正是要测的白名单/permit 分支）。`BLOCK` 复用现有 `472312054`，RPC 走 `vm.envString` + `[rpc_endpoints]`。
- 其余 fixtures 部署 `GreatLottoCoinTest`/`PartnerTest`，余额用 `deal()` → 本地无 RPC 跑。

### 6. 新增 invariant/fuzz（迁移的核心增益）
- `PrizePoolInvariant`：随机序列 `collectForBuy/payBonus/payBonusStrict/claimPayout` 后，断言 **奖池账本 == 实际 GLC 余额减去已分润**、分润率边界、无负值。
- `GreatLottoCoinInvariant`：多币种 mint/burn 后**白名单内代币总账守恒**。
- 关键入口加 fuzz：分润率 setter 边界、`bound()` 约束金额。

### 7. 覆盖校验 → 删除 mocha
- `forge test -vvv` 全绿。
- **以全覆盖为验收口径**（非「mocha 用例对等」）：`forge coverage --report summary` 对每个生产合约（步骤「既定决策 4」清单）行/分支覆盖率应达高位（目标 ≥ 现状 `coverage.json`，且不低于此前 mocha 覆盖的分支）。逐合约核对每个 revert/custom error 分支均有命中。
- 拿 mocha 文件最后查一遍漏（仅查漏，不作对等基准）。确认无遗漏后，**删除 `test/runTest/*.js` + `test/utils/*.js` + `test/abi/*` 中仅测试用部分 + `.mocharc.json`**；`hardhat.config.js` 移除 `gasReporter`/`solidity-coverage`/mocha 相关、保留编译+网络+ignition+etherscan。
- `package.json`：移除 mocha/coverage devDeps，加 `"test": "forge test"`、`"coverage": "forge coverage"`。

### 8. 文档 & 复制范本
- 更新 `infrastructure/CLAUDE.md` 与 `README.md`：测试命令改为 `forge test`，说明「Hardhat 仅部署+ABI」。
- 记录 remappings/foundry.toml 范本，供 ScratchCard / GreatLottoCore 后续复制（注意 ScratchCard 的 fork 是开奖 mock 而非真实币，GreatLottoCore 有 ERC4626 金库需额外 invariant）。

## 验证方式
```bash
cd infrastructure
forge build                                   # 编译对齐生产（viaIR+optimizer）
forge test -vvv                               # 单测+fuzz 全绿
forge test --match-contract Invariant -vvv    # 不变量
ARBITRUM_RPC_URL=<rpc> forge test --match-contract GreatLottoCoin   # fork 用例
forge coverage --report summary               # 覆盖率 ≥ 现状
# 部署链路不受影响（回归）：
npx hardhat compile && npx hardhat ignition ... # 仍走 Hardhat
```

## 风险 / 注意
- **viaIR + forge coverage 可能 stack-too-deep**：必要时 coverage 加 `--ir-minimum`（仅覆盖率，不影响 test/build 的生产对齐）。
- `out/` 与 hardhat `artifacts/` 并存：已用 `cache_path`/`out` 隔离，互不污染；interface 仍从 hardhat artifacts 取 ABI，不受影响。
- 生产合约残留 `hardhat/console.sol` 仅靠 remapping 兜住；建议另开 follow-up change 清理 console 调用（部署字节码体积/规范性）。
- **forge-std 不入库（`lib/` 已 gitignore），CI / checkout 后须先重装**（`forge install foundry-rs/forge-std`，断网回退 `git clone --depth 1 ... lib/forge-std`）；忘装则 `forge test` 编译 `.t.sol` 时报 forge-std 找不到。注意 `forge build` 仅编译 `contracts/`、不依赖 forge-std，故缺 forge-std 时 build 仍过、test 才挂——别被 build 通过误导。

## 实战修正（infrastructure 落地后回填，下游照用）

1. **`vm.expectRevert` 与带参 custom error**：`vm.expectRevert(Error.selector)`（4 字节）**只匹配无参数** revert；带参 error（如 `AccessControlUnauthorizedAccount(account, role)`、`ErrorInsufficientBalance(...)`、`ERC2612InvalidSigner(signer, owner)`）必须给完整 `abi.encodeWithSelector(Error.selector, args...)` 或 `abi.encodeWithSignature("Name(types)", args...)`，否则报「Error != expected error」。无参 error（`ErrorZeroAddress` 等）才能只给 selector。
2. **`makeAddr` 不能在 `view` 测试里调**：它含 `vm.label`（改状态），`view` 函数内调用编译报错——去掉该测试的 `view`。
3. **接口限定事件**：`emit IXxx.Event(...)`（0.8.22+ 支持）替代本地重声明，0.8.24 实测可用。
4. **抽象基类**：测试合约直接 `is XxxBase` 或内联 `XxxHarness is XxxBase` 具体化；`PrizePoolBaseHarness` 已暴露全部 internal，本仓直接复用未再瘦身（够用即可，不必为「删 wrapper」改 contracts/test）。
5. **PARTNER_CONTRACT_ROLE 授给测试合约自身**：测试合约即合约且字节码 > 1000（`_isContract` 阈值），`grantRole(PARTNER_ROLE, address(this))` 后直调 mint/mintToUser，免 `PartnerTest`。
6. **GLC 余额用 `deal(address(glc), who, amt)`** 直接铸，免跑底层 mint 全流程；fee-on-transfer / silent-fail 异常代币复用 `contracts/test/` 现成 mock 并 `ICoinBase(address(mock))` 强转传入。
7. **gasReporter 必须保留键、但置 false**：`@nomicfoundation/hardhat-toolbox` 加载时写 `config.gasReporter.enabled`，删掉整个 `gasReporter` 块会 `TypeError: Cannot set properties of undefined`——保留 `gasReporter: { enabled: false }`。它仅 hardhat test 出数、mocha 删后无意义，故 enabled:false；gas 实际看 `forge test --gas-report`（`npm run gas`）。
8. **删 `contracts/test/*.sol` 前必查跨仓**：infrastructure 是被 ScratchCard/Core 经 npm 包消费的上游，`grep -rn "@greatlotto/infrastructure/contracts/test/" <下游仓>/contracts`；`GreatLottoCoinTest` 即被双下游 import，删不得。
9. **`test/scripts` 运维脚本可随 mocha 一起删**：部署由 `ignition/modules/` 承接，手写 deploy/approve/init 脚本及其 `test/utils`、`test/abi` 依赖整体废弃。
