## Why

区块浏览器（Etherscan/Blockscout）在验证以 solc 0.8.26 编译的合约后，会按版本号机械列出该版本的两个已知编译器 bug 告警：

| Bug | 严重度 | 引入 | 修复版本 | 触发条件 | 本仓实际暴露 |
|---|---|---|---|---|---|
| `UnsoundSpillInMutualRecursion` | medium | 0.7.2 | **0.8.36** | `viaIR: true`（本仓命中） | 无（合约无互递归调用环） |
| `LostStorageArrayWriteOnSlotOverflow` | low | 0.1.0 | 0.8.32 | 无 | 无（需 storage 数组跨 2^256 槽边界） |

告警与合约是否真触发无关，两者对本仓均不可实际触发。但主网上线前审计要求「无已知编译器 bug 告警」，需升级到同时修复两者的 **0.8.36**（当前最新 release）。

## What Changes

- `hardhat.config.js`：`solidity.version` `"0.8.26"` → `"0.8.36"`
- `foundry.toml`：`solc_version` `"0.8.26"` → `"0.8.36"`
- 全部 `.sol` 源与测试的 `pragma solidity ^0.8.26;` → `^0.8.36;`（contracts 17 + test/foundry 19 = 36 处）
- 文档现状表述：`README.md`、`CLAUDE.md`、`doc/three-repo-deploy-gas-estimate.md` 中的「Solidity 0.8.26」→「0.8.36」

非目标 / 明确排除：
- **不**改 `evm_version = cancun` / `via_ir = true` / `optimizer runs=200`
- **不**改任何 Solidity 接口签名、事件、存储布局或合约行为（纯工具链/构建变更）
- **不**触碰历史/规划文档中的 `0.8.24`/`0.8.26`（属历史记录）
- **无 ABI/接口涟漪** → interface 仓无需对应 change

## Capabilities

### New Capabilities
- `build-toolchain`: 新增「Solidity 编译器无已知 bug 版本」需求——合约 MUST 以 solc 0.8.36+（viaIR+optimizer200+cancun）编译，Hardhat/Foundry 两套 pin 与全部 pragma 一致，编译产物不再触发 UnsoundSpillInMutualRecursion / LostStorageArrayWriteOnSlotOverflow 浏览器告警。

### Modified Capabilities
<!-- 无 -->

## Impact

- **构建**：全仓改用 solc 0.8.36 编译；字节码 metadata 记录 0.8.36，浏览器告警消除。
- **跨仓**：本仓经 symlink 被 ScratchCard / GreatLottoCore 消费；见 `.claude-workspace/coordination/2026Q3-solc-0836-bump.md`。下游用 0.8.36 编译本仓 `^0.8.36` 源无冲突。
- **验证**：`forge test`（148 tests）全绿；`npx hardhat compile` 通过；artifacts 确认 solcVersion=0.8.36。
- **流程**：合约仓编译器变更 → 走三道 review 门（`/flow-review-spec` → `requesting-code-review` → `/security-review`）。
