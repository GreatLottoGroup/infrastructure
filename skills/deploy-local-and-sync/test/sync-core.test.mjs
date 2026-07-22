import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";
import {
  parseArgs, resolveNetwork, isEmptyAddr,
  resolveContractAddresses, resolveEntropy,
  buildDiffs, applyDiffs, formatDiffs, getPath,
  filterMappingsBySource,
} from "../sync-core.mjs";

const REAL_CONFIG = JSON.parse(
  readFileSync(join(dirname(fileURLToPath(import.meta.url)), "..", "deploy.config.json"), "utf8"),
);

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
  assert.ok(labels.some((l) => l.includes("greatLottoCoinAddress")));
  assert.ok(!labels.some((l) => l.includes("GreatCoinContractAddress")));
  assert.ok(labels.some((l) => l.includes("ScratchCardContractAddress")));
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

test("filterMappingsBySource: 只保留指定 source 的映射", () => {
  const cfg = filterMappingsBySource(CONFIG, "infrastructure");
  assert.ok(cfg.mappings.length >= 1);
  assert.ok(cfg.mappings.every((m) => m.source === "infrastructure"));
  assert.ok(cfg.mappings.some((m) => m.logical === "GreatLottoCoin"));
  assert.ok(!cfg.mappings.some((m) => m.logical === "ScratchCard"));
  // 浅拷贝:原 config 不受影响
  assert.ok(CONFIG.mappings.some((m) => m.source === "scratchcard"));
});

// sync-deploy-params.mjs 的核心组合:infra-only config + only sc,core + entropy=null。
// 用真实 deploy.config.json,确认只写 sc/core 参数、不碰 interface、下游未部署也不产出无关告警。
test("deploy-params 组合:infra-only 只产出 sc/core diff,无 interface,无下游告警", () => {
  const cfg = filterMappingsBySource(REAL_CONFIG, "infrastructure");
  const net = resolveNetwork(REAL_CONFIG, "localhost");
  const deployedByRepo = {
    infrastructure: {
      "Infrastructure#GreatLottoCoinTest": "0xCoin",
      "Infrastructure#SalesVault": "0xVault",
      "Infrastructure#SalesChannel": "0xChan",
    },
  };
  const { resolved, warnings } = resolveContractAddresses(cfg, net, deployedByRepo);
  // 三个 infra 合约全解析,且没有 ScratchCard/GreatLotto 之类下游告警
  assert.equal(resolved.GreatLottoCoin, "0xCoin");
  assert.equal(resolved.SalesVault, "0xVault");
  assert.equal(resolved.SalesChannel, "0xChan");
  assert.equal(warnings.length, 0);

  const targets = {
    scParam: { [net.scModule]: {} },
    core: { [net.coreModule]: {} },
  };
  const diffs = buildDiffs({
    config: cfg, network: net, resolved, entropy: null, targets, only: ["sc", "core"],
  });
  assert.ok(diffs.length > 0);
  assert.ok(diffs.every((d) => d.scope === "sc" || d.scope === "core"));
  assert.ok(diffs.some((d) => d.scope === "sc"));
  assert.ok(diffs.some((d) => d.scope === "core"));
  assert.ok(!diffs.some((d) => d.label.includes("interface")));
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

// 回归:刮刮卡奖池与彩票奖池是两个独立合约,各有独立 interface key,绝不能共用一个 mapping。
// 曾经缺失 ScratchCardPrizePool mapping → sync 从不写 ScratchCardPrizePoolContractAddress,
// 前端只能靠 `|| PrizePoolContractAddress` 兜底到彩票池(静默打错合约)。
test("deploy.config: 刮刮卡奖池与彩票奖池各有独立 mapping,来源/目标互不相同", () => {
  const scPool = REAL_CONFIG.mappings.find(
    (m) => m.targets?.interface === "contracts.ScratchCardPrizePoolContractAddress",
  );
  const corePool = REAL_CONFIG.mappings.find(
    (m) => m.targets?.interface === "contracts.PrizePoolContractAddress",
  );
  assert.ok(scPool, "缺少 ScratchCardPrizePool → contracts.ScratchCardPrizePoolContractAddress 映射");
  assert.ok(corePool, "缺少 CorePrizePool → contracts.PrizePoolContractAddress 映射");
  assert.equal(scPool.source, "scratchcard");
  assert.equal(corePool.source, "core");
  assert.notEqual(scPool.logical, corePool.logical);
  // 刮刮卡奖池必须从 ScratchCard 部署产物取,不能借用彩票奖池 key
  assert.ok(scPool.keys.every((k) => k.includes("#PrizePool")));
  assert.ok(scPool.keys.some((k) => k.startsWith("ScratchCard")));
});
