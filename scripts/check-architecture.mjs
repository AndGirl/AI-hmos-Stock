#!/usr/bin/env node
/**
 * 分层架构红线门禁（设计 §3.1.10 / §6.6，R-01~R-09）。
 * 扫描各模块 .ets/.ts 的 import 与源码关键字，静态判定：
 *   R-01 products 之间不得横向 import
 *   R-02 features 不得 import products
 *   R-03 commons 不得 import features/products
 *   R-04 features 横向只允许 watchlist→detail、detail→trade、pk→detail
 *   R-05 除 commons/data/DataServices.ets 外禁止 new Mock* 与 new Real*
 *   R-06 跨模块只允许包名桶导入；禁止深路径/跨模块相对路径；HAR 必须有模块根 Index.ets
 *   R-07 feature 的 view/ 不得 import repository/ 或 commons_data
 *   R-08 feature 的 viewmodel/ 不得 import view/，不得出现 promptAction/AlertDialog/bindSheet
 *   R-09 模块依赖图不得有环
 * 退出码：0 通过，1 失败。
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const LAYERS = ['products', 'features', 'commons'];
const ALLOWED_FEATURE_EDGES = new Set(['watchlist->detail', 'detail->trade', 'pk->detail']);
const RULE_IDS = ['R-01', 'R-02', 'R-03', 'R-04', 'R-05', 'R-06', 'R-07', 'R-08', 'R-09'];

const norm = (value) => value.replace(/\\/g, '/');
const relToRoot = (file) => norm(path.relative(ROOT, file));

function readJson5Loose(file) {
  const text = fs.readFileSync(file, 'utf8');
  try {
    return JSON.parse(text);
  } catch {
    const name = text.match(/"name"\s*:\s*"([^"]+)"/);
    const main = text.match(/"main"\s*:\s*"([^"]*)"/);
    return { name: name ? name[1] : '', main: main ? main[1] : '' };
  }
}

function walkSources(dir, out) {
  if (!fs.existsSync(dir)) {
    return;
  }
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === 'build' || entry.name === 'oh_modules' || entry.name === 'node_modules') {
      continue;
    }
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walkSources(full, out);
    } else if (entry.isFile() && (entry.name.endsWith('.ets') || entry.name.endsWith('.ts'))) {
      out.push(full);
    }
  }
}

function isInside(child, parent) {
  const rel = path.relative(parent, child);
  return rel === '' || (!rel.startsWith('..') && !path.isAbsolute(rel));
}

function hasSegment(target, segment) {
  return norm(target).split('/').includes(segment);
}

function lineAt(content, index) {
  return content.slice(0, index).split('\n').length;
}

function extractImports(content) {
  const imports = [];
  const fromRe = /^\s*import\s+(?:type\s+)?[^;]*?\bfrom\s+['"]([^'"]+)['"]/gm;
  let match;
  while ((match = fromRe.exec(content)) !== null) {
    imports.push({ spec: match[1], line: lineAt(content, match.index) });
  }
  const sideRe = /^\s*import\s+['"]([^'"]+)['"]/gm;
  while ((match = sideRe.exec(content)) !== null) {
    imports.push({ spec: match[1], line: lineAt(content, match.index) });
  }
  return imports;
}

function resolveRelative(fromFile, spec) {
  const base = path.resolve(path.dirname(fromFile), spec);
  const candidates = [
    base,
    `${base}.ets`,
    `${base}.ts`,
    path.join(base, 'Index.ets'),
    path.join(base, 'index.ets')
  ];
  for (const candidate of candidates) {
    if (fs.existsSync(candidate) && fs.statSync(candidate).isFile()) {
      return candidate;
    }
  }
  return base;
}

// ---------- 模块发现 ----------
const modules = [];
for (const layer of LAYERS) {
  const layerDir = path.join(ROOT, layer);
  if (!fs.existsSync(layerDir)) {
    continue;
  }
  for (const entry of fs.readdirSync(layerDir, { withFileTypes: true })) {
    if (!entry.isDirectory()) {
      continue;
    }
    const dir = path.join(layerDir, entry.name);
    const pkgFile = path.join(dir, 'oh-package.json5');
    if (!fs.existsSync(pkgFile)) {
      continue;
    }
    const pkg = readJson5Loose(pkgFile);
    modules.push({
      name: pkg.name || entry.name,
      main: pkg.main || '',
      layer,
      dir,
      rel: norm(path.relative(ROOT, dir)),
      pkgFile
    });
  }
}

const modulesByName = new Map(modules.map((item) => [item.name, item]));
const modulesByPrefix = [...modules].sort((a, b) => b.name.length - a.name.length);

function moduleOf(file) {
  return modules.find((item) => isInside(file, item.dir));
}

function findPackage(spec) {
  for (const item of modulesByPrefix) {
    if (spec === item.name || spec.startsWith(`${item.name}/`)) {
      return item;
    }
  }
  return null;
}

// ---------- 违规收集 ----------
const violations = [];
function add(rule, file, line, message) {
  violations.push({ rule, file: typeof file === 'string' ? file : '', line: line || 0, message });
}

// R-06：HAR 根 Index.ets + oh-package main
for (const item of modules) {
  if (item.layer === 'products') {
    continue;
  }
  if (!fs.existsSync(path.join(item.dir, 'Index.ets'))) {
    add('R-06', `${item.rel}/Index.ets`, 1, 'HAR 缺少模块根 Index.ets（唯一桶导出）');
  }
  if (item.main !== 'Index.ets') {
    add('R-06', `${item.rel}/oh-package.json5`, 1, `oh-package main 必须为 Index.ets，实际为 "${item.main}"`);
  }
}

// ---------- 扫描源码 ----------
const files = [];
for (const item of modules) {
  walkSources(path.join(item.dir, 'src'), files);
}

const edges = new Map(modules.map((item) => [item.name, new Set()]));

for (const file of files) {
  const from = moduleOf(file);
  if (from === null) {
    continue;
  }
  const content = fs.readFileSync(file, 'utf8');
  const moduleRelative = path.relative(from.dir, file);

  // R-05：唯一允许 new Provider 的地方
  const isDataServices = norm(file).endsWith('commons/data/src/main/ets/DataServices.ets');
  if (!isDataServices) {
    const providerPattern = /\bnew\s+(Mock|Real)[A-Za-z0-9_]*/g;
    let match;
    while ((match = providerPattern.exec(content)) !== null) {
      add('R-05', relToRoot(file), lineAt(content, match.index),
        `禁止在此处 new Provider（${match[0]}），统一放 commons/data/DataServices.ets`);
    }
  }

  // R-08：viewmodel 中的 UI 副作用
  if (from.layer === 'features' && hasSegment(moduleRelative, 'viewmodel')) {
    for (const token of ['promptAction', 'AlertDialog', 'bindSheet']) {
      const index = content.indexOf(token);
      if (index >= 0) {
        add('R-08', relToRoot(file), lineAt(content, index),
          `viewmodel 不得出现 ${token}（UI 副作用应回 view）`);
      }
    }
  }

  for (const imported of extractImports(content)) {
    const spec = imported.spec;
    if (spec.startsWith('@')) {
      continue;
    }

    let target = null;
    let resolved = null;

    if (spec.startsWith('.')) {
      resolved = resolveRelative(file, spec);
      target = moduleOf(resolved);
      if (target === null) {
        add('R-06', relToRoot(file), imported.line, `相对导入越出模块：${spec}`);
        continue;
      }
      if (target.name !== from.name) {
        add('R-06', relToRoot(file), imported.line,
          `跨模块必须走包名桶导入，禁止相对路径：${spec}`);
      }
    } else {
      target = findPackage(spec);
      if (target === null) {
        continue;
      }
      if (spec !== target.name) {
        add('R-06', relToRoot(file), imported.line,
          `跨模块禁止深路径：${spec}（应为 "${target.name}"）`);
      }
    }

    // 分层规则只在跨模块时生效
    if (target.name !== from.name) {
      edges.get(from.name).add(target.name);

      if (from.layer === 'products' && target.layer === 'products') {
        add('R-01', relToRoot(file), imported.line, `products 之间禁止横向依赖：${from.name} -> ${target.name}`);
      }
      if (from.layer === 'features' && target.layer === 'products') {
        add('R-02', relToRoot(file), imported.line, `features 不得依赖 products：${from.name} -> ${target.name}`);
      }
      if (from.layer === 'commons' && (target.layer === 'features' || target.layer === 'products')) {
        add('R-03', relToRoot(file), imported.line, `commons 不得反向依赖上层：${from.name} -> ${target.name}`);
      }
      if (from.layer === 'features' && target.layer === 'features') {
        const pair = `${from.name}->${target.name}`;
        if (!ALLOWED_FEATURE_EDGES.has(pair)) {
          add('R-04', relToRoot(file), imported.line,
            `features 横向依赖不在白名单：${pair}（允许 ${[...ALLOWED_FEATURE_EDGES].join('、')}）`);
        }
      }
    }

    // R-07：view 不得依赖 repository / commons_data
    if (from.layer === 'features' && hasSegment(moduleRelative, 'view')) {
      if (target.name === 'commons_data') {
        add('R-07', relToRoot(file), imported.line, 'view 不得 import commons_data，只吃 VM 暴露的类型');
      }
      if (resolved !== null && hasSegment(path.relative(from.dir, resolved), 'repository')) {
        add('R-07', relToRoot(file), imported.line, 'view 不得 import repository/，只吃 VM 暴露的类型');
      }
    }

    // R-08：viewmodel 不得依赖 view
    if (from.layer === 'features' && hasSegment(moduleRelative, 'viewmodel')) {
      if (resolved !== null && hasSegment(path.relative(from.dir, resolved), 'view')) {
        add('R-08', relToRoot(file), imported.line, 'viewmodel 不得 import view/');
      }
    }
  }
}

// R-09：循环依赖
const state = new Map();
const stack = [];
const reportedCycles = new Set();

function dfs(name) {
  state.set(name, 1);
  stack.push(name);
  for (const next of edges.get(name) || []) {
    const nextState = state.get(next) || 0;
    if (nextState === 0) {
      dfs(next);
    } else if (nextState === 1) {
      const at = stack.indexOf(next);
      const cycle = [...stack.slice(at), next].join(' -> ');
      if (!reportedCycles.has(cycle)) {
        reportedCycles.add(cycle);
        add('R-09', 'module graph', 0, `存在循环依赖：${cycle}`);
      }
    }
  }
  stack.pop();
  state.set(name, 2);
}

for (const item of modules) {
  if ((state.get(item.name) || 0) === 0) {
    dfs(item.name);
  }
}

// ---------- 输出 ----------
console.log('分层架构门禁（R-01~R-09）');
console.log(`模块 ${modules.map((item) => item.name).join(', ')}`);
console.log(`扫描源码 ${files.length} 个文件\n`);

let failed = false;
for (const rule of RULE_IDS) {
  const hits = violations.filter((item) => item.rule === rule);
  if (hits.length === 0) {
    console.log(`${rule} PASS`);
  } else {
    failed = true;
    console.log(`${rule} FAIL（${hits.length}）`);
    for (const hit of hits) {
      console.log(`  - ${hit.file}:${hit.line} ${hit.message}`);
    }
  }
}

if (failed) {
  console.error(`\nFAIL：${violations.length} 项违规`);
  process.exit(1);
}
console.log('\nPASS：R-01~R-09 全部通过。');
