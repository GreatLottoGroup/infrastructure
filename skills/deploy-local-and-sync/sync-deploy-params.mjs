#!/usr/bin/env node
// 专用 CLI:infra 部署后,把 infra 的三个地址(GreatLottoCoin/SalesVault/SalesChannel)回填到
// ScratchCard / GreatLottoCore 的 ignition/parameters/<net>.json,为部署这两仓准备入参。
// 与 sync-addresses.mjs 的区别:本脚本只读 infra 部署产物、只写 sc/core 两个参数文件,永不触碰 interface。
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { createInterface } from "node:readline/promises";
import {
  parseArgs, resolveNetwork, filterMappingsBySource,
  resolveContractAddresses, buildDiffs, applyDiffs, formatDiffs,
} from "./sync-core.mjs";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const ROOT = join(SCRIPT_DIR, "..", "..", "..");    // infrastructure/skills/deploy-local-and-sync → 工作区根
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

  // 只关心 infra 来源的映射(三条:GreatLottoCoin/SalesVault/SalesChannel)
  const cfg = filterMappingsBySource(CONFIG, "infrastructure");

  // 1) 只读 infra 部署产物
  const deployedByRepo = {
    infrastructure: readJson(deployedPath(r.infrastructure, net.chainId)) || {},
  };

  // 2) 读目的地:sc / core 参数文件
  const scParamFile = paramPath(r.scratchcard, net.name);
  const coreParamFile = paramPath(r.core, net.name);
  const scParam = readJson(scParamFile) || {};
  const coreParam = readJson(coreParamFile) || {};

  // 3) 解析地址(无 entropy、无 interface)
  const { resolved, warnings } = resolveContractAddresses(cfg, net, deployedByRepo);

  // 4) 计算 diff:仅 sc + core
  const targets = { scParam, core: coreParam };
  const diffs = buildDiffs({
    config: cfg, network: net, resolved,
    entropy: null, targets, only: ["sc", "core"],
  });

  // 5) 打印
  console.log(`\n[deploy-params] 网络 ${net.name}(chainId ${net.chainId}, local=${net.local})`);
  if (warnings.length) console.log("⚠️  " + warnings.join("\n⚠️  "));
  console.log("变更:\n" + formatDiffs(diffs));

  if (!args.write) { console.log("\n(dry-run,未写。加 --write 落盘)"); return; }
  if (!diffs.length) { console.log("\n无变更,跳过写入。"); return; }

  // 6) 写入闸门(非本地网络需确认)
  if (!net.local && !args.yes) {
    if (!(await confirm(`\n⚠️ 非本地网络 ${net.name},确认写入以上变更?输入 yes: `))) {
      console.log("已取消。"); return;
    }
  }
  applyDiffs(targets, diffs);
  const scopes = new Set(diffs.map((d) => d.scope));
  if (scopes.has("sc")) writeJson(scParamFile, scParam);
  if (scopes.has("core")) writeJson(coreParamFile, coreParam);
  console.log("\n✅ 已写入。");
}

main().catch((e) => { console.error("❌ " + e.message); process.exit(1); });
