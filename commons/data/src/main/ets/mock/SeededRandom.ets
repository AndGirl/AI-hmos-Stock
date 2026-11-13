/**
 * 确定性伪随机（M9-7）：同一种子 + 同一调用序列 → 完全一致的结果。
 *
 * 为什么要有：模拟行情若用 `Math.random()`，任何时候重放都得到不同数值，
 * 既无法为验收「重放取证」，也无法在下一轮本地后端返回同一份数据时做对齐比对。
 *
 * 实现：mulberry32（32 位状态、周期 2^32，足够演示用；不用于任何安全场景）。
 */

/** 字符串 → 32 位种子（FNV-1a）。用于「按 code 派生独立随机流」。 */
export function hashSeed(text: string): number {
  let hash: number = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) {
    hash ^= text.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  return hash >>> 0;
}

/** 默认演示种子：换这个值即换「一套行情走势」，但同一值永远可复现。 */
export const SESSION_SEED: number = 20261114;

export class SeededRandom {
  private state: number;

  constructor(seed: number) {
    this.state = seed >>> 0;
  }

  /** 下一个 [0, 1) 浮点数。 */
  next(): number {
    this.state = (this.state + 0x6d2b79f5) >>> 0;
    let t: number = this.state;
    t = Math.imul(t ^ (t >>> 15), t | 1) >>> 0;
    t = (t ^ (t + Math.imul(t ^ (t >>> 7), t | 61))) >>> 0;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  }

  /** [min, max) 浮点。 */
  between(min: number, max: number): number {
    return min + this.next() * (max - min);
  }

  /** [0, maxExclusive) 整数。 */
  int(maxExclusive: number): number {
    if (maxExclusive <= 0) {
      return 0;
    }
    return Math.floor(this.next() * maxExclusive);
  }
}
