#!/usr/bin/env node
// CLI 外壳:定位工作区根 → 读三仓 artifact.abi → 计数 + 比对本地快照 → 打印计划。
//   默认 dry-run(纯离线);--write 仅刷新本地 4byte.directory 快照;
//   --submit POST 到 4byte(对外不可逆,需交互确认或 --yes),并隐含刷新快照。
import { readFileSync, writeFileSync, existsSync, readdirSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import { createInterface } from "node:readline/promises";
import {
  parseArgs, extractAbi, summarizeAbi, sanitizeAbiForImport, buildPayload,
  parseImportResponse, abiText, statusOf, classifyRecordDir,
} from "./4byte-core.mjs";

const SCRIPT_DIR = dirname(fileURLToPath(import.meta.url));
const ROOT = join(SCRIPT_DIR, "..", "..", "..");    // infrastructure/skills/sync-abi-to-4byte → 工作区根
const CFG = JSON.parse(readFileSync(join(SCRIPT_DIR, "4byte.config.json"), "utf8"));

function readJson(p) {
  return existsSync(p) ? JSON.parse(readFileSync(p, "utf8")) : null;
}
function artifactPath(repoDir, artifactRel) {
  return join(ROOT, repoDir, "artifacts", `${artifactRel}.json`);
}
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

const LABEL = {
  new:       "🆕 新建    ",
  changed:   "✏️  变更    ",
  unchanged: "   无变化  ",
  missing:   "⚠️  缺失    ",
};

async function confirm(question) {
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  try {
    const ans = (await rl.question(question)).trim().toLowerCase();
    return ans === "yes" || ans === "y";
  } finally {
    rl.close();
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const repos = CFG.repos;
  const recordDir = join(ROOT, CFG.recordDir);

  let contracts = CFG.contracts;
  if (args.only) {
    const want = new Set(args.only);
    contracts = contracts.filter((c) => want.has(c.name));
    const missingNames = args.only.filter((n) => !CFG.contracts.some((c) => c.name === n));
    for (const n of missingNames) console.log(`  ⚠️  --only 无此合约(config 未列):${n}`);
  }

  // 1) 逐合约解析 artifact → 取 .abi → 计数 → 比对本地快照
  const rows = [];
  for (const c of contracts) {
    const artPath = artifactPath(repos[c.source], c.artifact);
    const art = readJson(artPath);
    let abi;
    try {
      abi = extractAbi(art);
    } catch {
      rows.push({ name: c.name, status: "missing", artPath });
      continue;
    }
    // 快照与提交同源:都用净化后的 ABI(error 改标为 function、丢弃 constructor/receive/fallback),
    // 与实际提交给 4byte 的内容逐字节一致。summary 仍按原始 ABI 展示 fn/ev/err 构成(信息更全)。
    const importAbi = sanitizeAbiForImport(abi);
    const newText = abiText(importAbi);
    const outPath = join(recordDir, c.name);
    const oldText = existsSync(outPath) ? readFileSync(outPath, "utf8") : null;
    rows.push({
      name: c.name, status: statusOf(newText, oldText),
      outPath, newText, importAbi, summary: summarizeAbi(abi),
    });
  }

  // 2) 孤儿扫描(本地快照目录里的历史死件)
  const entries = existsSync(recordDir) ? readdirSync(recordDir) : [];
  const { orphans } = classifyRecordDir(entries, CFG.contracts);

  // 3) 打印计划
  const mode = args.submit ? "SUBMIT" : args.write ? "WRITE" : "DRY-RUN";
  console.log(`\n[4byte] ${mode} → ${CFG.endpoint}`);
  console.log(`        本地快照 ${CFG.recordDir}`);
  for (const r of rows) {
    const detail = r.status === "missing"
      ? `   (${r.artPath} — 去对应仓 npx hardhat compile)`
      : `   fn=${r.summary.functions} ev=${r.summary.events} err=${r.summary.errors}`;
    console.log(`  ${LABEL[r.status]} ${r.name}${detail}`);
  }
  for (const o of orphans) console.log(`  ⚠️  孤儿     ${o}   (历史死件,只报不删)`);

  const ready = rows.filter((r) => r.status !== "missing");

  // 4) 纯 dry-run
  if (!args.submit && !args.write) {
    console.log("\n(dry-run,未联网未写盘。--write 刷新本地快照;--submit 提交到 4byte)");
    return;
  }

  if (!ready.length) { console.log("\n无可处理合约(全部缺失 artifact)。"); process.exit(1); }

  // 5) --submit:POST 到公共库(对外不可逆),需确认
  let submitFailures = 0;
  if (args.submit) {
    if (!args.yes) {
      const ok = await confirm(`\n将向公共库 4byte.directory 提交 ${ready.length} 个合约的函数/事件签名(不可撤销)。输入 yes 继续:`);
      if (!ok) { console.log("已取消。"); return; }
    }
    console.log("");
    for (const r of ready) {
      try {
        const res = await fetch(CFG.endpoint, {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify(buildPayload(r.importAbi)),
        });
        if (!res.ok) {
          submitFailures++;
          console.log(`  ❌ ${r.name}   HTTP ${res.status} ${res.statusText}`);
        } else {
          const c = parseImportResponse(await res.json());
          console.log(`  ✅ ${r.name}   imported=${c.imported} duplicates=${c.duplicates} ignored=${c.ignored} (processed=${c.processed})`);
        }
      } catch (e) {
        submitFailures++;
        console.log(`  ❌ ${r.name}   ${e.message}`);
      }
      await sleep(300);   // 礼貌限速
    }
  }

  // 6) 刷新本地快照(--write,或 --submit 隐含):只写 new/changed
  if (args.write || args.submit) {
    const toWrite = ready.filter((r) => r.status === "new" || r.status === "changed");
    if (toWrite.length) {
      if (!existsSync(recordDir)) mkdirSync(recordDir, { recursive: true });
      for (const r of toWrite) writeFileSync(r.outPath, r.newText);
      console.log(`\n✅ 本地快照已刷新 ${toWrite.length} 个文件。`);
    } else {
      console.log("\n本地快照无变更,跳过写入。");
    }
  }

  if (submitFailures) { console.error(`\n❌ ${submitFailures} 个合约提交失败。`); process.exit(1); }
}

main().catch((e) => { console.error("❌ " + e.message); process.exit(1); });
