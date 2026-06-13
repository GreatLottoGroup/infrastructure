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
