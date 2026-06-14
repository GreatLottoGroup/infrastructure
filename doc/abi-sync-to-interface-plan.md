# ABI 同步到 interface 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **提交策略(用户偏好)**:**不要每一步都 commit**。各 Task 内不含提交步骤;全部完成且验证通过后,在 Task 6 一次性提交(或等用户明确要求再提交)。

**Goal:** 在 `infrastructure/scripts/` 交付 `sync-abi.mjs`,把三仓 hardhat 编译产物的合约 ABI 抽取并写到 interface,可独立调用,也并入 `deploy-local.sh`。

**Architecture:** 纯函数核心(`abi-core.mjs`,无 IO,可单测)+ CLI 外壳(`sync-abi.mjs`,读 artifact / 写 interface / dry-run 闸门)+ 声明式配置(`abi.config.json`)+ 集成进既有 `deploy-local.sh`。网络注册表复用 `deploy.config.json`(单一事实源),仅用于 GLC 变体选择。

**Tech Stack:** Node ESM(`.mjs`)、Node 内置测试器(`node --test`)、bash、Hardhat artifacts。

**设计依据:** [abi-sync-to-interface-design.md](./abi-sync-to-interface-design.md)。

---

## 文件结构

| 文件 | 职责 |
|------|------|
| `infrastructure/scripts/abi.config.json` | 声明式配置:abi 映射清单(file ← source 仓 + artifact 路径,GLC 带 variants)+ external 白名单 |
| `infrastructure/scripts/abi-core.mjs` | 纯函数:参数解析 / 变体解析 / 孤儿分类 / ABI 格式化 / diff 判定。无文件 IO |
| `infrastructure/scripts/sync-abi.mjs` | CLI:定位工作区根、读 artifact 的 `.abi`、比对 interface 现有文件、打印状态、`--write` 落盘 |
| `infrastructure/scripts/test/abi-core.test.mjs` | `node --test` 单测,覆盖 `abi-core.mjs` 全部纯函数 |
| `infrastructure/scripts/deploy-local.sh` | 修改:步骤 7 后新增 ABI 同步步骤 |
| `infrastructure/scripts/README.md` | 修改:补 sync-abi 用法段落 |

工作区根 = `infrastructure/` 的上级目录;脚本经 `<scriptDir>/../..` 解析。artifact 绝对路径 = `<root>/<repos[source]>/artifacts/<artifact>.json`,`repos` 复用 `deploy.config.json`。

---

## Task 1: abi.config.json(配置文件)

**Files:**
- Create: `infrastructure/scripts/abi.config.json`

- [ ] **Step 1: 建配置文件**

Create `infrastructure/scripts/abi.config.json`:

```json
{
  "interfaceAbiDir": "interface/src/app/abi",
  "mappings": [
    { "file": "ScratchCard.json",         "source": "scratchcard", "artifact": "contracts/ScratchCard.sol/ScratchCard" },
    { "file": "ScratchCardNFT.json",       "source": "scratchcard", "artifact": "contracts/ScratchCardNFT.sol/ScratchCardNFT" },
    { "file": "ScratchCardPrizePool.json", "source": "scratchcard", "artifact": "contracts/PrizePool.sol/PrizePool" },
    { "file": "IEntropyV2.json",           "source": "scratchcard", "artifact": "@pythnetwork/entropy-sdk-solidity/IEntropyV2.sol/IEntropyV2" },

    { "file": "PrizePool.json",            "source": "core", "artifact": "contracts/PrizePool.sol/PrizePool" },
    { "file": "GreatLotto.json",           "source": "core", "artifact": "contracts/GreatLotto.sol/GreatLotto" },
    { "file": "GreatLottoNFT.json",        "source": "core", "artifact": "contracts/GreatLottoNFT.sol/GreatLottoNFT" },
    { "file": "InvestmentCoinBase.json",   "source": "core", "artifact": "contracts/base/InvestmentCoinBase.sol/InvestmentCoinBase" },

    { "file": "DAOCoin.json",              "source": "infrastructure", "artifact": "contracts/DaoCoin.sol/DaoCoin" },
    { "file": "SalesChannel.json",         "source": "infrastructure", "artifact": "contracts/SalesChannel.sol/SalesChannel" },
    { "file": "BenefitPoolBase.json",      "source": "infrastructure", "artifact": "contracts/base/BenefitPoolBase.sol/BenefitPoolBase" },

    { "file": "GreatLottoCoin.json",       "source": "infrastructure",
      "variants": { "local":  "contracts/test/GreatLottoCoinTest.sol/GreatLottoCoinTest",
                    "remote": "contracts/GreatLottoCoin.sol/GreatLottoCoin" } }
  ],
  "external": ["permit_abi.json", "usdt_abi.json", "dai_abi.json", "4byte.directory"]
}
```

> 注:`source` 取值 `scratchcard` / `core` / `infrastructure`,与 `deploy.config.json` 的 `repos` 键一致(`sync-abi.mjs` 据此拼仓路径)。

---

## Task 2: abi-core.mjs —— 纯函数(TDD)

**Files:**
- Create: `infrastructure/scripts/abi-core.mjs`
- Test: `infrastructure/scripts/test/abi-core.test.mjs`

- [ ] **Step 1: 写失败测试**

Create `infrastructure/scripts/test/abi-core.test.mjs`:

```js
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  parseArgs, resolveArtifactRel, classifyDir, abiText, statusOf,
} from "../abi-core.mjs";

test("parseArgs: network 默认 localhost,--write/--network 解析", () => {
  assert.deepEqual(parseArgs([]), { network: "localhost", write: false });
  const a = parseArgs(["--network", "base", "--write"]);
  assert.equal(a.network, "base");
  assert.equal(a.write, true);
});

test("parseArgs: 未知参数抛错", () => {
  assert.throws(() => parseArgs(["--nope"]), /未知参数/);
});

test("resolveArtifactRel: 无 variants 返回 artifact", () => {
  const m = { file: "ScratchCard.json", artifact: "contracts/ScratchCard.sol/ScratchCard" };
  assert.equal(resolveArtifactRel(m, { local: true }), "contracts/ScratchCard.sol/ScratchCard");
});

test("resolveArtifactRel: variants 按 network.local 选", () => {
  const m = { file: "GreatLottoCoin.json",
    variants: { local: "contracts/test/GreatLottoCoinTest.sol/GreatLottoCoinTest",
                remote: "contracts/GreatLottoCoin.sol/GreatLottoCoin" } };
  assert.equal(resolveArtifactRel(m, { local: true }),  "contracts/test/GreatLottoCoinTest.sol/GreatLottoCoinTest");
  assert.equal(resolveArtifactRel(m, { local: false }), "contracts/GreatLottoCoin.sol/GreatLottoCoin");
});

test("classifyDir: 既非映射、又非 external 的为孤儿", () => {
  const mappings = [{ file: "ScratchCard.json" }, { file: "GreatLotto.json" }];
  const external = ["usdt_abi.json", "4byte.directory"];
  const entries = ["ScratchCard.json", "GreatLotto.json", "usdt_abi.json", "4byte.directory", "Callable.json", "ExecutorReward.json"];
  const { orphans } = classifyDir(entries, mappings, external);
  assert.deepEqual(orphans, ["Callable.json", "ExecutorReward.json"]);
});

test("abiText: 2 空格缩进 + 末尾换行", () => {
  assert.equal(abiText([{ a: 1 }]), '[\n  {\n    "a": 1\n  }\n]\n');
});

test("statusOf: new/unchanged/changed", () => {
  assert.equal(statusOf("X\n", null), "new");
  assert.equal(statusOf("X\n", "X\n"), "unchanged");
  assert.equal(statusOf("X\n", "Y\n"), "changed");
});
```

- [ ] **Step 2: 运行测试,确认失败**

Run: `cd infrastructure && node --test scripts/test/abi-core.test.mjs`
Expected: FAIL —— `Cannot find module '../abi-core.mjs'`

- [ ] **Step 3: 实现 abi-core.mjs**

Create `infrastructure/scripts/abi-core.mjs`:

```js
// 纯函数核心:无文件 IO,全部接收/返回普通对象,便于单测。

export function parseArgs(argv) {
  const a = { network: "localhost", write: false };
  for (let i = 0; i < argv.length; i++) {
    const t = argv[i];
    if (t === "--network") a.network = argv[++i];
    else if (t === "--write") a.write = true;
    else throw new Error(`未知参数: ${t}`);
  }
  return a;
}

// 带 variants(目前仅 GLC)按 network.local 选;否则用固定 artifact。
export function resolveArtifactRel(mapping, network) {
  if (mapping.variants) return network.local ? mapping.variants.local : mapping.variants.remote;
  return mapping.artifact;
}

// entries: abi 目录下所有条目名(文件 + 子目录)。
// 既不在 mappings.file、又不在 external 的,即孤儿(死件)。
export function classifyDir(entries, mappings, external) {
  const mapped = new Set(mappings.map((m) => m.file));
  const ext = new Set(external);
  const orphans = entries.filter((e) => !mapped.has(e) && !ext.has(e));
  return { orphans };
}

// 统一格式化口径:与现有 interface abi 文件一致(2 空格 + 末尾换行)。
export function abiText(abi) {
  return JSON.stringify(abi, null, 2) + "\n";
}

export function statusOf(newText, oldText) {
  if (oldText == null) return "new";
  return oldText === newText ? "unchanged" : "changed";
}
```

- [ ] **Step 4: 运行测试,确认通过**

Run: `cd infrastructure && node --test scripts/test/abi-core.test.mjs`
Expected: PASS（7 tests）

---

## Task 3: sync-abi.mjs —— CLI 外壳

**Files:**
- Create: `infrastructure/scripts/sync-abi.mjs`

- [ ] **Step 1: 实现 CLI**

Create `infrastructure/scripts/sync-abi.mjs`:

```js
#!/usr/bin/env node
// CLI 外壳:定位工作区根 → 读 artifact.abi → 比对 interface 现有文件 → 打印状态 → --write 落盘。
// 网络注册表复用 deploy.config.json(单一事实源),仅用于 GLC 变体选择。
import { readFileSync, writeFileSync, existsSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { resolveNetwork } from "./sync-core.mjs";
import { parseArgs, resolveArtifactRel, classifyDir, abiText, statusOf } from "./abi-core.mjs";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const ROOT = join(SCRIPT_DIR, "..", "..");          // infrastructure/scripts → 工作区根
const DEPLOY_CFG = JSON.parse(readFileSync(join(SCRIPT_DIR, "deploy.config.json"), "utf8"));
const ABI_CFG = JSON.parse(readFileSync(join(SCRIPT_DIR, "abi.config.json"), "utf8"));

function readJson(p) {
  return existsSync(p) ? JSON.parse(readFileSync(p, "utf8")) : null;
}
function artifactPath(repoDir, artifactRel) {
  return join(ROOT, repoDir, "artifacts", `${artifactRel}.json`);
}

const LABEL = {
  new:       "🆕 新建    ",
  changed:   "✏️  变更    ",
  unchanged: "   无变化  ",
  missing:   "⚠️  缺失    ",
};

function main() {
  const args = parseArgs(process.argv.slice(2));
  const net = resolveNetwork(DEPLOY_CFG, args.network);
  const repos = DEPLOY_CFG.repos;
  const abiDir = join(ROOT, ABI_CFG.interfaceAbiDir);

  // 1) 逐 mapping 解析 artifact → 取 .abi → 比对
  const rows = [];
  for (const m of ABI_CFG.mappings) {
    const rel = resolveArtifactRel(m, net);
    const artPath = artifactPath(repos[m.source], rel);
    const art = readJson(artPath);
    if (!art || !Array.isArray(art.abi) || art.abi.length === 0) {
      rows.push({ file: m.file, status: "missing", artPath });
      continue;
    }
    const newText = abiText(art.abi);
    const outPath = join(abiDir, m.file);
    const oldText = existsSync(outPath) ? readFileSync(outPath, "utf8") : null;
    rows.push({ file: m.file, status: statusOf(newText, oldText), outPath, newText });
  }

  // 2) 孤儿扫描
  const entries = existsSync(abiDir) ? readdirSync(abiDir) : [];
  const { orphans } = classifyDir(entries, ABI_CFG.mappings, ABI_CFG.external);

  // 3) 打印
  console.log(`\n[sync-abi] 网络 ${net.name}(local=${net.local}) → ${ABI_CFG.interfaceAbiDir}`);
  for (const r of rows) {
    console.log(`  ${LABEL[r.status]} ${r.file}${r.status === "missing" ? `   (${r.artPath})` : ""}`);
  }
  for (const o of orphans) console.log(`  ⚠️  孤儿     ${o}`);

  if (!args.write) { console.log("\n(dry-run,未写。加 --write 落盘)"); return; }
  const toWrite = rows.filter((r) => r.status === "new" || r.status === "changed");
  if (!toWrite.length) { console.log("\n无变更,跳过写入。"); return; }
  for (const r of toWrite) writeFileSync(r.outPath, r.newText);
  console.log(`\n✅ 已写入 ${toWrite.length} 个文件。`);
}

try { main(); } catch (e) { console.error("❌ " + e.message); process.exit(1); }
```

- [ ] **Step 2: 集成冒烟 —— dry-run**

Run: `cd infrastructure && node scripts/sync-abi.mjs`
Expected: 打印网络行 + 各文件状态(新建/变更/无变化/缺失) + 孤儿告警(如 `Callable.json` / `ExecutorReward.json`),结尾 `(dry-run,未写)`。

- [ ] **Step 3: 验证 dry-run 未改文件**

Run: `cd /Users/tongren/Documents/github/GreatLottoGroup && git -C interface status --short src/app/abi`
Expected: 无输出(dry-run 未改任何 abi 文件)。

- [ ] **Step 4: 落盘并校验幂等**

Run:
```bash
cd infrastructure
node scripts/sync-abi.mjs --write
node scripts/sync-abi.mjs            # 再 dry-run
```
Expected: 第一次打印 `✅ 已写入 N 个文件`;第二次所有映射文件状态为 `无变化`(幂等)。

---

## Task 4: deploy-local.sh 集成

**Files:**
- Modify: `infrastructure/scripts/deploy-local.sh`

- [ ] **Step 1: 在步骤 7 后插入 ABI 同步**

在 `infrastructure/scripts/deploy-local.sh` 中,找到步骤 7 这段:

```bash
# 7) 同步三仓地址 → interface address.json[31337](含 MockEntropy)
node "$SYNC" --network localhost --write --only interface
```

在其**后**、步骤 8(`# 8) 收尾`)**前**插入:

```bash
# 7b) 同步三仓 ABI → interface(本地变体:GLC=GreatLottoCoinTest)
log "同步 ABI → interface..."
node "$SCRIPT_DIR/sync-abi.mjs" --network localhost --write
```

- [ ] **Step 2: bash 语法检查**

Run: `cd infrastructure && bash -n scripts/deploy-local.sh`
Expected: 无输出(语法 OK)。

---

## Task 5: README 补 sync-abi 用法

**Files:**
- Modify: `infrastructure/scripts/README.md`

- [ ] **Step 1: 文件表加一行**

在 `infrastructure/scripts/README.md` 顶部文件表(含 `deploy-local.sh` 那张表)里,`sync-addresses.mjs` 行后追加一行:

```markdown
| `sync-abi.mjs` | ABI 同步 CLI(三仓 artifact → interface) |
| `abi.config.json` | ABI 映射(加/改合约 abi 改这里) |
```

- [ ] **Step 2: 新增「同步 ABI」段落**

在「单独跑地址同步(任意网络)」段落**之后**,新增一节:

````markdown
## 单独跑 ABI 同步

把三仓 hardhat 编译产物(`artifacts/`)里的合约 ABI 抽取(只取 `.abi` 数组)写到 `interface/src/app/abi/`。

```bash
# dry-run(默认):打印每文件状态(新建/变更/无变化/缺失/孤儿),不写
node scripts/sync-abi.mjs

# 落盘
node scripts/sync-abi.mjs --write

# 非本地变体(影响 GreatLottoCoin:base/arbitrum 取生产合约,localhost 取 Test)
node scripts/sync-abi.mjs --network base --write
```

- `--network` 可选,默认 `localhost`,**仅影响带变体的 mapping(目前只有 `GreatLottoCoin`)**;其余合约 ABI 与网络无关。
- 前置:对应仓已 `npx hardhat compile`(artifact 缺失会告警并跳过该文件)。`deploy-local.sh` 里 `ignition deploy` 已隐式编译,故一键流程无需额外编译。
- **孤儿告警**:abi 目录里既不在 `abi.config.json` 映射、又不在 `external` 白名单的文件(历史死件,如 `Callable.json`)会被列出,**只报告不删**。

### 加 / 改一个合约 ABI

改 `abi.config.json` 的 `mappings`:`file`(interface 目标文件名)+ `source`(`scratchcard`/`core`/`infrastructure`)+ `artifact`(`artifacts/` 下相对路径,不含 `.json`)。有 Test/生产变体的用 `variants.{local,remote}` 代替 `artifact`。
````

---

## Task 6: 端到端验证 + 一次性提交

**Files:** 无(验证 + 提交)

- [ ] **Step 1: 全量脚本单测**

Run: `cd infrastructure && npm run test:scripts`
Expected: 全绿(含既有 sync-core 13 tests + 新增 abi-core 7 tests)。

- [ ] **Step 2: 校验 interface 关键 abi 文件非空且为合法数组**

Run:
```bash
cd /Users/tongren/Documents/github/GreatLottoGroup
node -e "for (const f of ['ScratchCard','ScratchCardNFT','ScratchCardPrizePool','GreatLotto','PrizePool','DAOCoin','GreatLottoCoin','IEntropyV2']) { const a=require('./interface/src/app/abi/'+f+'.json'); if(!Array.isArray(a)||!a.length) throw new Error('空/非数组: '+f); } console.log('OK: interface abi 关键文件均为非空数组');"
```
Expected: `OK: interface abi 关键文件均为非空数组`。

- [ ] **Step 3: 校验 ScratchCardPrizePool 与 ScratchCard 仓 artifact 一致**

Run:
```bash
cd /Users/tongren/Documents/github/GreatLottoGroup
node -e "const a=require('./ScratchCard/artifacts/contracts/PrizePool.sol/PrizePool.json').abi; const b=require('./interface/src/app/abi/ScratchCardPrizePool.json'); if(JSON.stringify(a)!==JSON.stringify(b)) throw new Error('不一致'); console.log('OK: ScratchCardPrizePool.json 与 SC artifact 一致');"
```
Expected: `OK: ScratchCardPrizePool.json 与 SC artifact 一致`。

- [ ] **Step 4: 一次性提交(infrastructure 仓的脚本/文档/配置)**

> 用户偏好:不逐步提交。此处一次性提交本计划新增/修改的 infrastructure 仓文件。

```bash
cd /Users/tongren/Documents/github/GreatLottoGroup/infrastructure
git add scripts/abi.config.json scripts/abi-core.mjs scripts/sync-abi.mjs \
        scripts/test/abi-core.test.mjs scripts/deploy-local.sh scripts/README.md
git commit -m "feat(scripts): sync-abi.mjs — sync contract ABIs to interface"
```

- [ ] **Step 5: 提交 interface 仓被同步改动的 abi 文件(若有变更)**

> abi 文件属 interface 仓,按工作区惯例在该仓提交。

```bash
cd /Users/tongren/Documents/github/GreatLottoGroup/interface
git add src/app/abi
git commit -m "chore(abi): refresh contract ABIs via sync-abi" || true
```

---

## Self-Review 记录

- **Spec 覆盖**:设计 §3 架构(配置+核心+CLI+集成)→ Task 1/2/3/4;§4 `abi.config.json`(映射+external+variants)→ Task 1;§5 CLI(调用约定/主流程/写入安全)→ Task 3;§6 deploy-local 集成 → Task 4;§7 纯函数清单 → Task 2;§8 错误处理(缺失跳过/孤儿告警)→ Task 3(rows/orphans 分支);§9 验收 → Task 6;README(设计未单列但属交付惯例)→ Task 5。
- **决策落地**:A1 同步+报孤儿 → `classifyDir` + CLI 打印;A2 `ScratchCardPrizePool.json` → Task 1 映射 + Task 6 Step 3 校验;A3 GLC 变体 → `resolveArtifactRel` + Task 2 用例;A4 独立 `abi.config.json` + 复用 `deploy.config.json` 网络表 → Task 1 + Task 3 import `resolveNetwork`。
- **类型一致**:`abi-core.mjs` 导出 `parseArgs/resolveArtifactRel/classifyDir/abiText/statusOf` 与 `sync-abi.mjs` import 列表、`abi-core.test.mjs` import 列表三处一致;`status` 取值 `new/changed/unchanged/missing` 在 `statusOf`、CLI `LABEL`、`toWrite` 过滤三处一致;mapping 字段 `file/source/artifact/variants` 在 config、`resolveArtifactRel`、CLI 解析一致。
- **占位符**:无 TBD/TODO;所有代码步骤含完整实现。
- **提交策略**:遵用户偏好,Task 1–5 无 commit 步骤,集中到 Task 6。
