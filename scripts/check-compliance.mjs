#!/usr/bin/env node
/**
 * 合规门禁（M13-1 / AC-125）。
 *
 * 背景：「无真实数据」让合规负担变轻，但**上架硬要求**不能靠记忆：
 *   - SDK 清单必须与实际依赖一致（多写=虚假声明，少写=隐瞒）；
 *   - 权限必须最小化（本项目当前为 0 权限，任何新增都要走白名单并写进清单）；
 *   - 调试入口必须在 release 不可达（长按调试面板若漏守卫，审核/线上都会暴露）；
 *   - 隐私政策/同意的文案必须齐备（页面缺文案 = 隐私政策不可查）。
 *
 * 规则：
 *   X-01 SDK 清单与 `oh-package.json5` 的第三方运行期依赖完全一致（双向）；
 *   X-02 `module.json5` 的 `requestPermissions` 必须 ⊆ 白名单，且与清单文档一致；
 *   X-03 引用 `BuildProfile.DEBUG` 的文件必须有守卫；出现「调试」按钮但没引用 DEBUG 视为漏守卫；
 *   X-04 隐私政策/同意必需文案键齐备（`commons/basic` 资源）。
 *
 * 退出码：0 通过，1 失败。
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const SDK_DOC = path.join(ROOT, 'docs', 'phase2-sdk-list.md');
const STRINGS = path.join(ROOT, 'commons', 'basic', 'src', 'main', 'resources', 'base', 'element', 'string.json');

/** 允许申请的系统权限（当前策略：不申请任何权限；留白名单只为「本地后端」接入时放行网络类）。 */
const ALLOWED_PERMISSIONS = ['ohos.permission.INTERNET', 'ohos.permission.GET_NETWORK_INFO'];

/** 项目内本地模块（`file:` 依赖，不算第三方 SDK）。 */
const LOCAL_MODULES = ['watchlist', 'detail', 'trade', 'pk', 'search', 'account', 'commons_ui',
  'commons_basic', 'commons_data'];

/** X-04 必需文案键（计划 §12.2 `privacy_*` / `consent_*` 8 条 + 隐私页正文）。 */
const REQUIRED_STRINGS = ['privacy_title', 'privacy_consent_title', 'consent_agree', 'consent_reject',
  'consent_policy_link', 'privacy_revoke', 'privacy_revoke_confirm_title', 'privacy_version',
  'privacy_entry_policy'];

const norm = (value) => value.replace(/\\/g, '/');
const rel = (file) => norm(path.relative(ROOT, file));

function walk(dir, out, predicate) {
  if (!fs.existsSync(dir)) {
    return;
  }
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === 'build' || entry.name === 'oh_modules' || entry.name === 'node_modules' ||
      entry.name === '.test' || entry.name === '.preview' || entry.name.startsWith('.')) {
      continue;
    }
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(full, out, predicate);
    } else if (entry.isFile() && predicate(entry.name)) {
      out.push(full);
    }
  }
}

/** 极简 JSON5 读取：只用于 `oh-package.json5` / `module.json5`（注释 + 单引号 + 尾逗号）。 */
function readJson5(file) {
  let text = fs.readFileSync(file, 'utf8');
  text = text.replace(/\/\*[\s\S]*?\*\//g, '').replace(/(^|[^:])\/\/.*$/gm, '$1');
  text = text.replace(/,\s*([}\]])/g, '$1');
  text = text.replace(/'([^'\\]|\\.)*'/g, (match) => `"${match.slice(1, -1).replace(/"/g, '\\"')}"`);
  return JSON.parse(text);
}

const violations = [];
const add = (rule, file, message) => violations.push({ rule, file, message });

// ---------------------------------------------------------------- X-01 SDK 清单
const pkgFiles = [];
walk(ROOT, pkgFiles, (name) => name === 'oh-package.json5');

const actualSdks = new Map();
for (const file of pkgFiles) {
  const json = readJson5(file);
  const deps = json.dependencies || {};
  for (const [name, version] of Object.entries(deps)) {
    if (LOCAL_MODULES.includes(name) || String(version).startsWith('file:')) {
      continue;
    }
    actualSdks.set(name, String(version));
  }
}

const sdkDocText = fs.existsSync(SDK_DOC) ? fs.readFileSync(SDK_DOC, 'utf8') : '';
const sdkBlock = sdkDocText.match(/<!-- SDK-LIST:BEGIN -->([\s\S]*?)<!-- SDK-LIST:END -->/);
const documented = new Map();
if (sdkBlock === null) {
  add('X-01', 'docs/phase2-sdk-list.md', '缺少 `<!-- SDK-LIST:BEGIN/END -->` 标记块');
} else {
  const itemRe = /`(@?[A-Za-z0-9._-]+(?:\/[A-Za-z0-9._-]+)?)@([0-9][^`]*)`/g;
  let match;
  while ((match = itemRe.exec(sdkBlock[1])) !== null) {
    documented.set(match[1], match[2].trim());
  }
}
for (const [name, version] of actualSdks) {
  if (!documented.has(name)) {
    add('X-01', 'docs/phase2-sdk-list.md', `实际依赖 ${name}@${version} 未登记进 SDK 清单`);
  } else if (documented.get(name) !== version) {
    add('X-01', 'docs/phase2-sdk-list.md',
      `${name} 版本不一致：清单 ${documented.get(name)} / 实际 ${version}`);
  }
}
for (const name of documented.keys()) {
  if (!actualSdks.has(name)) {
    add('X-01', 'docs/phase2-sdk-list.md', `清单登记的 ${name} 已不在依赖里（虚假声明）`);
  }
}

// ---------------------------------------------------------------- X-02 权限
const moduleFiles = [];
walk(path.join(ROOT, 'products'), moduleFiles, (name) => name === 'module.json5');
walk(path.join(ROOT, 'features'), moduleFiles, (name) => name === 'module.json5');
walk(path.join(ROOT, 'commons'), moduleFiles, (name) => name === 'module.json5');

const declaredPermissions = new Set();
for (const file of moduleFiles) {
  const json = readJson5(file);
  const list = (json.module && json.module.requestPermissions) || [];
  for (const item of list) {
    const name = item && item.name;
    if (typeof name !== 'string') {
      continue;
    }
    declaredPermissions.add(name);
    if (!ALLOWED_PERMISSIONS.includes(name)) {
      add('X-02', rel(file), `权限 ${name} 不在白名单（当前应为 0 权限）`);
    }
  }
}
const permBlock = sdkDocText.match(/<!-- PERMISSIONS:BEGIN -->([\s\S]*?)<!-- PERMISSIONS:END -->/);
const documentedPermissions = new Set();
if (permBlock === null) {
  add('X-02', 'docs/phase2-sdk-list.md', '缺少 `<!-- PERMISSIONS:BEGIN/END -->` 标记块');
} else {
  const permRe = /`(ohos\.permission\.[A-Z_]+)`/g;
  let match;
  while ((match = permRe.exec(permBlock[1])) !== null) {
    documentedPermissions.add(match[1]);
  }
}
for (const name of declaredPermissions) {
  if (!documentedPermissions.has(name)) {
    add('X-02', 'docs/phase2-sdk-list.md', `模块声明了 ${name}，清单未登记`);
  }
}
for (const name of documentedPermissions) {
  if (!declaredPermissions.has(name)) {
    add('X-02', 'docs/phase2-sdk-list.md', `清单登记了 ${name}，但没有任何模块声明`);
  }
}

// ---------------------------------------------------------------- X-03 调试入口守卫
const etsFiles = [];
walk(ROOT, etsFiles, (name) => name.endsWith('.ets'));

const guardedFiles = [];
for (const file of etsFiles) {
  const text = fs.readFileSync(file, 'utf8');
  const importsDebug = /import\s*\{\s*DEBUG\s*\}\s*from\s*['"][^'"]*BuildProfile['"]/.test(text);
  const hasDebugWord = /调试/.test(text);
  const guard = /if\s*\(\s*!?\s*DEBUG\s*\)/.test(text);
  if (importsDebug) {
    guardedFiles.push(rel(file));
    if (!guard) {
      add('X-03', rel(file), '引用了 DEBUG 但没有 `if (!DEBUG)` / `if (DEBUG)` 守卫');
    }
  } else if (hasDebugWord && /showActionMenu\s*\(/.test(text)) {
    add('X-03', rel(file), '出现调试菜单但没有引用 BuildProfile.DEBUG（release 会露出）');
  }
}

// ---------------------------------------------------------------- X-04 隐私文案
const strings = fs.existsSync(STRINGS) ? JSON.parse(fs.readFileSync(STRINGS, 'utf8')).string || [] : [];
const keys = new Set(strings.map((item) => item.name));
for (const key of REQUIRED_STRINGS) {
  if (!keys.has(key)) {
    add('X-04', 'commons/basic/src/main/resources/base/element/string.json', `缺少文案键 ${key}`);
  }
}
for (let i = 1; i <= 8; i++) {
  for (const suffix of ['title', 'body']) {
    const key = `privacy_section_${i}_${suffix}`;
    if (!keys.has(key)) {
      add('X-04', 'commons/basic/src/main/resources/base/element/string.json', `缺少文案键 ${key}`);
    }
  }
}

// ---------------------------------------------------------------- 输出
console.log('合规门禁（X-01~X-04）');
console.log(`SDK 清单：实际 ${actualSdks.size} 项 / 登记 ${documented.size} 项` +
  `（${[...actualSdks.keys()].join(', ') || '无第三方依赖'}）`);
console.log(`权限：声明 ${declaredPermissions.size} 项 / 登记 ${documentedPermissions.size} 项`);
console.log(`调试守卫：${guardedFiles.length} 个文件引用 BuildProfile.DEBUG\n`);

let failed = false;
for (const rule of ['X-01', 'X-02', 'X-03', 'X-04']) {
  const hits = violations.filter((item) => item.rule === rule);
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
  console.error(`\nFAIL：${violations.length} 项合规问题`);
  process.exit(1);
}
console.log('\nPASS：X-01~X-04 全部通过。');
