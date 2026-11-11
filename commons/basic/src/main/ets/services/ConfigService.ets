import { AppStorageV2 } from '@kit.ArkUI';

/**
 * 系统配置（字号缩放）。
 * 为什么单独做：表格的列宽必须与字号同比放大（1.45× 不减列，CC-6.5），
 * 页面拿不到 Activity 级 Configuration，由 EntryAbility 在启动/配置变更时写入。
 */
@ObservedV2
export class ConfigService {
  @Trace fontScale: number = 1;

  apply(fontScale: number): void {
    const clamped: number = Math.min(2, Math.max(0.8, fontScale));
    if (clamped !== this.fontScale) {
      this.fontScale = clamped;
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
