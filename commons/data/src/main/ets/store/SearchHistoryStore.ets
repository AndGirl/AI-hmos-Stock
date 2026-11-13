import { SEARCH_HISTORY_MAX } from '../model/SearchModels';
import { normalizeTerm } from '../rules/SearchRules';
import { StorageAdapter } from './StorageAdapter';

const HISTORY_KEY: string = 'search_history_v1';

/**
 * 搜索历史（M6-5 / FR-05.7）：本地 MRU ≤10、去重、可单删、可清空，不上云。
 * 读在搜索页首次进入时发生（异步），写只在「提交搜索」时发生，避免脏历史。
 */
export class SearchHistoryStore {
  private items: string[] = [];
  private loaded: boolean = false;
  private loading: Promise<string[]> | undefined = undefined;
  /** 写代次（M6 评审 P3）：清空与首次读盘竞争时，旧的读结果不得覆盖新状态。 */
  private generation: number = 0;

  async load(): Promise<string[]> {
    if (this.loaded) {
      return this.items.slice();
    }
    if (this.loading !== undefined) {
      return this.loading;
    }
    this.loading = this.readFromDisk();
    return this.loading;
  }

  /** 已加载时同步取（View 首帧用）；未加载返回空数组。 */
  peek(): string[] {
    return this.items.slice();
  }

  isLoaded(): boolean {
    return this.loaded;
  }

  /** 提交搜索后写入（MRU 去重，超出上限截断）。 */
  async add(term: string): Promise<string[]> {
    const text: string = term.trim();
    if (text.length === 0) {
      return this.items.slice();
    }
    await this.load();
    const key: string = normalizeTerm(text);
    const next: string[] = [text];
    for (let i = 0; i < this.items.length; i++) {
      if (normalizeTerm(this.items[i]) !== key) {
        next.push(this.items[i]);
      }
    }
    while (next.length > SEARCH_HISTORY_MAX) {
      next.pop();
    }
    this.items = next;
    await this.writeToDisk();
    return this.items.slice();
  }

  async remove(term: string): Promise<string[]> {
    await this.load();
    const key: string = normalizeTerm(term);
    const next: string[] = [];
    for (let i = 0; i < this.items.length; i++) {
      if (normalizeTerm(this.items[i]) !== key) {
        next.push(this.items[i]);
      }
    }
    this.items = next;
    await this.writeToDisk();
    return this.items.slice();
  }

  async clear(): Promise<void> {
    // 先占住代次再清盘：并发中的首次 readFromDisk 回来时会发现代次已变，直接丢弃。
    this.generation++;
    this.items = [];
    this.loaded = true;
    this.loading = undefined;
    await StorageAdapter.remove(HISTORY_KEY);
  }

  private async readFromDisk(): Promise<string[]> {
    const gen: number = this.generation;
    const text: string = await StorageAdapter.getString(HISTORY_KEY, '');
    if (gen !== this.generation) {
      // 期间执行过 clear（或再次读盘）：本次结果已过期，保留当前内存状态。
      return this.items.slice();
    }
    const parsed: string[] = SearchHistoryStore.parse(text);
    const unique: string[] = [];
    const seen: Set<string> = new Set<string>();
    for (let i = 0; i < parsed.length; i++) {
      if (typeof parsed[i] !== 'string') {
        continue;
      }
      const item: string = parsed[i].trim();
      if (item.length === 0) {
        continue;
      }
      const key: string = normalizeTerm(item);
      if (seen.has(key)) {
        continue;
      }
      seen.add(key);
      unique.push(item);
      if (unique.length >= SEARCH_HISTORY_MAX) {
        break;
      }
    }
    this.items = unique;
    this.loaded = true;
    this.loading = undefined;
    return this.items.slice();
  }

  private async writeToDisk(): Promise<void> {
    await StorageAdapter.putString(HISTORY_KEY, JSON.stringify(this.items));
  }

  private static parse(text: string): string[] {
    if (text.length === 0) {
      return [];
    }
    try {
      const value: Object = JSON.parse(text) as Object;
      if (Array.isArray(value)) {
        return value as string[];
      }
      return [];
    } catch (err) {
      return [];
    }
  }
}
