#!/usr/bin/env node
/**
 * 对比度与红绿可辨门禁（G2-04 / M12-3）。
 * 规则：
 *   C-01 dark：文本对 ≥4.5:1；
 *   C-02 dark：状态类非文本对 ≥3:1；
 *   C-03 base/dark：涨跌红绿 ΔE76 ≥20 且相对亮度差 ≥15%（颜色之外的 ▲/▼ 由 UI 保证）；
 *   C-04 base：只输出「阶段一现状报告」，不失败（阶段一浅色是已验收基线；
 *        需要收紧时设 STRICT_LIGHT=1）。
 * 半透明色（#AARRGGBB 且 alpha != FF）与禁用态文本不参与断言。
 * 退出码：0 通过，1 失败。
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const BASE_FILE = 'commons/ui/src/main/resources/base/element/color.json';
const DARK_FILE = 'commons/ui/src/main/resources/dark/element/color.json';
const STRICT_LIGHT = process.env.STRICT_LIGHT === '1';

const TEXT_PAIRS = [
  ['text_primary', 'bg_page'],
  ['text_primary', 'bg_surface'],
  ['text_secondary', 'bg_page'],
  ['text_secondary', 'bg_surface'],
  ['price_up', 'bg_page'],
  ['price_up', 'bg_surface'],
  ['price_down', 'bg_page'],
  ['price_down', 'bg_surface'],
  ['price_flat', 'bg_page'],
  ['price_flat', 'bg_surface'],
  ['accent', 'bg_page'],
  ['accent', 'bg_surface'],
  ['error', 'bg_page'],
  ['error', 'bg_surface'],
  ['tag_fin', 'bg_page'],
  ['tag_star', 'bg_page'],
  ['chart_avg', 'bg_page'],
  ['orderbook_title_text', 'orderbook_title_bg'],
  ['text_on_accent', 'accent_fill'],
  ['accent', 'accent_soft'],
  ['text_primary', 'accent_soft'],
  ['text_primary', 'banner_bg'],
  ['text_secondary', 'news_band_bg']
];
const NON_TEXT_PAIRS = [
  ['accent', 'bg_page'],
  ['accent', 'bg_surface'],
  ['accent_fill', 'bg_page'],
  ['price_up', 'bg_page'],
  ['price_down', 'bg_page']
];

const problems = [];

function readPalette(relativePath) {
  const file = path.join(ROOT, relativePath);
  if (!fs.existsSync(file)) {
    problems.push(`缺少调色板：${relativePath}`);
    return null;
  }
  const json = JSON.parse(fs.readFileSync(file, 'utf8'));
  const map = new Map();
  for (const item of json.color || []) {
    const value = String(item.value);
    map.set(item.name, value);
    // 同时接受去掉 color_ 前缀的短名，断言表更好读。
    map.set(item.name.replace(/^color_/, ''), value);
  }
  return map;
}

/** #RRGGBB / #AARRGGBB（alpha 在前）→ [r,g,b]；半透明返回 null。 */
function parseHex(value) {
  if (!value) {
    return null;
  }
  const text = value.replace('#', '');
  if (text.length === 8) {
    const alpha = parseInt(text.slice(0, 2), 16);
    if (alpha !== 255) {
      return null;
    }
    return [parseInt(text.slice(2, 4), 16), parseInt(text.slice(4, 6), 16), parseInt(text.slice(6, 8), 16)];
  }
  if (text.length === 6) {
    return [parseInt(text.slice(0, 2), 16), parseInt(text.slice(2, 4), 16), parseInt(text.slice(4, 6), 16)];
  }
  return null;
}

function channelLuminance(channel) {
  const value = channel / 255;
  return value <= 0.03928 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
}

function luminance(rgb) {
  return 0.2126 * channelLuminance(rgb[0]) + 0.7152 * channelLuminance(rgb[1]) +
    0.0722 * channelLuminance(rgb[2]);
}

function contrast(rgbA, rgbB) {
  const a = luminance(rgbA);
  const b = luminance(rgbB);
  const light = Math.max(a, b);
  const dark = Math.min(a, b);
  return (light + 0.05) / (dark + 0.05);
}

function toLab(rgb) {
  const r = channelLuminance(rgb[0]);
  const g = channelLuminance(rgb[1]);
  const b = channelLuminance(rgb[2]);
  let x = (r * 0.4124 + g * 0.3576 + b * 0.1805) / 0.95047;
  let y = (r * 0.2126 + g * 0.7152 + b * 0.0722) / 1.0;
  let z = (r * 0.0193 + g * 0.1192 + b * 0.9505) / 1.08883;
  const f = (t) => (t > 0.008856 ? Math.cbrt(t) : 7.787 * t + 16 / 116);
  x = f(x);
  y = f(y);
  z = f(z);
  return [116 * y - 16, 500 * (x - y), 200 * (y - z)];
}

function deltaE(rgbA, rgbB) {
  const a = toLab(rgbA);
  const b = toLab(rgbB);
  return Math.sqrt(Math.pow(a[0] - b[0], 2) + Math.pow(a[1] - b[1], 2) + Math.pow(a[2] - b[2], 2));
}

function pairLabel(foreground, background) {
  return `${foreground} / ${background}`;
}

function checkPairs(palette, pairs, threshold, kind, strict) {
  const rows = [];
  let failed = 0;
  for (const [foreground, background] of pairs) {
    const fg = parseHex(palette.get(foreground));
    const bg = parseHex(palette.get(background));
    if (fg === null || bg === null) {
      rows.push({ label: pairLabel(foreground, background), ratio: '半透明/缺失', ok: true, skipped: true });
      continue;
    }
    const ratio = contrast(fg, bg);
    const ok = ratio >= threshold;
    if (!ok) {
      failed++;
    }
    rows.push({ label: pairLabel(foreground, background), ratio: ratio.toFixed(2), ok: ok, skipped: false });
  }
  console.log(`  ${kind}（阈值 ${threshold}:1）`);
  for (const row of rows) {
    const mark = row.skipped ? 'SKIP' : (row.ok ? 'PASS' : 'FAIL');
    console.log(`    [${mark}] ${row.label.padEnd(42)} ${row.ratio}`);
  }
  if (failed > 0 && strict) {
    problems.push(`${kind}：${failed} 组对比度不达标`);
  }
  return failed;
}

function checkRedGreen(palette, label, strict) {
  const up = parseHex(palette.get('price_up'));
  const down = parseHex(palette.get('price_down'));
  if (up === null || down === null) {
    console.log(`  ${label}：涨跌色半透明/缺失，跳过 C-03`);
    return;
  }
  const de = deltaE(up, down);
  const lumUp = luminance(up);
  const lumDown = luminance(down);
  const ratio = Math.abs(lumUp - lumDown) / Math.max(lumUp, lumDown);
  const ok = de >= 20 && ratio >= 0.15;
  console.log(`  ${label} C-03 红绿可辨：ΔE=${de.toFixed(1)}（≥20） 亮度差=${(ratio * 100).toFixed(1)}%（≥15%） [${ok ? 'PASS' : 'FAIL'}]`);
  if (!ok && strict) {
    problems.push(`${label}：涨跌红绿可辨不足（ΔE ${de.toFixed(1)}，亮度差 ${(ratio * 100).toFixed(1)}%）`);
  }
}

console.log('对比度门禁（C-01~C-04）');
const base = readPalette(BASE_FILE);
const dark = readPalette(DARK_FILE);
if (base === null || dark === null) {
  for (const problem of problems) {
    console.error(`  - ${problem}`);
  }
  process.exit(1);
}

console.log('\n[base] 阶段一浅色现状（默认只报告，STRICT_LIGHT=1 时失败）');
checkPairs(base, TEXT_PAIRS, 4.5, 'C-01 文本', STRICT_LIGHT);
checkPairs(base, NON_TEXT_PAIRS, 3.0, 'C-02 非文本', STRICT_LIGHT);
checkRedGreen(base, 'base', STRICT_LIGHT);
console.log(`  注：disabled_text 与装饰性 divider/divider_strong 不参与文本断言（禁用态/分隔线豁免）。`);

console.log('\n[dark] M12 深色（严格断言）');
checkPairs(dark, TEXT_PAIRS, 4.5, 'C-01 文本', true);
checkPairs(dark, NON_TEXT_PAIRS, 3.0, 'C-02 非文本', true);
checkRedGreen(dark, 'dark', true);

if (problems.length > 0) {
  console.error('\nFAIL：对比度/可辨门禁失败：');
  for (const problem of problems) {
    console.error(`  - ${problem}`);
  }
  process.exit(1);
}
console.log('\nPASS：深色对比度与红绿可辨达标；浅色现状已输出（未启用 STRICT_LIGHT）。');
