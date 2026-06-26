# deploy-local-and-sync Skill 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `infrastructure/scripts/` 的本地部署 + 地址/ABI 同步工作流物理迁移并封装为自包含 skill `infrastructure/skills/deploy-local-and-sync/`，原 `scripts/` 删除，skill 成唯一事实源。

**Architecture:** 纯机械迁移 + 路径重算。8 个脚本/配置文件 + `test/` 用 `git mv` 搬进 skill 目录（深一级），把两个 CLI + 一个 shell 脚本里的 `ROOT = ../..` 改为 `../../..`，更新 `package.json` 测试 glob，写 `SKILL.md`（吸收原 README），删空目录。现有单测套件做回归门。

**Tech Stack:** Node.js ESM 脚本、Bash、Hardhat Ignition、`node --test`。

> **提交策略**：按用户偏好（no-commit-each-step），全部改动在 Task 6 收尾一次性 commit，不逐步提交。

---

### Task 1: 物理迁移脚本 + 配置 + 测试到 skill 目录

**Files:**
- 移动源：`infrastructure/scripts/{deploy-local.sh,sync-addresses.mjs,sync-abi.mjs,sync-core.mjs,abi-core.mjs,deploy.config.json,abi.config.json}`
- 移动源：`infrastructure/scripts/test/{sync-core.test.mjs,abi-core.test.mjs}`
- 目标：`infrastructure/skills/deploy-local-and-sync/`

- [ ] **Step 1: 建 skill 目录并 git mv 8 个文件**

以 `infrastructure/` 为 cwd 执行：

```bash
cd /Users/tongren/Documents/github/GreatLottoGroup/infrastructure
mkdir -p skills/deploy-local-and-sync
git mv scripts/deploy-local.sh        skills/deploy-local-and-sync/deploy-local.sh
git mv scripts/sync-addresses.mjs     skills/deploy-local-and-sync/sync-addresses.mjs
git mv scripts/sync-abi.mjs           skills/deploy-local-and-sync/sync-abi.mjs
git mv scripts/sync-core.mjs          skills/deploy-local-and-sync/sync-core.mjs
git mv scripts/abi-core.mjs           skills/deploy-local-and-sync/abi-core.mjs
git mv scripts/deploy.config.json     skills/deploy-local-and-sync/deploy.config.json
git mv scripts/abi.config.json        skills/deploy-local-and-sync/abi.config.json
```

- [ ] **Step 2: git mv test 目录（保持 test/ 是核心文件兄弟目录）**

```bash
git mv scripts/test skills/deploy-local-and-sync/test
```

- [ ] **Step 3: 确认 scripts 目录只剩非迁移产物**

```bash
ls -A skills/deploy-local-and-sync && echo "---scripts 剩余---" && ls -A scripts
```

Expected: skill 目录列出 7 个文件 + `test/`；`scripts/` 只剩 `README.md` 和运行期产物 `.hardhat-node.log`（两者将在后续任务处理）。

---

### Task 2: rebase `sync-addresses.mjs` 的 ROOT 路径

**Files:**
- Modify: `infrastructure/skills/deploy-local-and-sync/sync-addresses.mjs:13`

- [ ] **Step 1: 把 ROOT 从 ../.. 改为 ../../..**

原行（含注释）：

```js
const ROOT = join(SCRIPT_DIR, "..", "..");          // infrastructure/scripts → 工作区根
```

改为：

```js
const ROOT = join(SCRIPT_DIR, "..", "..", "..");    // infrastructure/skills/deploy-local-and-sync → 工作区根
```

`SCRIPT_DIR` / `CONFIG`（同目录读 `deploy.config.json`）等其余逻辑不变。

---

### Task 3: rebase `sync-abi.mjs` 的 ROOT 路径

**Files:**
- Modify: `infrastructure/skills/deploy-local-and-sync/sync-abi.mjs:11`

- [ ] **Step 1: 把 ROOT 从 ../.. 改为 ../../..**

原行（含注释）：

```js
const ROOT = join(SCRIPT_DIR, "..", "..");          // infrastructure/scripts → 工作区根
```

改为：

```js
const ROOT = join(SCRIPT_DIR, "..", "..", "..");    // infrastructure/skills/deploy-local-and-sync → 工作区根
```

`DEPLOY_CFG` / `ABI_CFG`（同目录读两个 config）等其余逻辑不变。

---

### Task 4: rebase `deploy-local.sh` 的 ROOT 路径

**Files:**
- Modify: `infrastructure/skills/deploy-local-and-sync/deploy-local.sh:5`

- [ ] **Step 1: 把 ROOT 从 ../.. 改为 ../../..**

原行（含注释）：

```bash
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"          # 工作区根(4 仓父目录)
```

改为：

```bash
ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"       # 工作区根(4 仓父目录)
```

`SCRIPT_DIR`（`dirname BASH_SOURCE`，自适应）、`SYNC="$SCRIPT_DIR/sync-addresses.mjs"`、第 70 行 `node "$SCRIPT_DIR/sync-abi.mjs"`、`.hardhat-node.log` 写到 `$SCRIPT_DIR/` —— 这些都基于 `SCRIPT_DIR`，自动跟随新位置，无需改。

---

### Task 5: 更新 package.json 的 test:scripts glob

**Files:**
- Modify: `infrastructure/package.json`

- [ ] **Step 1: 改测试 glob 指向新目录**

原行：

```json
    "test:scripts": "node --test \"scripts/test/**/*.test.mjs\"",
```

改为：

```json
    "test:scripts": "node --test \"skills/deploy-local-and-sync/test/**/*.test.mjs\"",
```

- [ ] **Step 2: 跑迁移后的单测做回归门**

```bash
cd /Users/tongren/Documents/github/GreatLottoGroup/infrastructure && npm run test:scripts
```

Expected: 两个测试文件全部用例 PASS（`parseArgs` / `resolveArtifactRel` / `classifyDir` / `abiText` / `statusOf` 等），无 `Cannot find module` 报错 —— 证明相对 import 在新位置完好。

- [ ] **Step 3: dry-run 验证 ROOT 路径推算正确**

```bash
cd /Users/tongren/Documents/github/GreatLottoGroup/infrastructure
node skills/deploy-local-and-sync/sync-abi.mjs
node skills/deploy-local-and-sync/sync-addresses.mjs --network localhost
```

Expected: 两条命令都打印同步状态/diff 表并以 `(dry-run,未写...)` 结尾；**不**出现「找不到 artifact 因为根算错到了 `infrastructure/` 上一级的上一级」之类的全量 missing。若所有条目都 `missing`，说明 ROOT 多下沉了一级，回查 Task 2/3。（注：localhost 未部署时部分 `未解析到` 告警属正常。）

---

### Task 6: 写 SKILL.md，清理空 scripts 目录，补设计文档备注，收尾提交

**Files:**
- Create: `infrastructure/skills/deploy-local-and-sync/SKILL.md`
- Delete: `infrastructure/scripts/README.md`、`infrastructure/scripts/`（含运行期 `.hardhat-node.log`）
- Modify: `infrastructure/doc/local-deploy-and-address-sync-design.md`（加迁移备注）

- [ ] **Step 1: 写 SKILL.md**

内容吸收原 `scripts/README.md` 的三场景用法 + 加链/加合约/加 ABI 指引 + 常见错误表，frontmatter 加 name/description。所有命令路径改为 `skills/deploy-local-and-sync/<file>`，cwd 标注为 `infrastructure/`。frontmatter：

```markdown
---
name: deploy-local-and-sync
description: 在 GreatLottoGroup 4 仓工作区做本地一键部署(起 hardhat 链 + 部署 infrastructure/ScratchCard/Core + 回填地址 + 同步 ABI),或单独跑跨仓地址同步 / ABI 同步到 interface。当需要起本地链联调、把新部署的合约地址回填到下游参数与 address.json、或把合约 ABI 同步到前端时使用。
---
```

正文结构（场景 1/2/3 + 配置指引 + 错误表），命令形如：
- 一键本地部署：`bash skills/deploy-local-and-sync/deploy-local.sh`
- 地址同步：`node skills/deploy-local-and-sync/sync-addresses.mjs --network <net> [--write] [--yes] [--only sc,core,interface]`
- ABI 同步：`node skills/deploy-local-and-sync/sync-abi.mjs [--network <net>] [--write]`

并保留原 README 的护栏要点（dry-run 默认 / 非本地 `--write` 交互确认 / 软链接前置 / 对应仓先 compile）和常见错误对照表。

- [ ] **Step 2: 删除原 scripts 残留**

```bash
cd /Users/tongren/Documents/github/GreatLottoGroup/infrastructure
git rm scripts/README.md
rm -f scripts/.hardhat-node.log
rmdir scripts 2>/dev/null || ls -A scripts
```

Expected: `scripts/` 被删除（`rmdir` 成功）。若 `rmdir` 失败会列出残留物 —— 逐一确认是否运行期产物后清理。

- [ ] **Step 3: 设计文档加迁移备注**

在 `doc/local-deploy-and-address-sync-design.md` 顶部（标题下方）插入一行：

```markdown
> **迁移备注（2026-06-26）**：脚本已从 `infrastructure/scripts/` 迁移并封装为自包含 skill `infrastructure/skills/deploy-local-and-sync/`，原 `scripts/` 目录已删除。用法见该 skill 的 `SKILL.md`；本文档讲设计动机，路径引用以 skill 目录为准。
```

- [ ] **Step 4: 最终回归 + 一次性提交**

```bash
cd /Users/tongren/Documents/github/GreatLottoGroup/infrastructure
npm run test:scripts
git add -A
git status
git commit -m "chore(skills): wrap local-deploy + abi/address sync into self-contained deploy-local-and-sync skill"
```

Expected: 测试全绿；`git status` 显示 skill 目录新增（含 git mv 重命名）、`scripts/` 删除、`package.json` 与设计文档修改；提交成功。

---

## Self-Review

- **Spec coverage**：迁移 8 文件+test(Task1) / 三处 ROOT rebase(Task2-4) / package.json glob(Task5) / SKILL.md + 删 scripts + 文档备注(Task6) / 验证(Task5 Step2-3, Task6 Step4) —— 覆盖设计「改动清单」5 项 + 「验证」3 条。
- **Placeholder scan**：无 TBD/TODO；每个改动给出原行与目标行原文。
- **Type/path consistency**：三处 ROOT 统一改为 `../../..`；测试 glob 与 Task1 落地路径 `skills/deploy-local-and-sync/test/` 一致；所有命令路径前缀统一 `skills/deploy-local-and-sync/`。
