#!/usr/bin/env node
/**
 * 行情采样比对（M9-7 / AC-110）。
 *
 * 用途：用**独立实现**复算涨跌停与价格区间，检验 App 运行时下发的数值是否一致。
 * 本项目没有真实行情源，所以比对对象不是「供应商 vs 我们」，而是
 * 「App 运行时（通道 + 校验后的快照） vs 契约文档里的板块规则」。
 *
 * 采样来源：自选页调试面板 →「场景… → 行情通道… → 采样与缓存… → 导出行情采样」，
 * 每行一条 `QUOTE_SAMPLE {...}` 写进 hilog：
 *
 *   hdc -t <sn> shell "hilog -x" > dump.txt
 *   node scripts/compare-quote.mjs dump.txt
 *
 * 字段口径见 docs/api-contract-v1.md §3；规则见 commons/data/src/main/ets/rules/LimitRules.ets。
 *
 * 退出码：0 通过（一致率 ≥99.5% 且无硬违规），1 失败。
 */
import fs from 'node:fs';

const RATE_THRESHOLD = 99.5;
const TOLERANCE = 0.011; // 一分钱舍入容差
const PRICE_MIN = 0.01;
const PRICE_MAX = 100000;
const LIMIT_TOLERANCE = 0.02;

const BOARD_RATIOS = { main: 0.1, star: 0.2, chinext: 0.2, bse: 0.3, st: 0.05 };

function round2(value) {
  return Math.round(value * 100) / 100;
}

function boardOf(code) {
  if (code.startsWith('688')) {
    return 'star';
  }
  if (code.startsWith('300') || code.startsWith('301')) {
    return 'chinext';
  }
  if (code.startsWith('920') || code.startsWith('8') || code.startsWith('43') ||
    code.startsWith('83') || code.startsWith('87')) {
    return 'bse';
  }
  return 'main';
}

function ratioOf(code) {
  const board = boardOf(code);
  return BOARD_RATIOS[board] !== undefined ? BOARD_RATIOS[board] : BOARD_RATIOS.main;
}

function expectedLimits(sample) {
  if (sample.prevClose === null || sample.prevClose === undefined || sample.prevClose <= 0) {
    return null;
  }
  const ratio = ratioOf(sample.code);
  return {
    limitUp: round2(sample.prevClose * (1 + ratio)),
    limitDown: round2(sample.prevClose * (1 - ratio)),
    ratio
  };
}

function parseSamples(text) {
  const samples = [];
  for (const line of text.split(/\r?\n/)) {
    const at = line.indexOf('QUOTE_SAMPLE ');
    if (at < 0) {
      continue;
    }
    const raw = line.slice(at + 'QUOTE_SAMPLE '.length).trim();
    if (!raw.startsWith('{')) {
      continue;
    }
    try {
      samples.push(JSON.parse(raw));
    } catch {
      // 截断/串行的行直接跳过（hilog 会断行）
    }
  }
  return samples;
}

const file = process.argv[2];
if (!file) {
  console.error('用法：node scripts/compare-quote.mjs <hilog-dump.txt>');
  process.exit(1);
}
if (!fs.existsSync(file)) {
  console.error(`找不到文件：${file}`);
  process.exit(1);
}

const samples = parseSamples(fs.readFileSync(file, 'utf8'));
if (samples.length === 0) {
  console.error('未找到 QUOTE_SAMPLE 采样行（先在调试面板导出一次）');
  process.exit(1);
}

const buckets = {
  match: 0,
  rounding: 0,
  board_rule: 0,
  out_of_limit: 0,
  price_range: 0,
  missing_limit: 0,
  skipped: 0
};
const details = [];

for (const sample of samples) {
  if (sample.status === 'suspended' || sample.status === 'delisted') {
    buckets.skipped++;
    continue;
  }
  const expected = expectedLimits(sample);
  if (expected === null) {
    buckets.skipped++;
    continue;
  }
  if (sample.limitUp === -1 || sample.limitDown === -1) {
    buckets.missing_limit++;
    details.push(`${sample.code} 缺涨跌停（status=${sample.status}）`);
    continue;
  }
  const upDiff = Math.abs(sample.limitUp - expected.limitUp);
  const downDiff = Math.abs(sample.limitDown - expected.limitDown);
  if (upDiff > TOLERANCE || downDiff > TOLERANCE) {
    buckets.board_rule++;
    details.push(`${sample.code} 涨跌停不符：期望 ${expected.limitUp}/${expected.limitDown}` +
      `（板块 ${boardOf(sample.code)} ${(expected.ratio * 100).toFixed(0)}%），` +
      `实际 ${sample.limitUp}/${sample.limitDown}`);
    continue;
  }
  const hadRounding = upDiff > 0 || downDiff > 0;
  if (sample.last !== -1) {
    if (sample.last < PRICE_MIN || sample.last > PRICE_MAX) {
      buckets.price_range++;
      details.push(`${sample.code} 价格越界：${sample.last}`);
      continue;
    }
    const overUp = sample.last > expected.limitUp * (1 + LIMIT_TOLERANCE);
    const underDown = sample.last < expected.limitDown * (1 - LIMIT_TOLERANCE);
    if (overUp || underDown) {
      buckets.out_of_limit++;
      details.push(`${sample.code} 价格超出涨跌停容差：last=${sample.last}，` +
        `区间 ${expected.limitDown}~${expected.limitUp}`);
      continue;
    }
  }
  if (hadRounding) {
    buckets.rounding++;
  } else {
    buckets.match++;
  }
}

const checked = samples.length - buckets.skipped;
const passed = buckets.match + buckets.rounding;
const rate = checked > 0 ? (passed / checked) * 100 : 0;
const hardViolations = buckets.board_rule + buckets.out_of_limit + buckets.price_range + buckets.missing_limit;

console.log('行情采样比对（M9-7 / AC-110）');
console.log(`采样文件：${file}`);
console.log(`采样 ${samples.length} 条，参与校验 ${checked} 条，跳过 ${buckets.skipped} 条（停牌/无昨收）\n`);
console.log(`一致 ${buckets.match} 条`);
console.log(`舍入差（≤${TOLERANCE}） ${buckets.rounding} 条`);
console.log(`板块规则不符 ${buckets.board_rule} 条`);
console.log(`超涨跌停容差 ${buckets.out_of_limit} 条`);
console.log(`价格越界 ${buckets.price_range} 条`);
console.log(`缺涨跌停 ${buckets.missing_limit} 条`);
console.log(`\n一致率 ${rate.toFixed(2)}%（阈值 ${RATE_THRESHOLD}%）`);

if (details.length > 0) {
  console.log('\n明细：');
  for (const line of details.slice(0, 40)) {
    console.log(`  - ${line}`);
  }
  if (details.length > 40) {
    console.log(`  … 其余 ${details.length - 40} 条省略`);
  }
}

if (hardViolations > 0 || rate < RATE_THRESHOLD) {
  console.error('\nFAIL：存在硬违规或一致率低于阈值');
  process.exit(1);
}
console.log('\nPASS：涨跌停与价格区间与板块规则一致。');
