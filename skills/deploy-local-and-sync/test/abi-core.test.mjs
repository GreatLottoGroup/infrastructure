import { test } from "node:test";
import assert from "node:assert/strict";
import {
  parseArgs, resolveArtifactRel, classifyDir, abiText, statusOf,
} from "../abi-core.mjs";

test("parseArgs: network 默认 localhost,--write/--network 解析", () => {
  assert.deepEqual(parseArgs([]), { network: "localhost", write: false });
  const a = parseArgs(["--network", "base", "--write"]);
  assert.equal(a.network, "base");
  assert.equal(a.write, true);
});

test("parseArgs: 未知参数抛错", () => {
  assert.throws(() => parseArgs(["--nope"]), /未知参数/);
});

test("parseArgs: --network 缺值抛错", () => {
  assert.throws(() => parseArgs(["--network"]), /--network 缺少值/);
  assert.throws(() => parseArgs(["--network", "--write"]), /--network 缺少值/);
});

test("resolveArtifactRel: 无 variants 返回 artifact", () => {
  const m = { file: "ScratchCard.json", artifact: "contracts/ScratchCard.sol/ScratchCard" };
  assert.equal(resolveArtifactRel(m, { local: true }), "contracts/ScratchCard.sol/ScratchCard");
});

test("resolveArtifactRel: variants 按 network.local 选", () => {
  const m = { file: "GreatLottoCoin.json",
    variants: { local: "contracts/test/GreatLottoCoinTest.sol/GreatLottoCoinTest",
                remote: "contracts/GreatLottoCoin.sol/GreatLottoCoin" } };
  assert.equal(resolveArtifactRel(m, { local: true }),  "contracts/test/GreatLottoCoinTest.sol/GreatLottoCoinTest");
  assert.equal(resolveArtifactRel(m, { local: false }), "contracts/GreatLottoCoin.sol/GreatLottoCoin");
});

test("classifyDir: 既非映射、又非 external 的为孤儿", () => {
  const mappings = [{ file: "ScratchCard.json" }, { file: "GreatLotto.json" }];
  const external = ["usdt_abi.json", "4byte.directory"];
  const entries = ["ScratchCard.json", "GreatLotto.json", "usdt_abi.json", "4byte.directory", "Callable.json", "ExecutorReward.json"];
  const { orphans } = classifyDir(entries, mappings, external);
  assert.deepEqual(orphans, ["Callable.json", "ExecutorReward.json"]);
});

test("abiText: 2 空格缩进 + 末尾换行", () => {
  assert.equal(abiText([{ a: 1 }]), '[\n  {\n    "a": 1\n  }\n]\n');
});

test("statusOf: new/unchanged/changed", () => {
  assert.equal(statusOf("X\n", null), "new");
  assert.equal(statusOf("X\n", "X\n"), "unchanged");
  assert.equal(statusOf("X\n", "Y\n"), "changed");
});
