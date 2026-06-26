// 纯函数核心:无文件 IO,全部接收/返回普通对象,便于单测。

export function parseArgs(argv) {
  const a = { network: "localhost", write: false };
  for (let i = 0; i < argv.length; i++) {
    const t = argv[i];
    if (t === "--network") {
      const v = argv[++i];
      if (v === undefined || v.startsWith("--")) throw new Error("--network 缺少值");
      a.network = v;
    }
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
