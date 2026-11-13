import { AppStorageV2 } from '@kit.ArkUI';
import { normalizeViewMode, ViewMode } from '../constants/ViewModes';

/**
 * 系统配置（字号缩放 + 自选视图形态）。
 * 为什么单独做：表格的列宽必须与字号同比放大（1.45× 不减列，CC-6.5），
 * 页面拿不到 Activity 级 Configuration，由 EntryAbility 在启动/配置变更时写入。
 * M8-4：`viewMode` 是「首帧前的预热副本」——真值落盘在 `commons_data/ViewPrefStore`，
 * 冷启时由 EntryAbility 读出写入本字段，页面据此首帧即按卡片渲染（不出现先列表后卡片）。
 */
@ObservedV2
export class ConfigService {
  @Trace fontScale: number = 1;
  @Trace viewMode: ViewMode = 'list';

  apply(fontScale: number): void {
    const clamped: number = Math.min(2, Math.max(0.8, fontScale));
    if (clamped !== this.fontScale) {
      this.fontScale = clamped;
    }
  }

  /** 预热/同步视图形态（入参归一化，未知值退回列表）。 */
  applyViewMode(mode: string): void {
    const normalized: ViewMode = normalizeViewMode(mode);
    if (normalized !== this.viewMode) {
      this.viewMode = normalized;
    }
  }
}

export class ConfigHost {
  private static service: ConfigService | undefined = undefined;

  static getService(): ConfigService {
    if (ConfigHost.service === undefined) {
      const connected: ConfigService | undefined = AppStorageV2.connect(
        ConfigService,
        'config_service_v1',
        () => new ConfigService()
      );
      ConfigHost.service = connected !== undefined ? connected : new ConfigService();
    }
    return ConfigHost.service;
  }

  static update(fontScale: number | undefined): void {
    if (fontScale !== undefined) {
      ConfigHost.getService().apply(fontScale);
    }
  }
}
