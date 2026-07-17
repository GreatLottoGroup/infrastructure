#!/usr/bin/env node
/**
 * NatSpec completeness gate over Foundry's compiled AST (out/).
 *
 * Why a custom checker instead of @defi-wonderland/natspec-smells:
 *   natspec-smells (1.1.6) re-compiles the sources itself WITHOUT viaIR/optimizer,
 *   so it hits stack-too-deep on this workspace's long SVG-concat libraries
 *   (NFTSVG / PositionCard) — the same reason `forge coverage` needs `--ir-minimum`.
 *   This checker instead reads forge's OWN already-viaIR-compiled AST, so it never
 *   recompiles and never breaks. Zero npm dependencies (Node stdlib only).
 *
 * Gate: every external/public function in the included sources must have EITHER
 *   `@inheritdoc` (documented via parent/interface), OR
 *   `@notice` + a `@param <name>` for each named parameter + at least one `@return`
 *   per return value. Constructors, auto-getters, mocks and libraries are excluded.
 *
 * Usage: run `forge build --ast` first, then `node tools/check-natspec.mjs`.
 * Config (optional): natspec.config.json at repo root — { include, exclude, out }.
 */
import { readFileSync, readdirSync, statSync, existsSync } from 'node:fs';
import { join, relative, isAbsolute, resolve } from 'node:path';

const REPO = process.cwd();
const cfgPath = join(REPO, 'natspec.config.json');
const cfg = existsSync(cfgPath) ? JSON.parse(readFileSync(cfgPath, 'utf8')) : {};
const includes = (cfg.include || ['contracts/']).map((p) => resolve(REPO, p) + '/');
const excludes = (cfg.exclude || ['contracts/mocks/', 'contracts/libraries/']).map((p) => resolve(REPO, p) + '/');
const OUT = resolve(REPO, cfg.out || 'out');

if (!existsSync(OUT)) {
  console.error(`natspec-check: ${relative(REPO, OUT)}/ not found — run \`forge build --ast\` first.`);
  process.exit(2);
}

function walkJson(dir, acc = []) {
  for (const e of readdirSync(dir)) {
    const p = join(dir, e);
    const s = statSync(p);
    if (s.isDirectory()) walkJson(p, acc);
    else if (e.endsWith('.json')) acc.push(p);
  }
  return acc;
}

// Collect unique source ASTs (one per source file) that fall inside the include set.
const asts = new Map();
for (const f of walkJson(OUT)) {
  let d;
  try { d = JSON.parse(readFileSync(f, 'utf8')); } catch { continue; }
  const ast = d.ast;
  if (!ast || !ast.absolutePath) continue;
  const ap = isAbsolute(ast.absolutePath) ? ast.absolutePath : resolve(REPO, ast.absolutePath);
  if (!includes.some((i) => ap.startsWith(i))) continue;
  if (excludes.some((x) => ap.startsWith(x))) continue;
  asts.set(ap, ast);
}

// Defensive: `forge build --ast` is INCREMENTAL — with a warm cache it may emit AST for
// only the files it recompiled, which would make this checker silently under-check and
// pass. Compare AST coverage against the source .sol files on disk; if short, the build
// is stale — bail with a distinct exit code so the caller re-runs `forge build --ast --force`.
function walkSol(dir, acc = []) {
  if (!existsSync(dir)) return acc;
  for (const e of readdirSync(dir)) {
    const p = join(dir, e);
    statSync(p).isDirectory() ? walkSol(p, acc) : (e.endsWith('.sol') && acc.push(p));
  }
  return acc;
}
const srcFiles = includes
  .flatMap((i) => walkSol(i))
  .filter((p) => !excludes.some((x) => p.startsWith(x)));
if (asts.size < srcFiles.length) {
  console.error(
    `natspec-check: AST covers only ${asts.size}/${srcFiles.length} source files — stale/incomplete build. ` +
    `Run \`forge build --ast --force\` first (a warm cache makes \`forge build --ast\` skip files).`
  );
  process.exit(2);
}

const violations = [];
function checkContract(c, path) {
  for (const n of c.nodes || []) {
    if (n.nodeType !== 'FunctionDefinition') continue;
    if (n.kind === 'constructor') continue;
    if (!['external', 'public'].includes(n.visibility)) continue;
    const doc = (n.documentation && n.documentation.text) || '';
    if (doc.includes('@inheritdoc')) continue; // documented via parent/interface
    const name = n.name || n.kind;
    const miss = [];
    if (!/@notice\b/.test(doc)) miss.push('@notice');
    for (const p of n.parameters.parameters) {
      if (p.name && !new RegExp('@param\\s+' + p.name + '\\b').test(doc)) miss.push('@param ' + p.name);
    }
    const nRet = n.returnParameters.parameters.length;
    const retTags = (doc.match(/@return\b/g) || []).length;
    if (nRet > 0 && retTags < nRet) miss.push(`@return x${nRet} (found ${retTags})`);
    if (miss.length) violations.push({ file: relative(REPO, path), contract: c.name, fn: name, miss });
  }
}
for (const [path, ast] of [...asts].sort()) {
  for (const node of ast.nodes || []) {
    if (node.nodeType === 'ContractDefinition') checkContract(node, path);
  }
}

if (!violations.length) {
  console.log(`natspec-check: OK — all external/public functions documented across ${asts.size} source file(s).`);
  process.exit(0);
}

const byFile = {};
for (const v of violations) (byFile[v.file] ||= []).push(v);
console.error(`natspec-check: ${violations.length} undocumented external/public function(s):\n`);
for (const f of Object.keys(byFile).sort()) {
  console.error(f + ':');
  for (const v of byFile[f]) console.error(`  ${v.contract}.${v.fn} — missing ${v.miss.join(', ')}`);
  console.error('');
}
process.exit(1);
