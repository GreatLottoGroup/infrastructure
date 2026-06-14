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
