import { test } from "node:test";
import assert from "node:assert/strict";
import {
  parseArgs, resolveNetwork, isEmptyAddr,
  resolveContractAddresses, resolveEntropy,
  buildDiffs, applyDiffs, formatDiffs, getPath,
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
