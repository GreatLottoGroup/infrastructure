# build-toolchain Specification

## Purpose
TBD - created by archiving change 2026Q3-solc-0836-bump-workspace. Update Purpose after archive.
## Requirements
### Requirement: Solidity 编译器无已知 bug 版本

本仓所有合约 SHALL 使用**不含已知编译器 bug 告警**的 Solidity 版本编译。编译器版本 MUST 为 **0.8.36 或更高**（同时修复 `UnsoundSpillInMutualRecursion` 与 `LostStorageArrayWriteOnSlotOverflow`），并保持 `viaIR` 开启、`optimizer runs=200`、`evm_version=cancun`。Hardhat（`hardhat.config.js`）与 Foundry（`foundry.toml`）两套构建配置的版本 pin MUST 一致，且全部 `.sol` 的 `pragma` 版本约束 MUST 允许该版本。

#### Scenario: 构建配置 pin 到无 bug 版本

- **WHEN** 读取 `hardhat.config.js` 的 `solidity.version` 与 `foundry.toml` 的 `solc_version`
- **THEN** 两者 MUST 均为 `0.8.36`（或更高）
- **AND** `viaIR`/`via_ir` MUST 为 true、optimizer runs MUST 为 200、evm_version MUST 为 cancun

#### Scenario: 源码 pragma 允许无 bug 版本

- **WHEN** 扫描 `contracts/**/*.sol` 与 `test/**/*.sol` 的 `pragma solidity`
- **THEN** 每条 pragma MUST 允许 0.8.36（本仓统一为 `^0.8.36`），无残留 `^0.8.26`

#### Scenario: 编译产物记录无 bug 版本

- **WHEN** 执行 `forge build` / `npx hardhat compile` 后检视 artifacts / build-info
- **THEN** 记录的 `solcVersion` MUST 为 0.8.36
- **AND** 区块浏览器验证该字节码时 MUST NOT 列出 `UnsoundSpillInMutualRecursion` / `LostStorageArrayWriteOnSlotOverflow` 告警

