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
