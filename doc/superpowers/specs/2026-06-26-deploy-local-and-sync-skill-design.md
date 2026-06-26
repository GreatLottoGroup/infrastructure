# 把本地部署 + ABI/地址同步封装为自包含 Skill —— 设计

## 目标

把现有 `infrastructure/scripts/` 下成熟的「一键本地部署 + 跨仓地址同步 + ABI 同步」工作流，物理迁移并封装为一个**自包含 (self-contained) skill** `deploy-local-and-sync`，放在 `infrastructure/skills/` 下。脚本本体随 skill 走，原 `scripts/` 目录删除 —— skill 目录成为这套工具的**唯一事实源**。

## 背景与约束

- 现有脚本（`deploy-local.sh` / `sync-addresses.mjs` / `sync-abi.mjs` / `sync-core.mjs` / `abi-core.mjs` + `deploy.config.json` / `abi.config.json` + `test/`）功能完整、有单测覆盖、有详尽 `README.md`。本任务**不改逻辑、不加功能**，只搬位置 + 重算路径 + 写 skill 文档。
- 关键路径耦合：两个 CLI（`sync-addresses.mjs`、`sync-abi.mjs`）与 `deploy-local.sh` 都以「脚本位于 `infrastructure/scripts/`」为前提，用 `ROOT = SCRIPT_DIR/../..` 推算 4 仓工作区根。迁到 `infrastructure/skills/deploy-local-and-sync/` 后目录深一级，`../..` 必须改为 `../../..`。
- 纯函数核心（`sync-core.mjs` / `abi-core.mjs`）无路径假设，原样搬。
- 测试文件用 `../<core>.mjs` 相对自身 import，只要 `test/` 仍是核心文件的兄弟目录即不受影响。
- config json 内的仓路径是**根相对**（`"ScratchCard"` 等），只要 ROOT 仍解析到工作区根，内容不用动。
- 用户偏好：不要每一步都 commit（见工作区记忆 no-commit-each-step）—— 全部改动收尾一次 commit。

## 目标结构

```
infrastructure/skills/deploy-local-and-sync/
├── SKILL.md                  # frontmatter + 三场景用法 + 护栏 + 排错(吸收原 scripts/README.md)
├── deploy-local.sh           # ROOT 推算下沉一级
├── sync-addresses.mjs        # ROOT = SCRIPT_DIR/../../..
├── sync-abi.mjs              # 同上
├── sync-core.mjs             # 纯函数,原样搬
├── abi-core.mjs              # 纯函数,原样搬
├── deploy.config.json        # 内容不变
├── abi.config.json           # 内容不变
└── test/
    ├── sync-core.test.mjs    # import ../sync-core.mjs 不变
    └── abi-core.test.mjs     # import ../abi-core.mjs 不变
```

## SKILL.md 内容（唯一事实源，吸收原 README）

frontmatter：
- `name: deploy-local-and-sync`
- `description`：触发词覆盖「本地一键部署 / 起本地 hardhat 链 / 同步合约地址到下游参数与 interface / 同步 ABI 到 interface / 回填 address.json」。

正文三场景（按用户意图分流到脚本 + 参数），均以 `infrastructure/` 为 cwd：
1. **一键本地部署** → `bash skills/deploy-local-and-sync/deploy-local.sh`（前置：ScratchCard/Core 的 `@greatlotto/infrastructure` 软链接在位；跑完本地链保留运行，停止用结尾打印的 `kill <pid>`）。
2. **单独同步地址（任意网络）** → `node skills/deploy-local-and-sync/sync-addresses.mjs --network <net> [--write] [--yes] [--only sc,core,interface]`。护栏：默认 dry-run；`localhost --write` 直落；非本地 `--write` 交互确认，`--yes` 跳过。
3. **单独同步 ABI** → `node skills/deploy-local-and-sync/sync-abi.mjs [--network <net>] [--write]`。前置：对应仓已 `npx hardhat compile`。

附：加链 / 加合约 / 加 ABI 改哪个 config（吸收原 README）；常见错误对照表（吸收原 README）。

## 改动清单

1. `git mv` 8 个文件 + `test/` 目录到 skill 目录（保 git 历史）。
2. rebase 路径：`sync-addresses.mjs`、`sync-abi.mjs`、`deploy-local.sh` 三处 `../..` → `../../..`（并更新注释）。
3. `package.json` 的 `test:scripts` glob：`scripts/test/**` → `skills/deploy-local-and-sync/test/**`。
4. 删空后的 `infrastructure/scripts/`（原 `scripts/README.md` 内容已吸收进 SKILL.md）。
5. 写 `SKILL.md`。
6. 设计文档 `doc/local-deploy-and-address-sync-design.md` 加一行迁移备注（不重写整篇）。

## 验证

- `npm run test:scripts` 全绿（验证 import 没断、core 函数无回归）。
- `node skills/deploy-local-and-sync/sync-addresses.mjs --network localhost`（dry-run）能正确解析路径、打印 diff 不报 ROOT 错误。
- `node skills/deploy-local-and-sync/sync-abi.mjs`（dry-run）同上。

## 不做（YAGNI）

- 不改任何脚本逻辑、不加新 CLI flag、不加新合约/链。
- 不重写设计文档全文。
- 不保留 `scripts/` 的 README 指针（唯一事实源即 SKILL.md）。
