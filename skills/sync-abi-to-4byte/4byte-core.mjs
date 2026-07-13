// 纯函数核心:无文件 IO、无网络,全部接收/返回普通对象,便于 node --test 单测。
// 与同级 deploy-local-and-sync/abi-core.mjs 同风格(dry-run 判定 / 格式化口径一致)。

export function parseArgs(argv) {
  const a = { write: false, submit: false, yes: false, only: null };
  for (let i = 0; i < argv.length; i++) {
    const t = argv[i];
    if (t === "--write") a.write = true;
    else if (t === "--submit") a.submit = true;
    else if (t === "--yes") a.yes = true;
    else if (t === "--only") {
      const v = argv[++i];
      if (v === undefined || v.startsWith("--")) throw new Error("--only 缺少值(逗号分隔文件名,如 ScratchCard.json,GreatLotto.json)");
      a.only = v.split(",").map((s) => s.trim()).filter(Boolean);
    }
    else throw new Error(`未知参数: ${t}`);
  }
  return a;
}

// 从 hardhat artifact 对象取裸 abi 数组;缺失/非数组/空数组抛错(由 CLI 兜住转成「缺失」跳过)。
export function extractAbi(artifactJson) {
  if (!artifactJson || !Array.isArray(artifactJson.abi)) throw new Error("artifact 无 .abi 数组");
  if (artifactJson.abi.length === 0) throw new Error("artifact .abi 为空");
  return artifactJson.abi;
}

// 按 abi 条目 type 计数,供报告显示(constructor/fallback/receive 不计入三类)。
export function summarizeAbi(abi) {
  const s = { functions: 0, events: 0, errors: 0 };
  for (const e of abi) {
    if (e.type === "function") s.functions++;
    else if (e.type === "event") s.events++;
    else if (e.type === "error") s.errors++;
  }
  return s;
}

// 4byte 的 /import-abi/ 校验器只认 function / event —— 含 type:"error"(或 receive/fallback)会整包
// 报 400「Could not validate ABI」。自定义 error 与 function 共用同一套 4-byte 选择器
// (keccak256(sig)[:4]),故把 error 改标为 function 即可在同一次 import-abi 里登记其选择器,
// 供浏览器反解 revert;constructor / receive / fallback 无选择器,丢弃。
export function sanitizeAbiForImport(abi) {
  const out = [];
  for (const e of abi) {
    if (e.type === "function" || e.type === "event") out.push(e);
    else if (e.type === "error") out.push({ type: "function", name: e.name, inputs: e.inputs || [], outputs: [], stateMutability: "nonpayable" });
  }
  return out;
}

// 4byte /api/v1/import-abi/ 要 contract_abi 为「ABI 数组的 JSON 字符串」。传入前应先 sanitizeAbiForImport。
export function buildPayload(abi) {
  return { contract_abi: JSON.stringify(abi) };
}

// 归一 4byte 导入响应:{num_processed,num_imported,num_duplicates,num_ignored} → 短名(缺字段补 0)。
export function parseImportResponse(json) {
  const n = (v) => (typeof v === "number" ? v : 0);
  return {
    processed: n(json?.num_processed),
    imported: n(json?.num_imported),
    duplicates: n(json?.num_duplicates),
    ignored: n(json?.num_ignored),
  };
}

// 统一格式化口径:与现有 4byte.directory/*.json 一致(2 空格 + 末尾换行)。
export function abiText(abi) {
  return JSON.stringify(abi, null, 2) + "\n";
}

export function statusOf(newText, oldText) {
  if (oldText == null) return "new";
  return oldText === newText ? "unchanged" : "changed";
}

// recordDir 下的 .json 里,既不在合约清单 name、也不是本工具生成物的 → 孤儿(历史死件,只报不删)。
export function classifyRecordDir(entryNames, contracts) {
  const mapped = new Set(contracts.map((c) => c.name));
  const orphans = entryNames.filter((e) => e.endsWith(".json") && !mapped.has(e));
  return { orphans };
}
