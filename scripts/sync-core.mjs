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
