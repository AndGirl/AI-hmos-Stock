import { QuoteSnapshot, TradeStatus } from '../model/QuoteModels';

/**
 * 行情缓存规则（M9-6 / AC-111）。
 *
 * TTL 口径（计划 §5.5 `quote_cache_v1`）：
 * - 交易时段（`pre`/`auction`/`open`/`lunch`）→ 60s；
 * - 收盘后（`closed`）→ 当日有效（到当日 24:00）；
 * - 停牌/退市 → 当日有效（价格本身不再变化）；
 * - 缓存**不参与排序**（沿用列头快照序，避免冷启首帧顺序与刷新后不一致）。
 *
 * 上限 100 条，超出按「最旧优先淘汰」。
 */

export const QUOTE_CACHE_MAX: number = 100;

/** 交易时段缓存 TTL：60s。 */
export const QUOTE_CACHE_TTL_TRADING_MS: number = 60000;

/** 是否交易时段（决定 TTL 口径）。 */
export function isTradingStatus(status: TradeStatus): boolean {
  return status === 'pre' || status === 'auction' || status === 'open' || status === 'lunch';
}

/** 当日 24:00 的时间戳（本地时区）。 */
export function endOfDay(now: number): number {
  const date: Date = new Date(now);
  date.setHours(23, 59, 59, 999);
  return date.getTime();
}

/** 按状态与当前时间算 TTL；收盘后返回「到当日结束」的剩余毫秒。 */
export function cacheTtlMs(status: TradeStatus, now: number): number {
  if (isTradingStatus(status)) {
    return QUOTE_CACHE_TTL_TRADING_MS;
  }
  return Math.max(0, endOfDay(now) - now);
}

/** 缓存项：快照 + 写入时间。 */
export class QuoteCacheEntry {
  code: string;
  quote: QuoteSnapshot;
  ts: number;

  constructor(code: string, quote: QuoteSnapshot, ts: number) {
    this.code = code;
    this.quote = quote;
    this.ts = ts;
  }

  /** 按自身状态算是否新鲜。 */
  fresh(now: number): boolean {
    return now - this.ts <= cacheTtlMs(this.quote.status, this.ts);
  }
}

/** 过滤掉过期项（保持原顺序）。 */
export function pruneExpired(entries: QuoteCacheEntry[], now: number): QuoteCacheEntry[] {
  const kept: QuoteCacheEntry[] = [];
  for (let i = 0; i < entries.length; i++) {
    if (entries[i].fresh(now)) {
      kept.push(entries[i]);
    }
  }
  return kept;
}

/** 截断到上限：保留最新写入的 `QUOTE_CACHE_MAX` 条（返回新数组，顺序按 ts 升序）。 */
export function capEntries(entries: QuoteCacheEntry[]): QuoteCacheEntry[] {
  if (entries.length <= QUOTE_CACHE_MAX) {
    return entries;
  }
  const sorted: QuoteCacheEntry[] = entries.slice().sort(
    (a: QuoteCacheEntry, b: QuoteCacheEntry): number => a.ts - b.ts
  );
  return sorted.slice(sorted.length - QUOTE_CACHE_MAX);
}

/**
 * 快照是否可进缓存：
 * - 停牌/退市快照价格为空但**本身不再变化**，可以缓存（否则自选里只要有 1 只停牌，
 *   缓存命中率就永远差 1 条，冷启永远走网络路径）；
 * - 其余「没有最新价」的快照（未开盘/异常）不缓存，避免冷启渲染一屏 `--`。
 */
export function cacheable(snapshot: QuoteSnapshot): boolean {
  if (snapshot.status === 'suspended' || snapshot.status === 'delisted') {
    return true;
  }
  return snapshot.last !== null && snapshot.last !== undefined;
}
