import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0001;
const TAG: string = 'Storage';
const STORE_NAME: string = 'xiaoyang_stock_v1';

/**
 * 存储唯一入口（M7-1 的前置子集，M6 先落地）：
 * - 全工程只有本文件可以 import `@ohos.data.preferences`，feature 不得直接用（§5.5 规则 1）；
 * - 写失败静默并保留内存副本，读失败回默认值（§5.5 规则 2）；
 * - context 由 EntryAbility 在 onCreate 注入；未注入时退化为纯内存（单测/异常兜底）。
 */
export class StorageAdapter {
  private static context: common.Context | undefined = undefined;
  private static prefs: preferences.Preferences | undefined = undefined;
  private static memory: Map<string, string> = new Map<string, string>();

  /** EntryAbility.onCreate 调用一次；重复调用覆盖旧 context。 */
  static init(context: common.Context): void {
    StorageAdapter.context = context;
    StorageAdapter.prefs = undefined;
  }

  private static async open(): Promise<preferences.Preferences | undefined> {
    if (StorageAdapter.prefs !== undefined) {
      return StorageAdapter.prefs;
    }
    if (StorageAdapter.context === undefined) {
      return undefined;
    }
    try {
      const store: preferences.Preferences =
        await preferences.getPreferences(StorageAdapter.context, { name: STORE_NAME });
      StorageAdapter.prefs = store;
      return store;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'open_fail %{public}s', JSON.stringify(err));
      return undefined;
    }
  }

  static async getString(key: string, def: string): Promise<string> {
    const store: preferences.Preferences | undefined = await StorageAdapter.open();
    if (store === undefined) {
      const cached: string | undefined = StorageAdapter.memory.get(key);
      return cached !== undefined ? cached : def;
    }
    try {
      const value: preferences.ValueType = await store.get(key, def);
      const text: string = typeof value === 'string' ? value : def;
      StorageAdapter.memory.set(key, text);
      return text;
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'read_fail key=%{public}s', key);
      return def;
    }
  }

  static async putString(key: string, value: string): Promise<void> {
    StorageAdapter.memory.set(key, value);
    const store: preferences.Preferences | undefined = await StorageAdapter.open();
    if (store === undefined) {
      return;
    }
    try {
      await store.put(key, value);
      await store.flush();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'write_fail key=%{public}s', key);
    }
  }

  static async remove(key: string): Promise<void> {
    StorageAdapter.memory.delete(key);
    const store: preferences.Preferences | undefined = await StorageAdapter.open();
    if (store === undefined) {
      return;
    }
    try {
      await store.delete(key);
      await store.flush();
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'remove_fail key=%{public}s', key);
    }
  }

  /** 调试/验收用：当前是否已具备持久化能力。 */
  static ready(): boolean {
    return StorageAdapter.prefs !== undefined;
  }
}
