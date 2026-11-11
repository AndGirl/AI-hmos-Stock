#!/usr/bin/env node
/**
 * 占位文案门禁（DEC-10-02 / ADR-08）。
 * 校验 commons/basic 的 5 条 coming_soon_* 文案：
 *   1. 必须以「下阶段开放」结尾；
 *   2. 不得包含禁用变体（敬请期待/即将上线/暂未开放/Coming/~ /! /！）；
 *   3. 不得包含版本号片段（v1.x / 一期 / 二期）；
 *   4. 不得带标点、emoji、首尾空白；
 *   5. 代码中不得硬编码这些文案（必须走资源）。
 * 退出码：0 通过，1 失败。
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const STRINGS_FILE = path.join(ROOT, 'commons/basic/src/main/resources/base/element/string.json');
const CONSTANTS_FILE = path.join(ROOT, 'commons/basic/src/main/ets/constants/ComingSoonText.ets');

const EXPECTED_KEYS = [
  'coming_soon_add_watchlist',
  'coming_soon_card_view',
  'coming_soon_home',
  'coming_soon_news',
  'coming_soon_market'
];

const FORBIDDEN_WORDS = ['敬请期待', '即将上线', '暂未开放', 'Coming', 'coming soon', '~', '!', '！'];
const VERSION_PATTERN = /(v\d+(?:\.\d+)*|一期|二期|阶段[一二三])/i;
const TRAILING_PUNCTUATION = /[。，、,.!?！？;；:：]$/;

const errors = [];
const infos = [];

function fail(message) {
  errors.push(message);
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function walkEts(dir, out) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (entry.name === 'build' || entry.name === 'oh_modules' || entry.name === 'node_modules') {
      continue;
    }
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walkEts(full, out);
    } else if (entry.isFile() && (entry.name.endsWith('.ets') || entry.name.endsWith('.ts'))) {
      out.push(full);
    }
  }
}

function checkStrings() {
  const data = readJson(STRINGS_FILE);
  const entries = Array.isArray(data.string) ? data.string : [];
  const map = new Map();
  for (const item of entries) {
    if (typeof item.name !== 'string') {
      continue;
    }
    if (map.has(item.name)) {
      fail(`资源重复：${item.name}`);
    }
    map.set(item.name, String(item.value ?? ''));
  }

  const actualKeys = [...map.keys()].filter((key) => key.startsWith('coming_soon_')).sort();
  const expectedSorted = [...EXPECTED_KEYS].sort();
  if (actualKeys.length !== expectedSorted.length || actualKeys.some((key, index) => key !== expectedSorted[index])) {
    fail(`coming_soon 键集合不符：期望 [${expectedSorted.join(', ')}]，实际 [${actualKeys.join(', ')}]`);
  }

  for (const key of EXPECTED_KEYS) {
    if (!map.has(key)) {
      fail(`缺少文案：${key}`);
      continue;
    }
    const value = map.get(key);
    if (!value.endsWith('下阶段开放')) {
      fail(`${key} 未以「下阶段开放」结尾：${value}`);
    }
    for (const word of FORBIDDEN_WORDS) {
      if (value.includes(word)) {
        fail(`${key} 含禁用变体「${word}」：${value}`);
      }
    }
    if (VERSION_PATTERN.test(value)) {
      fail(`${key} 含版本号片段：${value}`);
    }
    if (TRAILING_PUNCTUATION.test(value)) {
      fail(`${key} 末尾带标点：${value}`);
    }
    if (value !== value.trim()) {
      fail(`${key} 首尾有空白：${value}`);
    }
    if (/\p{Extended_Pictographic}/u.test(value)) {
      fail(`${key} 含 emoji：${value}`);
    }
    if (value.includes('\n')) {
      fail(`${key} 含换行：${value}`);
    }
    infos.push(`  ${key} = ${value}`);
  }

  if (fs.existsSync(CONSTANTS_FILE)) {
    const constants = fs.readFileSync(CONSTANTS_FILE, 'utf8');
    for (const key of EXPECTED_KEYS) {
      if (!constants.includes(`app.string.${key}`)) {
        fail(`ComingSoonText.ets 未引用 ${key}`);
      }
    }
  } else {
    fail('缺少 commons/basic/src/main/ets/constants/ComingSoonText.ets');
  }
}

function stripComments(content) {
  return content.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '');
}

function checkNoHardcodedCopy() {
  const files = [];
  walkEts(path.join(ROOT, 'products'), files);
  walkEts(path.join(ROOT, 'features'), files);
  walkEts(path.join(ROOT, 'commons'), files);
  const literalPattern = /['"`][^'"`\n]*下阶段开放[^'"`\n]*['"`]/;
  for (const file of files) {
    const content = stripComments(fs.readFileSync(file, 'utf8'));
    if (literalPattern.test(content)) {
      fail(`发现硬编码占位文案：${path.relative(ROOT, file)}`);
    }
  }
}

checkStrings();
checkNoHardcodedCopy();

console.log('ComingSoon 文案门禁');
for (const line of infos) {
  console.log(line);
}

if (errors.length > 0) {
  console.error(`\nFAIL（${errors.length} 项）`);
  for (const error of errors) {
    console.error(`  - ${error}`);
  }
  process.exit(1);
}

console.log(`\nPASS：${EXPECTED_KEYS.length} 条占位文案合规，无硬编码。`);
