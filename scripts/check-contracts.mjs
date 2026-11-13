#!/usr/bin/env node
/**
 * 契约完整性门禁（G2-05 / M9-1）。
 *
 * 背景：M9 起 `commons/data` 的 Provider 接口要「只加不改」地扩可选成员，
 * 最容易出的错是「接口加了方法、某个实现忘了写」或「新 Provider 只有接口没有实现」。
 * 这类问题编译期不一定报（可选成员尤其不报），所以在提交前静态拦一次。
 *
 * 规则：
 *   K-01 每个 `*Provider` 接口至少有一个实现类；
 *   K-02 每个实现类必须实现该接口的全部**必需**成员（带 `?` 的可选成员可缺省）；
 *   K-03 每个 `*Provider` 接口必须出现在装配点 `commons/data/src/main/ets/DataServices.ets`；
 *   K-04 契约 v1.1 的可选成员不得被实现成「必需」签名（`onError`/`capabilities`/`chartPage`
 *        必须是 `?` 形式），防止把「只加不改」写成破坏性变更。
 *
 * 退出码：0 通过，1 失败。
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const DATA_MAIN = path.join(ROOT, 'commons', 'data', 'src', 'main', 'ets');
const DATA_SERVICES = path.join(DATA_MAIN, 'DataServices.ets');

/** 契约 v1.1 里必须是可选形式的成员。 */
const OPTIONAL_MEMBERS = [
  'onError',
  'capabilities',
  'chartPage',
  'seq',
  'retryAfterMs',
  'browse',
  'listOrders',
  'cancelOrder',
  'openAccount',
  'positionOf'
];

const norm = (value) => value.replace(/\\/g, '/');
const rel = (file) => norm(path.relative(ROOT, file));

function walk(dir, out) {
  if (!fs.existsSync(dir)) {
    return;
  }
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === 'build' || entry.name === 'oh_modules' || entry.name === 'node_modules') {
      continue;
    }
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(full, out);
    } else if (entry.isFile() && entry.name.endsWith('.ets')) {
      out.push(full);
    }
  }
}

/** 从接口/类体里抽成员名（方法与方法式属性）。 */
function membersOf(body) {
  const names = [];
  const methodRe = /^\s+(?:async\s+)?(?:readonly\s+)?([A-Za-z_][\w]*)(\??)\s*[<(]/gm;
  const propRe = /^\s+(?:readonly\s+)?([A-Za-z_][\w]*)(\??)\s*:\s*[A-Za-z_([{]/gm;
  let match;
  while ((match = methodRe.exec(body)) !== null) {
    names.push({ name: match[1], optional: match[2] === '?' });
  }
  while ((match = propRe.exec(body)) !== null) {
    names.push({ name: match[1], optional: match[2] === '?' });
  }
  return names;
}

const files = [];
walk(DATA_MAIN, files);

const interfaces = new Map();
const implementations = new Map();

for (const file of files) {
  const content = fs.readFileSync(file, 'utf8');

  // 接口：export interface XxxProvider { ... }
  const ifaceRe = /export\s+interface\s+([A-Za-z_][\w]*Provider)\s*(?:extends[^{]*)?\{/g;
  let match;
  while ((match = ifaceRe.exec(content)) !== null) {
    const start = ifaceRe.lastIndex;
    const end = content.indexOf('\n}', start);
    if (end < 0) {
      continue;
    }
    const body = content.slice(start, end);
    interfaces.set(match[1], {
      name: match[1],
      file: rel(file),
      members: membersOf(body)
    });
  }

  // 实现：class Xxx implements A, BProvider { ... }
  const classRe = /class\s+([A-Za-z_][\w]*)\s+implements\s+([^{]+)\{/g;
  while ((match = classRe.exec(content)) !== null) {
    const start = classRe.lastIndex;
    const end = content.indexOf('\n}', start);
    if (end < 0) {
      continue;
    }
    const body = content.slice(start, end);
    const targets = match[2].split(',').map((item) => item.trim()).filter(Boolean);
    const members = membersOf(body).map((item) => item.name);
    for (const target of targets) {
      if (!target.endsWith('Provider')) {
        continue;
      }
      if (!implementations.has(target)) {
        implementations.set(target, []);
      }
      implementations.get(target).push({
        className: match[1],
        file: rel(file),
        members
      });
    }
  }
}

const violations = [];
const add = (rule, file, message) => violations.push({ rule, file, message });

const dataServicesText = fs.existsSync(DATA_SERVICES) ? fs.readFileSync(DATA_SERVICES, 'utf8') : '';

for (const iface of [...interfaces.values()].sort((a, b) => a.name.localeCompare(b.name))) {
  const impls = implementations.get(iface.name) || [];

  // K-01 至少一个实现
  if (impls.length === 0) {
    add('K-01', iface.file, `${iface.name} 没有任何实现类`);
    continue;
  }

  // K-02 必需成员齐备
  for (const impl of impls) {
    for (const member of iface.members) {
      if (member.optional) {
        continue;
      }
      if (!impl.members.includes(member.name)) {
        add('K-02', impl.file, `${impl.className} 缺少 ${iface.name}.${member.name}()`);
      }
    }
  }

  // K-03 装配点覆盖
  if (!dataServicesText.includes(iface.name)) {
    add('K-03', 'commons/data/src/main/ets/DataServices.ets',
      `装配点未出现 ${iface.name}（新增 Provider 必须在 DataServices 暴露工厂）`);
  }
}

// K-04 契约 v1.1 可选成员必须是 `?` 形式
for (const iface of interfaces.values()) {
  for (const member of iface.members) {
    if (OPTIONAL_MEMBERS.includes(member.name) && !member.optional) {
      add('K-04', iface.file, `${iface.name}.${member.name} 必须是可选成员（M9 契约「只加不改」）`);
    }
  }
}

console.log('契约完整性门禁（K-01~K-04）');
console.log(`扫描 ${files.length} 个文件，${interfaces.size} 个 Provider 接口`);
const summary = [...interfaces.values()]
  .sort((a, b) => a.name.localeCompare(b.name))
  .map((item) => `${item.name}(${(implementations.get(item.name) || []).length})`)
  .join(' ');
console.log(`${summary}\n`);

let failed = false;
for (const rule of ['K-01', 'K-02', 'K-03', 'K-04']) {
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
  console.error(`\nFAIL：${violations.length} 项契约问题`);
  process.exit(1);
}
console.log('\nPASS：K-01~K-04 全部通过。');
