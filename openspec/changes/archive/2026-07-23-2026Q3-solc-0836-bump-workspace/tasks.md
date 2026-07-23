# Tasks — infrastructure solc 0.8.36 bump

## 1. 编译器 pin
- [x] `hardhat.config.js` `version: "0.8.26"` → `"0.8.36"`
- [x] `foundry.toml` `solc_version = "0.8.26"` → `"0.8.36"`

## 2. 源码 pragma
- [x] 全部 `contracts/**/*.sol` + `test/**/*.sol` 的 `^0.8.26` → `^0.8.36`（36 处）
- [x] 确认无残留 `^0.8.26`

## 3. 文档
- [x] `README.md` / `CLAUDE.md` / `doc/three-repo-deploy-gas-estimate.md` 现状版本号 → 0.8.36

## 4. 验证
- [x] `forge test` 全绿（148 tests）
- [x] `npx hardhat compile` 通过、无体积超限
- [x] artifacts 确认 solcVersion = 0.8.36
- [x] 下游 ScratchCard / Core `forge test` 经 symlink 编译本仓源无冲突（原地分支，非 worktree）

## 5. Review 门
- [x] `/security-review`（跨仓一并，ZERO findings — 见 `security-review.md`）
- [~] `/flow-review-spec` / `requesting-code-review`：纯工具链 pin/pragma/文档 bump、零行为面变更，方案+代码审查并入 security-review 的 diff 比对
