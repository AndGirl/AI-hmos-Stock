import { describe, expect, it } from '@ohos/hypium';
import { QuoteSnapshot } from '../main/ets/model/QuoteModels';
import {
  cacheable,
  cacheTtlMs,
  capEntries,
  endOfDay,
  isTradingStatus,
  pruneExpired,
  QUOTE_CACHE_MAX,
  QUOTE_CACHE_TTL_TRADING_MS,
  QuoteCacheEntry
} from '../main/ets/rules/QuoteCacheRules';

function snapshot(code: string, last: number | null, status: string): QuoteSnapshot {
  const item: QuoteSnapshot = {
    code: code,
    market: 'SH',
    name: '示范',
    status: status === 'closed' ? 'closed' : 'open',
    snapshotTime: 1000,
    isNew: false,
    last: last,
    prevClose: 10,
    chg: 0,
    pct: 0,
    volume: 100,
    lastVolume: 10,
    amount: 1000,
    amplitude: 1,
    turnover: 1,
    pe: 10,
    pb: 1
  };
  return item;
}

/**
 * M9-6 / AC-111 缓存规则单测：日内 60s、收盘当日、过期过滤、100 条上限、空值不入缓存。
 */
export default function quoteCacheRulesTest(): void {
  describe('QuoteCacheRules', () => {
    it('trading_status_classification', 0, () => {
      expect(isTradingStatus('pre')).assertTrue();
      expect(isTradingStatus('auction')).assertTrue();
      expect(isTradingStatus('open')).assertTrue();
      expect(isTradingStatus('lunch')).assertTrue();
      expect(isTradingStatus('closed')).assertFalse();
      expect(isTradingStatus('suspended')).assertFalse();
    });

    it('trading_ttl_is_60s', 0, () => {
      const now: number = new Date(2026, 0, 5, 10, 0, 0).getTime();
      expect(cacheTtlMs('open', now)).assertEqual(QUOTE_CACHE_TTL_TRADING_MS);
      expect(cacheTtlMs('lunch', now)).assertEqual(QUOTE_CACHE_TTL_TRADING_MS);
    });

    it('closed_ttl_runs_to_end_of_day', 0, () => {
      const now: number = new Date(2026, 0, 5, 15, 30, 0).getTime();
      const ttl: number = cacheTtlMs('closed', now);
      expect(ttl > 0).assertTrue();
      expect(ttl <= 24 * 3600 * 1000).assertTrue();
      expect(now + ttl).assertEqual(endOfDay(now));
    });

    it('end_of_day_is_2359', 0, () => {
      const now: number = new Date(2026, 0, 5, 8, 0, 0).getTime();
      const end: Date = new Date(endOfDay(now));
      expect(end.getHours()).assertEqual(23);
      expect(end.getMinutes()).assertEqual(59);
    });

    it('expired_entries_pruned', 0, () => {
      const now: number = new Date(2026, 0, 5, 10, 0, 0).getTime();
      const fresh: QuoteCacheEntry = new QuoteCacheEntry('600519', snapshot('600519', 10, 'open'), now - 1000);
      const stale: QuoteCacheEntry = new QuoteCacheEntry('000001', snapshot('000001', 11, 'open'),
        now - QUOTE_CACHE_TTL_TRADING_MS - 1);
      expect(fresh.fresh(now)).assertTrue();
      expect(stale.fresh(now)).assertFalse();
      const kept: QuoteCacheEntry[] = pruneExpired([fresh, stale], now);
      expect(kept.length).assertEqual(1);
      expect(kept[0].code).assertEqual('600519');
    });

    it('closed_entry_survives_within_day', 0, () => {
      const writeAt: number = new Date(2026, 0, 5, 15, 0, 0).getTime();
      const readAt: number = new Date(2026, 0, 5, 22, 0, 0).getTime();
      const entry: QuoteCacheEntry = new QuoteCacheEntry('600519', snapshot('600519', 10, 'closed'), writeAt);
      expect(entry.fresh(readAt)).assertTrue();
    });

    it('caps_to_max_keeping_newest', 0, () => {
      const entries: QuoteCacheEntry[] = [];
      for (let i = 0; i < QUOTE_CACHE_MAX + 5; i++) {
        entries.push(new QuoteCacheEntry(`S${i}`, snapshot(`S${i}`, 10, 'open'), 1000 + i));
      }
      const capped: QuoteCacheEntry[] = capEntries(entries);
      expect(capped.length).assertEqual(QUOTE_CACHE_MAX);
      // 保留最新写入的（ts 最大）5 条被淘汰的是最早的
      expect(capped[capped.length - 1].code).assertEqual(`S${QUOTE_CACHE_MAX + 4}`);
      expect(capped[0].code).assertEqual('S5');
    });

    it('under_cap_is_unchanged', 0, () => {
      const entries: QuoteCacheEntry[] = [
        new QuoteCacheEntry('600519', snapshot('600519', 10, 'open'), 1000)
      ];
      expect(capEntries(entries).length).assertEqual(1);
    });

    it('empty_price_not_cacheable', 0, () => {
      expect(cacheable(snapshot('600519', 10, 'open'))).assertTrue();
      expect(cacheable(snapshot('600519', null, 'open'))).assertFalse();
    });
  });
}
