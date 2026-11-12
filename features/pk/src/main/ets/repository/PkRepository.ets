import { DataServices, QuoteSnapshot, WatchItem, WatchlistRaw } from 'commons_data';
import { PkCandidate } from '../viewmodel/PkVM';

/**
 * PK 换股候选项来源（L2，只做装配与参数透传）：
 * - 本期用自选列表当候选池（FR-05 搜索未建，二期替换为 `scope=stock` 的搜索结果，见设计 §5.5.3）；
 * - 名称/价格走 QuoteProvider（与自选、详情同源），不额外维护一份行情。
 */
export class PkRepository {
  async candidates(): Promise<PkCandidate[]> {
    const raw: WatchlistRaw = await DataServices.watchlistProvider().load();
    const codes: string[] = [];
    for (let i = 0; i < raw.items.length; i++) {
      const item: WatchItem = raw.items[i];
      codes.push(item.code);
    }
    const snapshots: QuoteSnapshot[] = await DataServices.quoteProvider().getSnapshots(codes);
    const byCode: Map<string, QuoteSnapshot> = new Map<string, QuoteSnapshot>();
    for (let i = 0; i < snapshots.length; i++) {
      byCode.set(snapshots[i].code, snapshots[i]);
    }
    const out: PkCandidate[] = [];
    for (let i = 0; i < codes.length; i++) {
      const code: string = codes[i];
      const quote: QuoteSnapshot | undefined = byCode.get(code);
      if (quote === undefined) {
        continue;
      }
      out.push(new PkCandidate(code, quote.name, quote.last, quote.pct));
    }
    return out;
  }
}
