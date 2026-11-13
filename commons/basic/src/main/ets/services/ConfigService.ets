import { AppStorageV2 } from '@kit.ArkUI';
import { normalizeViewMode, ViewMode } from '../constants/ViewModes';

/**
 * 系统配置（字号缩放 + 自选视图形态）。
 * 为什么单独做：表格的列宽必须与字号同比放大（1.45× 不减列，CC-6.5），
 * 页面拿不到 Activity 级 Configuration，由 EntryAbility 在启动/配置变更时写入。
 * M8-4：`viewMode` 是「首帧前的预热副本」——真值落盘在 `commons_data/ViewPrefStore`，
 * 冷启时由 EntryAbility 读出写入本字段，页面据此首帧即按卡片渲染（不出现先列表后卡片）。
 */
/** 当前生效的外观（M12-2）：由 EntryAbility 从系统 Configuration 写入，release 始终跟随系统。 */
export type ColorModeName = 'light' | 'dark';

@ObservedV2
export class ConfigService {
  @Trace fontScale: number = 1;
  @Trace viewMode: ViewMode = 'list';
  /** M12-2：图表等命令式绘制组件靠它感知深浅色切换（资源型颜色由系统自动重解析）。 */
  @Trace colorMode: ColorModeName = 'light';

  apply(fontScale: number): void {
    const clamped: number = Math.min(2, Math.max(0.8, fontScale));
    if (clamped !== this.fontScale) {
      this.fontScale = clamped;
    }
  }

  /** 写入系统深浅色（未知/未设置时按浅色兜底）。 */
  applyColorMode(mode: string): void {
    const normalized: ColorModeName = mode === 'dark' ? 'dark' : 'light';
    if (normalized !== this.colorMode) {
      this.colorMode = normalized;
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

  /** M12-2：系统深浅色写入（'dark' / 'light'）。 */
  static updateColorMode(mode: string | undefined): void {
    if (mode !== undefined) {
      ConfigHost.getService().applyColorMode(mode);
    }
  }
}
