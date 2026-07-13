import { test } from "node:test";
import assert from "node:assert/strict";
import {
  parseArgs, extractAbi, summarizeAbi, sanitizeAbiForImport, buildPayload,
  parseImportResponse, abiText, statusOf, classifyRecordDir,
} from "../4byte-core.mjs";

test("parseArgs 默认全 false / null", () => {
  assert.deepEqual(parseArgs([]), { write: false, submit: false, yes: false, only: null });
});

test("parseArgs 识别 flags", () => {
  const a = parseArgs(["--write", "--submit", "--yes"]);
  assert.equal(a.write, true);
  assert.equal(a.submit, true);
  assert.equal(a.yes, true);
});

test("parseArgs --only 逗号拆分并 trim", () => {
  const a = parseArgs(["--only", "A.json, B.json ,C.json"]);
  assert.deepEqual(a.only, ["A.json", "B.json", "C.json"]);
});

test("parseArgs --only 缺值抛错", () => {
  assert.throws(() => parseArgs(["--only"]), /--only 缺少值/);
  assert.throws(() => parseArgs(["--only", "--write"]), /--only 缺少值/);
});

test("parseArgs 未知参数抛错", () => {
  assert.throws(() => parseArgs(["--nope"]), /未知参数/);
});

test("extractAbi 正常返回 abi 数组", () => {
  const abi = [{ type: "function", name: "f" }];
  assert.deepEqual(extractAbi({ abi }), abi);
});

test("extractAbi 缺 abi / 非数组 / 空数组抛错", () => {
  assert.throws(() => extractAbi(null), /无 .abi 数组/);
  assert.throws(() => extractAbi({}), /无 .abi 数组/);
  assert.throws(() => extractAbi({ abi: "x" }), /无 .abi 数组/);
  assert.throws(() => extractAbi({ abi: [] }), /为空/);
});

test("summarizeAbi 按 type 计数(constructor 等不计)", () => {
  const abi = [
    { type: "constructor" },
    { type: "function", name: "a" },
    { type: "function", name: "b" },
    { type: "event", name: "E" },
    { type: "error", name: "Err" },
    { type: "receive" },
  ];
  assert.deepEqual(summarizeAbi(abi), { functions: 2, events: 1, errors: 1 });
});

test("sanitizeAbiForImport 保留 function/event、error 改标为 function、丢弃 constructor/receive/fallback", () => {
  const abi = [
    { type: "constructor", inputs: [] },
    { type: "function", name: "f", inputs: [{ type: "uint256" }] },
    { type: "event", name: "E", inputs: [] },
    { type: "error", name: "Err", inputs: [{ type: "address" }] },
    { type: "receive" },
    { type: "fallback" },
    { type: "error", name: "NoArgErr" },   // inputs 缺失 → 补 []
  ];
  const out = sanitizeAbiForImport(abi);
  assert.deepEqual(out, [
    { type: "function", name: "f", inputs: [{ type: "uint256" }] },
    { type: "event", name: "E", inputs: [] },
    { type: "function", name: "Err", inputs: [{ type: "address" }], outputs: [], stateMutability: "nonpayable" },
    { type: "function", name: "NoArgErr", inputs: [], outputs: [], stateMutability: "nonpayable" },
  ]);
});

test("buildPayload 产出 contract_abi 为字符串", () => {
  const abi = [{ type: "function", name: "f" }];
  const p = buildPayload(abi);
  assert.equal(typeof p.contract_abi, "string");
  assert.deepEqual(JSON.parse(p.contract_abi), abi);
});

test("parseImportResponse 字段归一 + 缺字段补 0", () => {
  assert.deepEqual(
    parseImportResponse({ num_processed: 4, num_imported: 2, num_duplicates: 1, num_ignored: 1 }),
    { processed: 4, imported: 2, duplicates: 1, ignored: 1 },
  );
  assert.deepEqual(parseImportResponse({}), { processed: 0, imported: 0, duplicates: 0, ignored: 0 });
  assert.deepEqual(parseImportResponse(null), { processed: 0, imported: 0, duplicates: 0, ignored: 0 });
});

test("abiText 2 空格缩进 + 末尾换行", () => {
  const t = abiText([{ type: "function" }]);
  assert.ok(t.endsWith("}\n]\n"));
  assert.ok(t.includes('\n  {'));
});

test("statusOf new / changed / unchanged", () => {
  assert.equal(statusOf("x", null), "new");
  assert.equal(statusOf("x", "x"), "unchanged");
  assert.equal(statusOf("x", "y"), "changed");
});

test("classifyRecordDir 识别孤儿(死件),忽略非 .json", () => {
  const contracts = [{ name: "ScratchCard.json" }, { name: "GreatLotto.json" }];
  const entries = ["ScratchCard.json", "GreatLotto.json", "Callable.json", "GreatLottoEth.json", "README.md"];
  assert.deepEqual(classifyRecordDir(entries, contracts).orphans, ["Callable.json", "GreatLottoEth.json"]);
});
