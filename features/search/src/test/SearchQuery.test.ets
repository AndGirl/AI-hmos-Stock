import { describe, it, expect } from '@ohos/hypium';
import {
  normalizeTerm,
  SearchHit,
  SearchOptions,
  SearchProvider,
  SearchResult,
  SearchSection
} from 'commons_data';
import { SearchQuery } from '../main/ets/repository/SearchQuery';

/** 测试桩：计数请求次数，用于验证 LRU 命中「不发请求」（AC-93）。 */
class StubSearchProvider implements SearchProvider {
  calls: number = 0;

  search(term: string, seq: number, opts?: SearchOptions): Promise<SearchResult> {
    this.calls++;
    const result: SearchResult = new SearchResult();
    result.term = normalizeTerm(term);
    result.seq = seq;
    const section: SearchSection = new SearchSection();
    section.kind = 'stock';
    const hit: SearchHit = new SearchHit();
    hit.code = '600519';
    hit.name = '贵州茅台';
    hit.kind = 'stock';
    hit.price = 1680;
    section.hits.push(hit);
    section.total = 1;
    result.sections.push(section);
    return Promise.resolve(result);
  }

  hot(): Promise<string[]> {
    return Promise.resolve(['贵州茅台']);
  }
}

/** 测试桩：返回 offline=true 的结果（验证离线结果不进 LRU，M6 评审修复）。 */
class OfflineStubProvider extends StubSearchProvider {
  search(term: string, seq: number, opts?: SearchOptions): Promise<SearchResult> {
    return super.search(term, seq, opts).then((result: SearchResult): SearchResult => {
      result.offline = true;
      return result;
    });
  }
}

function delay(ms: number): Promise<void> {
  return new Promise<void>((resolve: (value: void) => void): void => {
    setTimeout((): void => {
      resolve();
    }, ms);
  });
}

export default function searchQueryTest(): void {
  describe('SearchQuery', () => {
    it('seq_is_monotonic_and_latest', 0, () => {
      const query: SearchQuery = new SearchQuery(new StubSearchProvider());
      const first: number = query.nextSeq();
      expect(first).assertEqual(1);
      const second: number = query.nextSeq();
      expect(second).assertEqual(2);
      expect(query.isLatest(second)).assertTrue();
      expect(query.isLatest(first)).assertFalse();
      query.dispose();
    });

    it('schedule_immediate_runs_synchronously', 0, () => {
      const query: SearchQuery = new SearchQuery(new StubSearchProvider());
      let ran: boolean = false;
      query.schedule((): void => {
        ran = true;
      }, true);
      expect(ran).assertTrue();
      query.dispose();
    });

    it('debounce_waits_300ms', 0, async (done: Function) => {
      const query: SearchQuery = new SearchQuery(new StubSearchProvider());
      let ran: boolean = false;
      query.schedule((): void => {
        ran = true;
      }, false);
      await delay(150);
      expect(ran).assertFalse();
      await delay(250);
      expect(ran).assertTrue();
      query.dispose();
      done();
    });

    it('cache_hit_skips_second_request', 0, async (done: Function) => {
      const provider: StubSearchProvider = new StubSearchProvider();
      const query: SearchQuery = new SearchQuery(provider);
      const seq1: number = query.nextSeq();
      await query.run('600519', seq1, false);
      const seq2: number = query.nextSeq();
      const cached: SearchResult = await query.run('600519', seq2, false);
      expect(provider.calls).assertEqual(1);
      expect(cached.seq).assertEqual(seq1);
      query.dispose();
      done();
    });

    it('cache_key_is_normalized', 0, async (done: Function) => {
      const provider: StubSearchProvider = new StubSearchProvider();
      const query: SearchQuery = new SearchQuery(provider);
      await query.run('６００５１９', query.nextSeq(), false);
      await query.run('600519 ', query.nextSeq(), false);
      expect(provider.calls).assertEqual(1);
      query.dispose();
      done();
    });

    it('invalidate_cancels_debounce', 0, async (done: Function) => {
      const query: SearchQuery = new SearchQuery(new StubSearchProvider());
      let ran: boolean = false;
      query.schedule((): void => {
        ran = true;
      }, false);
      query.invalidate();
      await delay(400);
      expect(ran).assertFalse();
      query.dispose();
      done();
    });

    it('offline_result_not_cached', 0, async (done: Function) => {
      const provider: OfflineStubProvider = new OfflineStubProvider();
      const query: SearchQuery = new SearchQuery(provider);
      const offlineResult: SearchResult = await query.run('600519', query.nextSeq(), true);
      expect(offlineResult.offline).assertTrue();
      expect(query.cached('600519') === undefined).assertTrue();
      // 恢复网络后同词必须重新请求，不能命中离线缓存把「当前离线」带回来
      await query.run('600519', query.nextSeq(), false);
      expect(provider.calls).assertEqual(2);
      query.dispose();
      done();
    });

    it('dispose_clears_cache', 0, async (done: Function) => {
      const provider: StubSearchProvider = new StubSearchProvider();
      const query: SearchQuery = new SearchQuery(provider);
      await query.run('600519', query.nextSeq(), false);
      query.dispose();
      await query.run('600519', query.nextSeq(), false);
      expect(provider.calls).assertEqual(2);
      done();
    });
  });
}
