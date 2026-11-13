import { QuoteSnapshot } from '../model/QuoteModels';
import { StorageAdapter } from './StorageAdapter';
import {
  cacheable,
  capEntries,
  pruneExpired,
  QuoteCacheEntry
} from '../rules/QuoteCacheRules';

const KEY: string = 'quote_cache_v1';
const WRITE_MERGE_MS: number = 200;

/** 落盘结构（带版本，便于后续加字段不破旧数据）。 */
class QuoteCacheDoc {
  version: number = 1;
  items: QuoteCacheEntry[] = [];
}

/**
 * 行情缓存（M9-6，`quote_cache_v1`）：
 * - 内存为读路径（冷启首帧直接取，不等 IO），落盘 200ms 合并写；
 * - 唯一入口仍是 `StorageAdapter`（§5.5 规则 1），本类不直接碰 preferences；
 * - 只缓存「有价格」的快照；缓存不参与排序（AC-111）。
 */
export class QuoteCacheStore {
  private entries: Map<string, QuoteCacheEntry> = new Map<string, QuoteCacheEntry>();
  private loaded: boolean = false;
  private loading: Promise<void> | undefined = undefined;
  private writeTimer: number = -1;
  private dirty: boolean = false;

  /** 冷启预热（EntryAbility 调用一次）：读盘到内存；重复调用复用同一 Promise。 */
  load(): Promise<void> {
    const existing: Promise<void> | undefined = this.loading;
    if (existing !== undefined) {
      return existing;
    }
    const task: Promise<void> = this.loadInner();
    this.loading = task;
    return task;
  }

  private async loadInner(): Promise<void> {
    try {
      const raw: string = await StorageAdapter.getString(KEY, '');
      if (raw.length > 0) {
        this.applyDoc(raw);
      }
    } catch (err) {
      // 读失败回默认（空缓存），不阻塞首帧（§5.5 规则 2）。
    }
    this.loaded = true;
  }

  private applyDoc(raw: string): void {
    const doc: QuoteCacheDoc = JSON.parse(raw) as QuoteCacheDoc;
    const items: QuoteCacheEntry[] = doc.items !== undefined && doc.items !== null ? doc.items : [];
    // JSON.parse 出来的是纯对象字面量，没有类方法：必须先还原成 QuoteCacheEntry 实例，
    // 否则 `entry.fresh()` 会抛 "is not a function"。
    const restored: QuoteCacheEntry[] = [];
    for (let i = 0; i < items.length; i++) {
      const item: QuoteCacheEntry = items[i];
      if (item.code === undefined || item.quote === undefined || item.ts === undefined) {
        continue;
      }
      restored.push(new QuoteCacheEntry(item.code, item.quote, item.ts));
    }
    const now: number = Date.now();
    const fresh: QuoteCacheEntry[] = pruneExpired(restored, now);
    for (let i = 0; i < fresh.length; i++) {
      this.entries.set(fresh[i].code, fresh[i]);
    }
  }

  /** 是否已完成首轮读盘（调试断言用）。 */
  ready(): boolean {
    return this.loaded;
  }

  /** 写一条快照：只收「有价格」的快照，过期项顺手清理。 */
  put(snapshot: QuoteSnapshot): void {
    if (!cacheable(snapshot)) {
      return;
    }
    this.entries.set(snapshot.code, new QuoteCacheEntry(snapshot.code, snapshot, Date.now()));
    this.dirty = true;
    this.scheduleWrite();
  }

  /** 批量写入（首屏快照一次性落缓存，比逐条更省）。 */
  putAll(snapshots: QuoteSnapshot[]): void {
    for (let i = 0; i < snapshots.length; i++) {
      if (cacheable(snapshots[i])) {
        this.entries.set(snapshots[i].code, new QuoteCacheEntry(snapshots[i].code, snapshots[i], Date.now()));
        this.dirty = true;
      }
    }
    if (this.dirty) {
      this.scheduleWrite();
    }
  }

  /** 取一条（过期视为未命中，返回 undefined）。 */
  cached(code: string): QuoteSnapshot | undefined {
    const entry: QuoteCacheEntry | undefined = this.entries.get(code);
    if (entry === undefined) {
      return undefined;
    }
    if (!entry.fresh(Date.now())) {
      this.entries.delete(code);
      return undefined;
    }
    return entry.quote;
  }

  /** 批量取（保持入参顺序，未命中跳过）。 */
  cachedMany(codes: string[]): QuoteSnapshot[] {
    const result: QuoteSnapshot[] = [];
    for (let i = 0; i < codes.length; i++) {
      const quote: QuoteSnapshot | undefined = this.cached(codes[i]);
      if (quote !== undefined) {
        result.push(quote);
      }
    }
    return result;
  }

  /** 内存条数（调试/验收断言）。 */
  size(): number {
    return this.entries.size;
  }

  /** 立即落盘（页面退出/杀进程前调用）。 */
  async flush(): Promise<void> {
    this.clearWriteTimer();
    if (!this.dirty) {
      return;
    }
    this.dirty = false;
    await this.writeNow();
  }

  /** 清空缓存并落盘（调试「清除行情缓存」）。 */
  async clear(): Promise<void> {
    this.entries.clear();
    this.dirty = true;
    await this.writeNow();
  }

  private scheduleWrite(): void {
    if (this.writeTimer !== -1) {
      return;
    }
    this.writeTimer = setTimeout((): void => {
      this.writeTimer = -1;
      this.writeNow().catch((): void => {
      });
    }, WRITE_MERGE_MS);
  }

  private clearWriteTimer(): void {
    if (this.writeTimer !== -1) {
      clearTimeout(this.writeTimer);
      this.writeTimer = -1;
    }
  }

  private async writeNow(): Promise<void> {
    const now: number = Date.now();
    const alive: QuoteCacheEntry[] = [];
    const expired: string[] = [];
    this.entries.forEach((entry: QuoteCacheEntry): void => {
      if (entry.fresh(now)) {
        alive.push(entry);
      } else {
        expired.push(entry.code);
      }
    });
    for (let i = 0; i < expired.length; i++) {
      this.entries.delete(expired[i]);
    }
    const capped: QuoteCacheEntry[] = capEntries(alive);
    const doc: QuoteCacheDoc = new QuoteCacheDoc();
    doc.items = capped;
    await StorageAdapter.putString(KEY, JSON.stringify(doc));
  }
}
