import { DataServices, QuoteSnapshot } from 'commons_data';
import { PkCandidate } from '../viewmodel/PkVM';

/**
 * PK 换股候选项来源（L2，只做装配与参数透传）：
 * - 候选池 = 当前自选（与自选页同源：`WatchlistStore`，M7-1 起不再读 Mock Provider）；
 * - 名称/价格走 QuoteProvider（与自选、详情同源），不额外维护一份行情。
 */
export class PkRepository {
  async candidates(): Promise<PkCandidate[]> {
    const codes: string[] = await DataServices.watchlistStore().codes();
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
