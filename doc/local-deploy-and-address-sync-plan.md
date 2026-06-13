# 本地一键部署 + 跨仓地址同步 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `infrastructure/scripts/` 交付一套脚本,一条命令完成本地链(31337)的三仓部署并自动回填地址,且地址同步逻辑对所有网络通用。

**Architecture:** 纯函数核心(`sync-core.mjs`,无 IO,可单测)+ CLI 外壳(`sync-addresses.mjs`,负责读写 JSON 与写入闸门)+ bash 编排器(`deploy-local.sh`,串联起链/部署/同步)+ 声明式配置(`deploy.config.json`)+ 使用文档(`README.md`)。

**Tech Stack:** Node ESM(`.mjs`)、Node 内置测试器(`node --test`,本机 v24)、bash、Hardhat Ignition、curl。

**设计依据:** [local-deploy-and-address-sync-design.md](./local-deploy-and-address-sync-design.md)。本计划在实现层对设计 §4.3 做一处细化:**entropy 从 `mappings` 中抽出**,改为独立的 `entropy` 配置块(因 entropy 地址/provider 的来源随本地/非本地而变,见设计 §5.4),其余与设计一致。

---

## 文件结构

| 文件 | 职责 |
|------|------|
| `infrastructure/scripts/deploy.config.json` | 声明式配置:网络注册表 + 仓路径 + 地址映射 + entropy 块。加链/加合约只改这里 |
| `infrastructure/scripts/sync-core.mjs` | 纯函数:解析网络/参数、解析地址、计算 diff、应用 diff、格式化。无文件 IO |
| `infrastructure/scripts/sync-addresses.mjs` | CLI:定位工作区根、读写 JSON、调用核心、写入闸门(本地自动/非本地确认) |
| `infrastructure/scripts/deploy-local.sh` | 一键本地编排(仅 31337):预检 → 清旧 → 起链 → 部署三仓 → 两次同步 |
| `infrastructure/scripts/README.md` | 使用文档(交付物):一键部署用法 / 同步器单独用法 / 改配置指引 / 错误对照 |
| `infrastructure/scripts/test/sync-core.test.mjs` | `node --test` 单测,覆盖 `sync-core.mjs` 全部纯函数 |

工作区根 = `infrastructure/` 的上级目录(4 仓共同父目录)。脚本经 `<scriptDir>/../..` 解析到根,再拼各仓相对路径。

---

## Task 1: 脚手架 + 配置文件

**Files:**
- Create: `infrastructure/scripts/deploy.config.json`
- Modify: `infrastructure/package.json`(加 `test:scripts` 脚本)

- [ ] **Step 1: 建目录与配置文件**

Create `infrastructure/scripts/deploy.config.json`:

```json
{
  "networks": {
    "localhost":       { "chainId": 31337,  "scModule": "ScratchCardLocalModule", "coreModule": "GreatLottoCoreLocal", "local": true },
    "baseSepolia":     { "chainId": 84532,  "scModule": "ScratchCardModule",      "coreModule": "GreatLottoCore",      "local": false },
    "arbitrumSepolia": { "chainId": 421614, "scModule": "ScratchCardModule",      "coreModule": "GreatLottoCore",      "local": false },
    "base":            { "chainId": 8453,   "scModule": "ScratchCardModule",      "coreModule": "GreatLottoCore",      "local": false },
    "arbitrum":        { "chainId": 42161,  "scModule": "ScratchCardModule",      "coreModule": "GreatLottoCore",      "local": false }
  },
  "repos": {
    "infrastructure": "infrastructure",
    "scratchcard":    "ScratchCard",
    "core":           "GreatLottoCore",
    "interfaceAddressFile": "interface/src/app/launch/address.json"
  },
  "mappings": [
    { "logical": "GreatLottoCoin", "source": "infrastructure",
      "keys": ["Infrastructure#GreatLottoCoinTest", "Infrastructure#GreatLottoCoin"],
      "targets": { "scParam": "greatLottoCoinAddress", "coreParam": "greatLottoCoinAddress", "interface": "contracts.GreatCoinContractAddress" } },
    { "logical": "DaoCoin", "source": "infrastructure",
      "keys": ["Infrastructure#DaoCoin"],
      "targets": { "scParam": "daoCoinAddress", "coreParam": "daoCoinAddress", "interface": "contracts.DaoCoinContractAddress" } },
    { "logical": "DaoBenefitPool", "source": "infrastructure",
      "keys": ["Infrastructure#DaoBenefitPool"],
      "targets": { "scParam": "daoBenefitPoolAddress", "coreParam": "daoBenefitPoolAddress", "interface": "contracts.DaoBenefitPoolContractAddress" } },
    { "logical": "SalesChannel", "source": "infrastructure",
      "keys": ["Infrastructure#SalesChannel"],
      "targets": { "scParam": "salesChannelAddress", "coreParam": "salesChannelAddress", "interface": "contracts.SalesChannelContractAddress" } },

    { "logical": "ScratchCard", "source": "scratchcard",
      "keys": ["ScratchCardLocalModule#ScratchCard", "ScratchCardModule#ScratchCard"],
      "targets": { "interface": "contracts.ScratchCardContractAddress" } },
    { "logical": "ScratchCardNFT", "source": "scratchcard",
      "keys": ["ScratchCardLocalModule#ScratchCardNFT", "ScratchCardModule#ScratchCardNFT"],
      "targets": { "interface": "contracts.ScratchCardNFTContractAddress" } },

    { "logical": "GreatLotto", "source": "core",
      "keys": ["GreatLottoCoreLocal#GreatLotto", "GreatLottoCore#GreatLotto"],
      "targets": { "interface": "contracts.GreatLottoContractAddress" } },
    { "logical": "GreatLottoNFT", "source": "core",
      "keys": ["GreatLottoCoreLocal#GreatLottoNFT", "GreatLottoCore#GreatLottoNFT"],
      "targets": { "interface": "contracts.GreatNftContractAddress" } },
    { "logical": "CorePrizePool", "source": "core",
      "keys": ["GreatLottoCoreLocal#PrizePool", "GreatLottoCore#PrizePool"],
      "targets": { "interface": "contracts.PrizePoolContractAddress" } },
    { "logical": "InvestmentCoin", "source": "core",
      "keys": ["GreatLottoCoreLocal#InvestmentCoin", "GreatLottoCore#InvestmentCoin"],
      "targets": { "interface": "contracts.InvestmentCoinContractAddress" } },
    { "logical": "InvestmentBenefitPool", "source": "core",
      "keys": ["GreatLottoCoreLocal#InvestmentBenefitPool", "GreatLottoCore#InvestmentBenefitPool"],
      "targets": { "interface": "contracts.InvestmentBenefitPoolContractAddress" } }
  ],
  "entropy": {
    "interfaceAddressKey": "entropy.entropyAddress",
    "interfaceProviderKey": "entropy.entropyProvider",
    "local":  { "addressFromDeployed": { "source": "scratchcard", "keys": ["ScratchCardLocalModule#MockEntropy"] },
                "providerFromScParam": "entropyProvider" },
    "remote": { "addressFromScParam": "entropyAddress",
                "providerFromScParam": "entropyProvider" }
  }
}
```

> 注:interface 的 `GreatEthContractAddress` / `InvestmentEthContractAddress` / `GuaranteePoolContractAddress` 本地不部署对应合约(已核对 Core 本地部署产物不含),故不进 `mappings`,保持留空(设计 §8 item 3)。

- [ ] **Step 2: 给 infrastructure 加 scripts 测试命令**

Modify `infrastructure/package.json` 的 `"scripts"` 块,新增一行(放在 `"coverage"` 后):

```json
  "scripts": {
    "test": "forge test",
    "gas": "forge test --gas-report",
    "coverage": "forge coverage --report summary",
    "test:scripts": "node --test scripts/test/",
    "compile": "hardhat compile"
  },
```

- [ ] **Step 3: Commit**

```bash
cd infrastructure
git add scripts/deploy.config.json package.json
git commit -m "chore(scripts): scaffold deploy config + test:scripts runner"
```

---

## Task 2: sync-core.mjs —— 网络/参数解析 + 地址解析(TDD)

**Files:**
- Create: `infrastructure/scripts/sync-core.mjs`
- Test: `infrastructure/scripts/test/sync-core.test.mjs`

- [ ] **Step 1: 写失败测试**

Create `infrastructure/scripts/test/sync-core.test.mjs`:

```js
import { test } from "node:test";
import assert from "node:assert/strict";
import {
  parseArgs, resolveNetwork, isEmptyAddr,
  resolveContractAddresses, resolveEntropy,
} from "../sync-core.mjs";

const CONFIG = {
  networks: {
    localhost:   { chainId: 31337, scModule: "ScratchCardLocalModule", coreModule: "GreatLottoCoreLocal", local: true },
    baseSepolia: { chainId: 84532, scModule: "ScratchCardModule", coreModule: "GreatLottoCore", local: false },
  },
  mappings: [
    { logical: "GreatLottoCoin", source: "infrastructure",
      keys: ["Infrastructure#GreatLottoCoinTest", "Infrastructure#GreatLottoCoin"],
      targets: { scParam: "greatLottoCoinAddress", interface: "contracts.GreatCoinContractAddress" } },
    { logical: "ScratchCard", source: "scratchcard",
      keys: ["ScratchCardLocalModule#ScratchCard", "ScratchCardModule#ScratchCard"],
      targets: { interface: "contracts.ScratchCardContractAddress" } },
  ],
  entropy: {
    interfaceAddressKey: "entropy.entropyAddress",
    interfaceProviderKey: "entropy.entropyProvider",
    local:  { addressFromDeployed: { source: "scratchcard", keys: ["ScratchCardLocalModule#MockEntropy"] }, providerFromScParam: "entropyProvider" },
    remote: { addressFromScParam: "entropyAddress", providerFromScParam: "entropyProvider" },
  },
};
const ZERO = "0x0000000000000000000000000000000000000000";

test("parseArgs: 解析 network/write/yes/only", () => {
  const a = parseArgs(["--network", "localhost", "--write", "--only", "sc,core"]);
  assert.equal(a.network, "localhost");
  assert.equal(a.write, true);
  assert.equal(a.yes, false);
  assert.deepEqual(a.only, ["sc", "core"]);
});

test("parseArgs: 缺 --network 抛错", () => {
  assert.throws(() => parseArgs(["--write"]), /缺少 --network/);
});

test("resolveNetwork: 按名与按 chainId 均可", () => {
  assert.equal(resolveNetwork(CONFIG, "localhost").chainId, 31337);
  assert.equal(resolveNetwork(CONFIG, "84532").name, "baseSepolia");
  assert.throws(() => resolveNetwork(CONFIG, "nope"), /未知网络/);
});

test("isEmptyAddr: 空串/零地址为空", () => {
  assert.equal(isEmptyAddr(""), true);
  assert.equal(isEmptyAddr(undefined), true);
  assert.equal(isEmptyAddr(ZERO), true);
  assert.equal(isEmptyAddr("0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512"), false);
});

test("resolveContractAddresses: 命中第一个存在的 key", () => {
  const net = resolveNetwork(CONFIG, "localhost");
  const deployed = {
    infrastructure: { "Infrastructure#GreatLottoCoinTest": "0xCoin" },
    scratchcard: { "ScratchCardLocalModule#ScratchCard": "0xSC" },
    core: {},
  };
  const { resolved, warnings } = resolveContractAddresses(CONFIG, net, deployed);
  assert.equal(resolved.GreatLottoCoin, "0xCoin");
  assert.equal(resolved.ScratchCard, "0xSC");
  assert.equal(warnings.length, 0);
});

test("resolveContractAddresses: 未解析到则警告且不入 resolved", () => {
  const net = resolveNetwork(CONFIG, "localhost");
  const { resolved, warnings } = resolveContractAddresses(CONFIG, net, { infrastructure: {}, scratchcard: {}, core: {} });
  assert.equal(resolved.GreatLottoCoin, undefined);
  assert.equal(warnings.length, 2);
});

test("resolveEntropy: 本地取 MockEntropy + scParam provider", () => {
  const net = resolveNetwork(CONFIG, "localhost");
  const deployed = { scratchcard: { "ScratchCardLocalModule#MockEntropy": "0xMock" }, infrastructure: {}, core: {} };
  const scParamMod = { entropyProvider: "0x0000000000000000000000000000000000000001" };
  const { entropyAddress, entropyProvider } = resolveEntropy(CONFIG, net, deployed, scParamMod);
  assert.equal(entropyAddress, "0xMock");
  assert.equal(entropyProvider, "0x0000000000000000000000000000000000000001");
});

test("resolveEntropy: 非本地从 scParam 读 address+provider", () => {
  const net = resolveNetwork(CONFIG, "baseSepolia");
  const scParamMod = { entropyAddress: "0xPyth", entropyProvider: "0xProv" };
  const { entropyAddress, entropyProvider } = resolveEntropy(CONFIG, net, {}, scParamMod);
  assert.equal(entropyAddress, "0xPyth");
  assert.equal(entropyProvider, "0xProv");
});
```

- [ ] **Step 2: 运行测试,确认失败**

Run: `cd infrastructure && node --test scripts/test/`
Expected: FAIL —— `Cannot find module '../sync-core.mjs'`

- [ ] **Step 3: 实现 sync-core.mjs(本任务部分)**

Create `infrastructure/scripts/sync-core.mjs`:

```js
// 纯函数核心:无文件 IO,全部接收/返回普通对象,便于单测。
export const ZERO_ADDR = "0x0000000000000000000000000000000000000000";

export function isEmptyAddr(v) {
  return !v || v.toLowerCase() === ZERO_ADDR;
}

export function parseArgs(argv) {
  const a = { network: null, write: false, yes: false, only: null };
  for (let i = 0; i < argv.length; i++) {
    const t = argv[i];
    if (t === "--network") a.network = argv[++i];
    else if (t === "--write") a.write = true;
    else if (t === "--yes") a.yes = true;
    else if (t === "--only") a.only = argv[++i].split(",").map((s) => s.trim()).filter(Boolean);
    else throw new Error(`未知参数: ${t}`);
  }
  if (!a.network) throw new Error("缺少 --network");
  return a;
}

export function resolveNetwork(config, arg) {
  if (config.networks[arg]) return { name: arg, ...config.networks[arg] };
  for (const [name, n] of Object.entries(config.networks)) {
    if (String(n.chainId) === String(arg)) return { name, ...n };
  }
  throw new Error(`未知网络: ${arg}`);
}

export function resolveContractAddresses(config, network, deployedByRepo) {
  const resolved = {};
  const warnings = [];
  for (const m of config.mappings) {
    if (m.localOnly && !network.local) continue;
    const dict = deployedByRepo[m.source] || {};
    let found;
    for (const k of m.keys) {
      if (!isEmptyAddr(dict[k])) { found = dict[k]; break; }
    }
    if (found === undefined) {
      warnings.push(`未解析到 ${m.logical}(来源 ${m.source},尝试 keys: ${m.keys.join(", ")})`);
      continue;
    }
    resolved[m.logical] = found;
  }
  return { resolved, warnings };
}

export function resolveEntropy(config, network, deployedByRepo, scParamModule) {
  const e = config.entropy;
  const warnings = [];
  let entropyAddress, entropyProvider;
  const scMod = scParamModule || {};
  if (network.local) {
    const src = e.local.addressFromDeployed;
    const dict = (deployedByRepo[src.source]) || {};
    for (const k of src.keys) if (!isEmptyAddr(dict[k])) { entropyAddress = dict[k]; break; }
    entropyProvider = scMod[e.local.providerFromScParam];
  } else {
    entropyAddress = scMod[e.remote.addressFromScParam];
    entropyProvider = scMod[e.remote.providerFromScParam];
  }
  if (isEmptyAddr(entropyAddress)) warnings.push("未解析到 entropyAddress");
  return { entropyAddress: entropyAddress || "", entropyProvider: entropyProvider || "", warnings };
}
```

- [ ] **Step 4: 运行测试,确认通过**

Run: `cd infrastructure && node --test scripts/test/`
Expected: PASS（8 tests）

- [ ] **Step 5: Commit**

```bash
cd infrastructure
git add scripts/sync-core.mjs scripts/test/sync-core.test.mjs
git commit -m "feat(scripts): sync-core network/arg/address resolvers + tests"
```

---

## Task 3: sync-core.mjs —— diff 引擎(TDD)

**Files:**
- Modify: `infrastructure/scripts/sync-core.mjs`(追加 diff 相关导出)
- Modify: `infrastructure/scripts/test/sync-core.test.mjs`(追加测试)

- [ ] **Step 1: 追加失败测试**

在 `infrastructure/scripts/test/sync-core.test.mjs` 顶部 import 改为:

```js
import {
  parseArgs, resolveNetwork, isEmptyAddr,
  resolveContractAddresses, resolveEntropy,
  buildDiffs, applyDiffs, formatDiffs, getPath,
} from "../sync-core.mjs";
```

并在文件末尾追加:

```js
test("buildDiffs: 仅对变化字段产出 diff,跳过空 newValue 与同值", () => {
  const net = resolveNetwork(CONFIG, "localhost");
  const resolved = { GreatLottoCoin: "0xCoin", ScratchCard: "0xSC" };
  const targets = {
    scParam: { ScratchCardLocalModule: { greatLottoCoinAddress: "0xOLD" } },
    core: { GreatLottoCoreLocal: {} },
    interface: { "31337": { contracts: { GreatCoinContractAddress: "0xCoin", ScratchCardContractAddress: "" }, entropy: {} } },
  };
  const entropy = { entropyAddress: "0xMock", entropyProvider: "0x0000000000000000000000000000000000000001" };
  const diffs = buildDiffs({ config: CONFIG, network: net, resolved, entropy, targets, only: null });
  const labels = diffs.map((d) => d.label);
  // scParam GLC: 0xOLD → 0xCoin(变化)
  assert.ok(labels.some((l) => l.includes("greatLottoCoinAddress")));
  // interface GreatCoin 同值(0xCoin==0xCoin)→ 不产出
  assert.ok(!labels.some((l) => l.includes("GreatCoinContractAddress")));
  // interface ScratchCard 空→0xSC(变化)
  assert.ok(labels.some((l) => l.includes("ScratchCardContractAddress")));
  // entropy 写入 interface
  assert.ok(labels.some((l) => l.includes("entropyAddress")));
});

test("buildDiffs: --only 过滤目的地", () => {
  const net = resolveNetwork(CONFIG, "localhost");
  const resolved = { GreatLottoCoin: "0xCoin" };
  const targets = {
    scParam: { ScratchCardLocalModule: { greatLottoCoinAddress: "" } },
    core: { GreatLottoCoreLocal: {} },
    interface: { "31337": { contracts: { GreatCoinContractAddress: "" }, entropy: {} } },
  };
  const diffs = buildDiffs({ config: CONFIG, network: net, resolved, entropy: null, targets, only: ["sc"] });
  assert.ok(diffs.every((d) => d.scope === "sc"));
});

test("applyDiffs: 按 scope+path 写回,保留其它 key", () => {
  const targets = {
    scParam: { ScratchCardLocalModule: { greatLottoCoinAddress: "0xOLD", owner: "0xOwner" } },
    core: {}, interface: {},
  };
  const diffs = [{ scope: "sc", path: ["ScratchCardLocalModule", "greatLottoCoinAddress"], oldValue: "0xOLD", newValue: "0xNEW", label: "x" }];
  applyDiffs(targets, diffs);
  assert.equal(targets.scParam.ScratchCardLocalModule.greatLottoCoinAddress, "0xNEW");
  assert.equal(targets.scParam.ScratchCardLocalModule.owner, "0xOwner");
});

test("getPath: 字符串路径读取(interface 用)", () => {
  const obj = { "31337": { contracts: { ScratchCardContractAddress: "0xSC" } } };
  assert.equal(getPath(obj, ["31337", "contracts", "ScratchCardContractAddress"]), "0xSC");
});

test("formatDiffs: 无变化返回占位", () => {
  assert.equal(formatDiffs([]), "(无变化)");
});
```

- [ ] **Step 2: 运行测试,确认新增用例失败**

Run: `cd infrastructure && node --test scripts/test/`
Expected: FAIL —— `buildDiffs is not a function` / `getPath is not a function`

- [ ] **Step 3: 追加 diff 引擎到 sync-core.mjs**

在 `infrastructure/scripts/sync-core.mjs` 末尾追加:

```js
export function getPath(obj, path) {
  return path.reduce((o, k) => (o == null ? undefined : o[k]), obj);
}

export function setPath(obj, path, val) {
  let o = obj;
  for (let i = 0; i < path.length - 1; i++) {
    if (o[path[i]] == null) o[path[i]] = {};
    o = o[path[i]];
  }
  o[path[path.length - 1]] = val;
}

// scope ∈ {"sc","core","interface"};label 为人类可读展示串。
function pushDiff(diffs, scope, obj, path, newValue, label) {
  if (isEmptyAddr(newValue)) return;            // 绝不写空值,避免刷掉已有真实地址
  const oldValue = getPath(obj, path) || "";
  if (oldValue === newValue) return;            // 无变化不产出
  diffs.push({ scope, path, oldValue, newValue, label });
}

export function buildDiffs({ config, network, resolved, entropy, targets, only }) {
  const diffs = [];
  const want = only ? new Set(only) : new Set(["sc", "core", "interface"]);
  const cid = String(network.chainId);
  for (const m of config.mappings) {
    if (m.localOnly && !network.local) continue;
    const addr = resolved[m.logical];
    if (addr === undefined) continue;           // 未解析(已在解析阶段告警)
    if (want.has("sc") && m.targets.scParam) {
      pushDiff(diffs, "sc", targets.scParam, [network.scModule, m.targets.scParam], addr,
        `sc :: ${network.scModule}.${m.targets.scParam}`);
    }
    if (want.has("core") && m.targets.coreParam) {
      pushDiff(diffs, "core", targets.core, [network.coreModule, m.targets.coreParam], addr,
        `core :: ${network.coreModule}.${m.targets.coreParam}`);
    }
    if (want.has("interface") && m.targets.interface) {
      const p = [cid, ...m.targets.interface.split(".")];
      pushDiff(diffs, "interface", targets.interface, p, addr, `interface :: [${cid}].${m.targets.interface}`);
    }
  }
  if (want.has("interface") && entropy) {
    for (const [k, v] of [
      [config.entropy.interfaceAddressKey, entropy.entropyAddress],
      [config.entropy.interfaceProviderKey, entropy.entropyProvider],
    ]) {
      pushDiff(diffs, "interface", targets.interface, [cid, ...k.split(".")], v, `interface :: [${cid}].${k}`);
    }
  }
  return diffs;
}

export function applyDiffs(targets, diffs) {
  const byScope = { sc: targets.scParam, core: targets.core, interface: targets.interface };
  for (const d of diffs) setPath(byScope[d.scope], d.path, d.newValue);
  return targets;
}

export function formatDiffs(diffs) {
  if (!diffs.length) return "(无变化)";
  return diffs.map((d) => `  ${d.label}\n      ${d.oldValue || "∅"} → ${d.newValue}`).join("\n");
}
```

- [ ] **Step 4: 运行测试,确认全部通过**

Run: `cd infrastructure && node --test scripts/test/`
Expected: PASS（13 tests）

- [ ] **Step 5: Commit**

```bash
cd infrastructure
git add scripts/sync-core.mjs scripts/test/sync-core.test.mjs
git commit -m "feat(scripts): sync-core diff engine (build/apply/format) + tests"
```

---

## Task 4: sync-addresses.mjs —— CLI 外壳 + 写入闸门

**Files:**
- Create: `infrastructure/scripts/sync-addresses.mjs`

- [ ] **Step 1: 实现 CLI**

Create `infrastructure/scripts/sync-addresses.mjs`:

```js
#!/usr/bin/env node
// CLI 外壳:定位工作区根 → 读 deployed_addresses / 参数 / interface → 调 sync-core → 打印 diff → 写入闸门。
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { createInterface } from "node:readline/promises";
import {
  parseArgs, resolveNetwork, resolveContractAddresses, resolveEntropy,
  buildDiffs, applyDiffs, formatDiffs,
} from "./sync-core.mjs";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const ROOT = join(SCRIPT_DIR, "..", "..");          // infrastructure/scripts → 工作区根
const CONFIG = readJson(join(SCRIPT_DIR, "deploy.config.json"));

function readJson(p) {
  if (!existsSync(p)) return null;
  return JSON.parse(readFileSync(p, "utf8"));
}
function writeJson(p, obj) {
  writeFileSync(p, JSON.stringify(obj, null, 2) + "\n");
}
function deployedPath(repoDir, chainId) {
  return join(ROOT, repoDir, "ignition", "deployments", `chain-${chainId}`, "deployed_addresses.json");
}
function paramPath(repoDir, network) {
  return join(ROOT, repoDir, "ignition", "parameters", `${network}.json`);
}

async function confirm(question) {
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  const ans = (await rl.question(question)).trim();
  rl.close();
  return ans === "yes";
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const net = resolveNetwork(CONFIG, args.network);
  const r = CONFIG.repos;

  // 1) 读各仓 deployed_addresses
  const deployedByRepo = {
    infrastructure: readJson(deployedPath(r.infrastructure, net.chainId)) || {},
    scratchcard: readJson(deployedPath(r.scratchcard, net.chainId)) || {},
    core: readJson(deployedPath(r.core, net.chainId)) || {},
  };

  // 2) 读目的地文件
  const scParamFile = paramPath(r.scratchcard, net.name);
  const coreParamFile = paramPath(r.core, net.name);
  const ifaceFile = join(ROOT, r.interfaceAddressFile);
  const scParam = readJson(scParamFile) || {};
  const coreParam = readJson(coreParamFile) || {};
  const iface = readJson(ifaceFile) || {};
  const scParamModule = scParam[net.scModule] || {};

  // 3) 解析地址 + entropy
  const { resolved, warnings: w1 } = resolveContractAddresses(CONFIG, net, deployedByRepo);
  const { entropyAddress, entropyProvider, warnings: w2 } = resolveEntropy(CONFIG, net, deployedByRepo, scParamModule);
  const warnings = [...w1, ...w2];

  // 4) 计算 diff
  const targets = { scParam, core: coreParam, interface: iface };
  const diffs = buildDiffs({
    config: CONFIG, network: net, resolved,
    entropy: { entropyAddress, entropyProvider }, targets, only: args.only,
  });

  // 5) 打印
  console.log(`\n[sync] 网络 ${net.name}(chainId ${net.chainId}, local=${net.local})`);
  if (warnings.length) console.log("⚠️  " + warnings.join("\n⚠️  "));
  console.log("变更:\n" + formatDiffs(diffs));

  if (!args.write) { console.log("\n(dry-run,未写。加 --write 落盘)"); return; }
  if (!diffs.length) { console.log("\n无变更,跳过写入。"); return; }

  // 6) 写入闸门
  if (!net.local && !args.yes) {
    if (!(await confirm(`\n⚠️ 非本地网络 ${net.name},确认写入以上变更?输入 yes: `))) {
      console.log("已取消。"); return;
    }
  }
  applyDiffs(targets, diffs);
  const scopes = new Set(diffs.map((d) => d.scope));
  if (scopes.has("sc")) writeJson(scParamFile, scParam);
  if (scopes.has("core")) writeJson(coreParamFile, coreParam);
  if (scopes.has("interface")) writeJson(ifaceFile, iface);
  console.log("\n✅ 已写入。");
}

main().catch((e) => { console.error("❌ " + e.message); process.exit(1); });
```

- [ ] **Step 2: 集成冒烟 —— 对当前仓库状态 dry-run**

Run: `cd infrastructure && node scripts/sync-addresses.mjs --network localhost`
Expected: 打印网络行 + 变更清单(基于当前 chain-31337 部署),结尾打印 `(dry-run,未写)`,**不修改任何文件**。

- [ ] **Step 3: 验证 dry-run 未改文件**

Run: `cd /Users/tongren/Documents/github/GreatLottoGroup && git -C ScratchCard status --short ignition/parameters/localhost.json`
Expected: 无输出（文件未被改动）。

- [ ] **Step 4: Commit**

```bash
cd infrastructure
git add scripts/sync-addresses.mjs
git commit -m "feat(scripts): sync-addresses CLI with dry-run + per-network write gate"
```

---

## Task 5: deploy-local.sh —— 一键本地编排器

**Files:**
- Create: `infrastructure/scripts/deploy-local.sh`

- [ ] **Step 1: 实现编排脚本**

Create `infrastructure/scripts/deploy-local.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"          # 工作区根(4 仓父目录)
SYNC="$SCRIPT_DIR/sync-addresses.mjs"
RPC="http://127.0.0.1:8545"
NODE_PID=""

log(){ printf '\033[1;34m[deploy-local]\033[0m %s\n' "$*"; }
die(){ printf '\033[1;31m[deploy-local] 错误:\033[0m %s\n' "$*" >&2; exit 1; }
cleanup(){ [ -n "$NODE_PID" ] && kill "$NODE_PID" 2>/dev/null || true; }
trap 'code=$?; if [ "$code" -ne 0 ]; then log "失败(exit $code),拆除本地节点"; cleanup; fi' EXIT
trap 'die "用户中断"' INT

# 1) 预检:下游两仓 infrastructure 软链接在位
for repo in ScratchCard GreatLottoCore; do
  [ -e "$ROOT/$repo/node_modules/@greatlotto/infrastructure" ] \
    || die "$repo 缺 @greatlotto/infrastructure 软链接;在该仓跑 pnpm i 或 npm link @greatlotto/infrastructure"
done

# 2) 清三仓 chain-31337 旧部署(新链 ⇒ 旧 journal 会冲突)
for repo in infrastructure ScratchCard GreatLottoCore; do
  rm -rf "$ROOT/$repo/ignition/deployments/chain-31337"
done
log "已清理三仓 chain-31337 旧部署"

# 3) 起本地链(由 infrastructure 起,任一仓 hardhat node 都是同一条 31337)
log "启动 hardhat node..."
( cd "$ROOT/infrastructure" && npx hardhat node ) >"$SCRIPT_DIR/.hardhat-node.log" 2>&1 &
NODE_PID=$!
for i in $(seq 1 30); do
  if curl -s -X POST "$RPC" -H 'content-type: application/json' \
       --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' 2>/dev/null | grep -q '0x7a69'; then
    break
  fi
  sleep 1
  [ "$i" -eq 30 ] && die "hardhat node 30s 未就绪,见 $SCRIPT_DIR/.hardhat-node.log"
done
log "本地链就绪 (pid $NODE_PID, chainId 31337)"

# 4) 部署 infrastructure
log "部署 infrastructure..."
( cd "$ROOT/infrastructure" && npx hardhat ignition deploy ignition/modules/infrastructure.js \
    --network localhost --parameters ignition/parameters/localhost.json --reset )

# 5) 同步 infra 地址 → ScratchCard/Core 的 localhost.json
node "$SYNC" --network localhost --write --only sc,core

# 6) 部署 ScratchCardLocal + GreatLottoCoreLocal
log "部署 ScratchCardLocal..."
( cd "$ROOT/ScratchCard" && npx hardhat ignition deploy ignition/modules/ScratchCardLocal.js \
    --network localhost --parameters ignition/parameters/localhost.json --reset )
log "部署 GreatLottoCoreLocal..."
( cd "$ROOT/GreatLottoCore" && npx hardhat ignition deploy ignition/modules/GreatLottoCoreLocal.js \
    --network localhost --parameters ignition/parameters/localhost.json --reset )

# 7) 同步三仓地址 → interface address.json[31337](含 MockEntropy)
node "$SYNC" --network localhost --write --only interface

# 8) 收尾:节点保留运行(interface dev 需要)
log "完成 ✅  本地链保留运行 (pid $NODE_PID)"
log "停止本地链: kill $NODE_PID"
trap - EXIT     # 正常结束不触发拆链
```

- [ ] **Step 2: 赋可执行权限**

Run: `cd infrastructure && chmod +x scripts/deploy-local.sh`

- [ ] **Step 3: bash 语法检查**

Run: `cd infrastructure && bash -n scripts/deploy-local.sh`
Expected: 无输出(语法 OK)。

- [ ] **Step 4: Commit**

```bash
cd infrastructure
git add scripts/deploy-local.sh
git commit -m "feat(scripts): one-click local deploy orchestrator (31337)"
```

---

## Task 6: README.md —— 使用文档

**Files:**
- Create: `infrastructure/scripts/README.md`

- [ ] **Step 1: 写 README**

Create `infrastructure/scripts/README.md`:

````markdown
# scripts —— 本地一键部署 + 跨仓地址同步

设计依据见 [../doc/local-deploy-and-address-sync-design.md](../doc/local-deploy-and-address-sync-design.md)。
本目录讲**怎么用**;设计文档讲**为什么这么设计**。

| 文件 | 作用 |
|------|------|
| `deploy.config.json` | 网络注册表 + 地址映射(加链/加合约只改这里) |
| `sync-core.mjs` | 纯函数核心(单测覆盖) |
| `sync-addresses.mjs` | 地址同步 CLI |
| `deploy-local.sh` | 一键本地部署(仅 31337) |

> 路径基准:脚本以**工作区根**(`infrastructure/` 的上级、4 仓父目录)为基准访问 ScratchCard / GreatLottoCore / interface。

## 一键本地部署

前置:三仓已装依赖,且 ScratchCard / GreatLottoCore 的 `node_modules/@greatlotto/infrastructure` 软链接在位。

```bash
cd infrastructure
bash scripts/deploy-local.sh
```

它会:清三仓 `chain-31337` 旧部署 → 起 `hardhat node` → 部署 infrastructure → 同步地址到两仓 `localhost.json` → 部署 ScratchCardLocal + GreatLottoCoreLocal → 回填 `interface/src/app/launch/address.json` 的 `31337` 块(含 MockEntropy)。

跑完**本地链保留运行**(interface dev 需要);停止用结尾打印的 `kill <pid>`。失败/Ctrl-C 会自动拆掉节点。

## 单独跑地址同步(任意网络)

```bash
# dry-run(默认):只打印 diff,不写文件
node scripts/sync-addresses.mjs --network baseSepolia

# 落盘:非本地网络会先要求交互输入 yes 确认
node scripts/sync-addresses.mjs --network baseSepolia --write

# CI / 跳过确认
node scripts/sync-addresses.mjs --network baseSepolia --write --yes

# 只同步部分目的地
node scripts/sync-addresses.mjs --network localhost --write --only sc,core
node scripts/sync-addresses.mjs --network localhost --write --only interface
```

- `localhost` 网络:`--write` 直接落盘,无需确认。
- 非本地网络:`--write` 默认要交互确认(防误改含真实地址的参数文件);`--yes` 跳过。
- `--network` 接受网络名(`localhost`/`baseSepolia`/…)或 chainId(`31337`/`84532`/…)。

典型测试网流程:先 `ignition deploy` 三仓 → 再 `node scripts/sync-addresses.mjs --network <net> --write` 回填下游参数与 interface。

## 加一条链 / 加一个合约

只改 `deploy.config.json`:

- **加链**:在 `networks` 加一项(chainId / scModule / coreModule / local);确保各仓有同名 `ignition/parameters/<network>.json`。
- **加合约**:在 `mappings` 加一项(`logical` / `source` / `keys` / `targets`)。`keys` 是 `deployed_addresses.json` 里的 ignition key 数组,按序匹配(用于容忍 Test/生产合约别名)。

## 常见错误

| 现象 | 原因 / 处理 |
|------|------------|
| `缺 @greatlotto/infrastructure 软链接` | 在对应仓 `pnpm i` 或 `npm link @greatlotto/infrastructure` |
| `hardhat node 30s 未就绪` | 端口被占:`lsof -i:8545`;或看 `scripts/.hardhat-node.log` |
| 部署 ScratchCardLocal 时 `grantRole` revert | account#0 须持 GLC/DaoCoin 的 `DEFAULT_ADMIN_ROLE`(本地补授权前提) |
| 同步告警 `未解析到 <合约>` | 该仓 `chain-<id>` 未部署,或 `deploy.config.json` 的 `keys` 与 ignition key 不符 |
| 测试网误跑 `--write` | 默认会交互确认;未输入 `yes` 不会写 |

## 已知坑(非本工具范围)

- `interface address.json[31337].payToken` 硬编码主网稳定币,本地链上不存在;本地真实支付币是 `GreatLottoCoinTest`。
- interface 仅一个 `PrizePoolContractAddress`,本工具默认指向 **Core** 奖池;ScratchCard 奖池若前端需要,需先在 `address.json` 新增字段再补 mapping。
````

- [ ] **Step 2: Commit**

```bash
cd infrastructure
git add scripts/README.md
git commit -m "docs(scripts): usage README for local deploy + address sync"
```

---

## Task 7: 端到端集成验证

**Files:** 无(纯验证)

- [ ] **Step 1: 全量单测**

Run: `cd infrastructure && npm run test:scripts`
Expected: 13 tests PASS。

- [ ] **Step 2: 跑一键部署**

Run: `cd infrastructure && bash scripts/deploy-local.sh`
Expected: 三仓依次部署成功;结尾打印各步骤完成 + 节点 pid。

- [ ] **Step 3: 校验 interface 已回填**

Run:
```bash
cd /Users/tongren/Documents/github/GreatLottoGroup
node -e "const a=require('./interface/src/app/launch/address.json')['31337'].contracts; const e=require('./interface/src/app/launch/address.json')['31337'].entropy; for(const k of ['ScratchCardContractAddress','ScratchCardNFTContractAddress','GreatLottoContractAddress','PrizePoolContractAddress','GreatCoinContractAddress']) if(!a[k]) throw new Error('空: '+k); if(!e.entropyAddress) throw new Error('空 entropyAddress'); console.log('OK: interface 31337 关键地址均非空');"
```
Expected: `OK: interface 31337 关键地址均非空`。

- [ ] **Step 4: 校验幂等(再同步一次应无变更)**

Run: `cd infrastructure && node scripts/sync-addresses.mjs --network localhost --write`
Expected: 打印 `无变更,跳过写入。`

- [ ] **Step 5: 校验下游参数已更新且与 infra 部署一致**

Run:
```bash
cd /Users/tongren/Documents/github/GreatLottoGroup
node -e "const d=require('./infrastructure/ignition/deployments/chain-31337/deployed_addresses.json'); const sc=require('./ScratchCard/ignition/parameters/localhost.json').ScratchCardLocalModule; if(sc.greatLottoCoinAddress!==d['Infrastructure#GreatLottoCoinTest']) throw new Error('GLC 不一致'); console.log('OK: SC localhost.json 与 infra 部署一致');"
```
Expected: `OK: SC localhost.json 与 infra 部署一致`。

- [ ] **Step 6: 停掉本地链**

Run: `kill <上一步打印的 pid>`(或 `pkill -f "hardhat node"`)
Expected: 进程结束,无僵尸。

- [ ] **Step 7: 提交可能被同步改动的下游文件**

> 同步会改 ScratchCard / GreatLottoCore 的 `localhost.json` 与 interface `address.json`。这些属下游仓,按工作区惯例在各自仓提交。

```bash
cd /Users/tongren/Documents/github/GreatLottoGroup/ScratchCard && git add ignition/parameters/localhost.json && git commit -m "chore(local): refresh 31337 addresses via deploy-local" || true
cd /Users/tongren/Documents/github/GreatLottoGroup/GreatLottoCore && git add ignition/parameters/localhost.json && git commit -m "chore(local): refresh 31337 addresses via deploy-local" || true
cd /Users/tongren/Documents/github/GreatLottoGroup/interface && git add src/app/launch/address.json && git commit -m "chore(local): refresh 31337 addresses via deploy-local" || true
```

---

## Self-Review 记录

- **Spec 覆盖**:设计 §3(三组件+README)→ Task 1/2-3/4/5/6;§4 配置 → Task 1;§5 同步器(解析/diff/entropy 方向/写入安全)→ Task 2-4;§6 一键脚本 8 步 → Task 5;§7 错误处理 → Task 4(闸门)/Task 5(预检+trap+RPC 超时)+README 错误表;§9 验收 → Task 7。
- **entropy 方向差异**(设计 §5.4)→ `resolveEntropy` 本地/非本地分支 + Task 2 两条用例。
- **占位符**:无 TBD/TODO;所有代码步骤含完整实现。
- **类型一致**:`buildDiffs` 产出 `{scope,path,oldValue,newValue,label}` 与 `applyDiffs`/`formatDiffs` 消费字段一致;CLI 传入 `targets={scParam,core,interface}` 与核心 `byScope` 映射一致;`only` 取值 `sc|core|interface` 在 CLI(`--only sc,core`)、`buildDiffs`、写入分支三处一致。
