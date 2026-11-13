import { hilog } from '@kit.PerformanceAnalysisKit';
import { normalizeViewMode, ViewMode } from 'commons_basic';
import { StorageAdapter } from './StorageAdapter';

const DOMAIN: number = 0x0001;
const TAG: string = 'ViewPref';
const VIEW_PREF_KEY: string = 'view_pref_v1';

/**
 * 自选视图偏好（M8-4，计划 §5.5 `view_pref_v1`）：
 * - 只存一个键（`list` / `card`），切换后**立即写盘**（不合并写，避免杀进程丢偏好）；
 * - 唯一入口仍是 `StorageAdapter`（feature 不得直接 import preferences）；
 * - 冷启由 `EntryAbility` 预读并写入 `ConfigService.viewMode`；页面在出内容前会 await 本类，
 *   因此首帧要么骨架、要么正确的视图，不会「先列表后卡片」。
 */
export class ViewPrefStore {
  private mode: ViewMode = 'list';
  private ready: boolean = false;
  private loading: Promise<void> | undefined = undefined;

  /** 幂等读盘：并发调用共用同一个 Promise。 */
  load(): Promise<void> {
    if (this.ready) {
      return Promise.resolve();
    }
    if (this.loading !== undefined) {
      return this.loading;
    }
    this.loading = this.doLoad();
    return this.loading;
  }

  isReady(): boolean {
    return this.ready;
  }

  /** 当前形态（未读盘时返回列表，调用方应先 await load()）。 */
  current(): ViewMode {
    return this.mode;
  }

  /** 切换后立即落盘（写失败静默，内存副本仍生效）。 */
  async setMode(mode: ViewMode): Promise<void> {
    const next: ViewMode = normalizeViewMode(mode);
    this.mode = next;
    this.ready = true;
    await StorageAdapter.putString(VIEW_PREF_KEY, next);
    hilog.info(DOMAIN, TAG, 'view_mode_write mode=%{public}s', next);
  }

  /** 调试「清除视图记忆」用：删键并回默认列表。 */
  async clear(): Promise<void> {
    this.mode = 'list';
    this.ready = true;
    await StorageAdapter.remove(VIEW_PREF_KEY);
    hilog.info(DOMAIN, TAG, 'view_mode_clear');
  }

  private async doLoad(): Promise<void> {
    try {
      const raw: string = await StorageAdapter.getString(VIEW_PREF_KEY, '');
      this.mode = normalizeViewMode(raw);
    } catch (err) {
      // 读失败回默认值，不阻塞首帧（写失败仍保留内存副本）。
      this.mode = 'list';
      hilog.warn(DOMAIN, TAG, 'view_mode_read_fail');
    }
    this.ready = true;
    this.loading = undefined;
    hilog.info(DOMAIN, TAG, 'view_mode_read mode=%{public}s', this.mode);
  }
}
