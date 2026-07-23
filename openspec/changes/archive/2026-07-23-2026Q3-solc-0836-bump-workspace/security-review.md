# Security Review — 2026Q3-solc-0836-bump-workspace (infrastructure)

**Date**: 2026-07-23
**Scope**: `git diff main` 的真实 delta（纯 solc 0.8.26 → 0.8.36 pin + pragma + 文档），排除 main 上已有的无关提交。
**Verdict**: ✅ **ZERO findings** — clean toolchain bump。

## 核查项与结论

1. **非 pragma/非文档代码改动**：无。41 files，每个 +1/-1；新增行全部为 `pragma solidity ^0.8.36;`（18 处 .sol）、`solc_version = "0.8.36"`、`version: "0.8.36"`，或文档版本串。无任何函数体 / 存储布局 / 可见性 / 访问控制变更。
2. **optimizer / evm 设置未变**：`foundry.toml` 与 `hardhat.config.js` 的 `evm_version=cancun`、`via_ir=true`、`optimizer runs=200` 均未出现在 diff 中（保持不变）。
3. **无 pragma 放宽 / 降级**：全部改为 `^0.8.36`，无 `>=0.8.0` 放宽、无低于 0.8.36 的下钉。
4. **编译器回归评估**：0.8.26 → 0.8.36 为严格改进——修复 `UnsoundSpillInMutualRecursion`(medium, viaIR) 与 `LostStorageArrayWriteOnSlotOverflow`(low)，两者均 viaIR 路径 bug、本仓命中 viaIR，故修复直接相关；未知 0.8.27–0.8.36 有影响本仓构造的安全性回归。字节码/codegen 变化属编译器 bump 预期，但配置恒定故不引入语义变更。
5. **untracked 文件**：仅 `openspec/changes/2026Q3-solc-0836-bump-workspace/`（proposal/tasks/spec 全 md）。

## 验证支撑
- `forge test` 148 tests 全绿；`npx hardhat compile` 通过；artifacts `solcVersion=0.8.36`。
