#!/usr/bin/env node
/**
 * 版本一致性门禁（阶段一发版要求）：
 *   V-01 AppScope/app.json5 必须有 versionName（x.y.z）与正整数 versionCode
 *   V-02 versionCode 与 versionName 口径匹配（major*1000000 + minor*1000 + patch）
 *   V-03 所有模块（entry + features/* + commons/*）oh-package.json5 的 version 必须等于 versionName
 * 退出码：0 通过，1 失败。
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const RULES = ['V-01', 'V-02', 'V-03'];
const violations = [];

function add(rule, file, message) {
  violations.push({ rule, file, message });
}

function readText(file) {
  return fs.readFileSync(file, 'utf8');
}

function readJson5Loose(file) {
  const text = readText(file);
  try {
    return JSON.parse(text);
  } catch {
    const grab = (key) => {
      const m = text.match(new RegExp(`"${key}"\\s*:\\s*"?([^",\\n}]+)"?`));
      return m ? m[1].trim() : '';
    };
    return { versionName: grab('versionName'), versionCode: grab('versionCode'), version: grab('version') };
  }
}

// ---------- app.json5 ----------
const appFile = path.join(ROOT, 'AppScope', 'app.json5');
if (!fs.existsSync(appFile)) {
  add('V-01', 'AppScope/app.json5', '缺少 AppScope/app.json5');
} else {
  const app = readJson5Loose(appFile);
  const appBlock = app.app || {};
  const versionName = String(appBlock.versionName || '').trim();
  const versionCode = Number(appBlock.versionCode);

  if (!/^\d+\.\d+\.\d+$/.test(versionName)) {
    add('V-01', 'AppScope/app.json5', `versionName 必须为 x.y.z，实际 "${versionName}"`);
  }
  if (!Number.isInteger(versionCode) || versionCode <= 0) {
    add('V-01', 'AppScope/app.json5', `versionCode 必须为正整数，实际 "${appBlock.versionCode}"`);
  } else if (/^\d+\.\d+\.\d+$/.test(versionName)) {
    const [major, minor, patch] = versionName.split('.').map((n) => Number(n));
    if (minor > 999 || patch > 999) {
      add('V-02', 'AppScope/app.json5', `versionName "${versionName}" 的 minor/patch 超过 999，无法映射 versionCode`);
    } else {
      const expected = major * 1000000 + minor * 1000 + patch;
      if (versionCode !== expected) {
        add('V-02', 'AppScope/app.json5',
          `versionCode ${versionCode} 与 versionName ${versionName} 不匹配（应为 ${expected}）`);
      }
    }
  }

  // ---------- 模块 oh-package.json5 ----------
  const moduleFiles = [];
  for (const layer of ['products', 'features', 'commons']) {
    const layerDir = path.join(ROOT, layer);
    if (!fs.existsSync(layerDir)) {
      continue;
    }
    for (const entry of fs.readdirSync(layerDir, { withFileTypes: true })) {
      if (!entry.isDirectory()) {
        continue;
      }
      const pkg = path.join(layerDir, entry.name, 'oh-package.json5');
      if (fs.existsSync(pkg)) {
        moduleFiles.push({ rel: path.relative(ROOT, pkg).replace(/\\/g, '/'), file: pkg });
      }
    }
  }
  if (moduleFiles.length === 0) {
    add('V-03', 'oh-package.json5', '未发现任何模块 oh-package.json5');
  }
  for (const item of moduleFiles) {
    const pkg = readJson5Loose(item.file);
    const version = String(pkg.version || '').trim();
    if (version !== versionName) {
      add('V-03', item.rel, `模块版本 "${version}" 与 AppScope versionName "${versionName}" 不一致`);
    }
  }

  console.log('版本一致性门禁（V-01~V-03）');
  console.log(`versionName=${versionName} versionCode=${appBlock.versionCode}`);
  console.log(`模块 ${moduleFiles.length} 个：${moduleFiles.map((m) => m.rel.split('/')[1]).join(', ')}\n`);
}

let failed = false;
for (const rule of RULES) {
  const hits = violations.filter((v) => v.rule === rule);
  if (hits.length === 0) {
    console.log(`${rule} PASS`);
  } else {
    failed = true;
    console.log(`${rule} FAIL（${hits.length}）`);
    for (const hit of hits) {
      console.log(`  - ${hit.file}: ${hit.message}`);
    }
  }
}

if (failed) {
  console.error(`\nFAIL：${violations.length} 项版本问题`);
  process.exit(1);
}
console.log('\nPASS：版本号统一（app.json5 与全部模块一致，versionCode 规则匹配）。');
