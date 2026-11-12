#!/usr/bin/env node
/**
 * 版本号统一修改：一次改完 AppScope 与全部模块，避免手改 9 处不一致。
 * 用法：
 *   node scripts/bump-version.mjs 1.1.0            # 实际修改
 *   node scripts/bump-version.mjs 1.1.0 --dry      # 只打印将要改的内容
 * 规则：versionCode = major*1000000 + minor*1000 + patch（与 check-version.mjs 的 V-02 一致）
 * 退出码：0 成功，1 参数/写入失败。
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const args = process.argv.slice(2);
const target = args.find((a) => /^\d+\.\d+\.\d+$/.test(a));
const dryRun = args.includes('--dry');

if (!target) {
  console.error('用法：node scripts/bump-version.mjs <x.y.z> [--dry]');
  process.exit(1);
}

const [major, minor, patch] = target.split('.').map((n) => Number(n));
if (minor > 999 || patch > 999) {
  console.error('minor / patch 不能超过 999（versionCode 映射需要）');
  process.exit(1);
}
const versionCode = major * 1000000 + minor * 1000 + patch;

const files = [path.join(ROOT, 'AppScope', 'app.json5')];
for (const layer of ['products', 'features', 'commons']) {
  const layerDir = path.join(ROOT, layer);
  if (!fs.existsSync(layerDir)) {
    continue;
  }
  for (const entry of fs.readdirSync(layerDir, { withFileTypes: true })) {
    const pkg = path.join(layerDir, entry.name, 'oh-package.json5');
    if (entry.isDirectory() && fs.existsSync(pkg)) {
      files.push(pkg);
    }
  }
}

let changed = 0;
for (const file of files) {
  const rel = path.relative(ROOT, file).replace(/\\/g, '/');
  let text = fs.readFileSync(file, 'utf8');
  const before = text;

  if (rel.endsWith('app.json5')) {
    text = text.replace(/"versionName"\s*:\s*"[^"]*"/, `"versionName": "${target}"`);
    text = text.replace(/"versionCode"\s*:\s*\d+/, `"versionCode": ${versionCode}`);
  } else {
    text = text.replace(/"version"\s*:\s*"[^"]*"/, `"version": "${target}"`);
  }

  if (text !== before) {
    changed++;
    if (dryRun) {
      console.log(`[dry] ${rel}`);
    } else {
      fs.writeFileSync(file, text);
      console.log(`[write] ${rel}`);
    }
  }
}

console.log(`\n${dryRun ? '将' : '已'}更新 ${changed} 个文件 → versionName ${target} / versionCode ${versionCode}`);
if (!dryRun) {
  console.log('下一步：node scripts/check-version.mjs 校验，再提交');
}
