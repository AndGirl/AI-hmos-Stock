#!/usr/bin/env node
/**
 * 深色 token 完整性门禁（G2-03 / M12-2 / M12-4）。
 * 规则：
 *   D-01 base 与 dark 的 color 键集合完全一致（commons/ui 与 products/entry 各自成对）；
 *   D-02 TokenRegistry 引用的每个 app.color.* 都必须同时存在于 base 与 dark；
 *   D-03 .ets 源码不得出现颜色字面量（#RGB/#RRGGBB/#AARRGGBB），也不得用 Color.White 等系统色做业务语义；
 *        注释先剔除，避免把 TokenRegistry 的说明注释误判为字面量。
 * 退出码：0 通过，1 失败。
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const PAIRS = [
  {
    label: 'commons/ui',
    base: 'commons/ui/src/main/resources/base/element/color.json',
    dark: 'commons/ui/src/main/resources/dark/element/color.json'
  },
  {
    label: 'products/entry',
    base: 'products/entry/src/main/resources/base/element/color.json',
    dark: 'products/entry/src/main/resources/dark/element/color.json'
  }
];
const TOKEN_REGISTRY = 'commons/ui/src/main/ets/theme/TokenRegistry.ets';
const SKIP_DIRS = new Set(['build', 'oh_modules', 'node_modules', '.test', '.hvigor', '.idea', '.git']);
const HEX_LITERAL = /#[0-9A-Fa-f]{3,8}\b/g;
const SYSTEM_COLOR = /\bColor\.(White|Black|Red|Green|Blue|Gray|Grey|Orange|Yellow|Pink|Purple|Brown|Cyan|Magenta)\b/g;

const problems = [];

function rel(file) {
  return path.relative(ROOT, file).replace(/\\/g, '/');
}

function readColors(file) {
  if (!fs.existsSync(file)) {
    problems.push(`D-01 缺少文件：${rel(file)}`);
    return null;
  }
  const json = JSON.parse(fs.readFileSync(file, 'utf8'));
  const map = new Map();
  for (const item of json.color || []) {
    map.set(item.name, String(item.value).toUpperCase());
  }
  return map;
}

function comparePair(pair) {
  const baseFile = path.join(ROOT, pair.base);
  const darkFile = path.join(ROOT, pair.dark);
  const base = readColors(baseFile);
  const dark = readColors(darkFile);
  if (base === null || dark === null) {
    return;
  }
  for (const key of base.keys()) {
    if (!dark.has(key)) {
      problems.push(`D-01 ${pair.label}：dark 缺少键 ${key}`);
    }
  }
  for (const key of dark.keys()) {
    if (!base.has(key)) {
      problems.push(`D-01 ${pair.label}：dark 多出键 ${key}（base 不存在）`);
    }
  }
  console.log(`  ${pair.label}: base ${base.size} 键 / dark ${dark.size} 键`);
}

function checkTokenRegistry() {
  const file = path.join(ROOT, TOKEN_REGISTRY);
  if (!fs.existsSync(file)) {
    problems.push(`D-02 缺少文件：${TOKEN_REGISTRY}`);
    return;
  }
  const text = fs.readFileSync(file, 'utf8');
  const refs = [...text.matchAll(/app\.color\.([a-zA-Z0-9_]+)/g)].map((m) => m[1]);
  const uiBase = readColors(path.join(ROOT, PAIRS[0].base));
  const uiDark = readColors(path.join(ROOT, PAIRS[0].dark));
  if (uiBase === null || uiDark === null) {
    return;
  }
  for (const key of new Set(refs)) {
    if (!uiBase.has(key)) {
      problems.push(`D-02 TokenRegistry 引用 ${key}，但 base 未定义`);
    }
    if (!uiDark.has(key)) {
      problems.push(`D-02 TokenRegistry 引用 ${key}，但 dark 未定义`);
    }
  }
  console.log(`  TokenRegistry 引用 ${new Set(refs).size} 个颜色 token`);
}

function walkSources(dir, out) {
  if (!fs.existsSync(dir)) {
    return;
  }
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (SKIP_DIRS.has(entry.name)) {
      continue;
    }
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walkSources(full, out);
    } else if (entry.isFile() && entry.name.endsWith('.ets')) {
      out.push(full);
    }
  }
}

function stripComments(text) {
  return text.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '');
}

function checkLiterals() {
  const files = [];
  for (const layer of ['commons', 'features', 'products']) {
    walkSources(path.join(ROOT, layer), files);
  }
  let scanned = 0;
  for (const file of files) {
    scanned++;
    const code = stripComments(fs.readFileSync(file, 'utf8'));
    for (const match of code.matchAll(HEX_LITERAL)) {
      problems.push(`D-03 颜色字面量 ${match[0]}：${rel(file)}`);
    }
    for (const match of code.matchAll(SYSTEM_COLOR)) {
      problems.push(`D-03 系统色 ${match[0]}：${rel(file)}`);
    }
  }
  console.log(`  扫描 .ets 源码 ${scanned} 个文件`);
}

console.log('深色 token 门禁（D-01~D-03）');
for (const pair of PAIRS) {
  comparePair(pair);
}
checkTokenRegistry();
checkLiterals();

if (problems.length > 0) {
  console.error('\nFAIL：深色 token 门禁失败：');
  for (const problem of problems) {
    console.error(`  - ${problem}`);
  }
  process.exit(1);
}
console.log('\nPASS：base/dark 键集合一致、TokenRegistry 全量可解析、.ets 无颜色字面量。');
