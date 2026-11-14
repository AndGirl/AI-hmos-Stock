import { AppStorageV2 } from '@kit.ArkUI';

/**
 * 隐私同意状态（M13-1）。
 *
 * 为什么放在 `commons_basic` 而不是 `commons_data`：
 * 首启门禁在 `Index`（entry）里，必须能在**首帧前**同步读到「是否已同意」；
 * 而真正的持久化在 `commons_data` 的 `PrivacyConsentStore`（唯一入口 `StorageAdapter`）。
 * 本类只做「UI 可见的状态镜像」，写盘由存储层完成后回灌（见 `applyConsent`），
 * 因此 commons_data 依赖 commons_basic（同 `normalizeViewMode` 的方向），不会反向。
 *
 * 只存布尔/时间戳，不存中文文案（文案走资源）。
 */
@ObservedV2
export class ComplianceService {
  /** 已读盘（未读盘前 UI 只渲染中性骨架，避免「先内容后弹窗」）。 */
  @Trace ready: boolean = false;
  /** 当前策略版本下是否已同意。 */
  @Trace consented: boolean = false;
  /** 同意时间（ms；未同意为 0）。 */
  @Trace agreedAt: number = 0;
  /** 同意时的策略版本（空串=未同意）。 */
  @Trace policyVersion: string = '';

  /**
   * 由存储层回灌（`PrivacyConsentStore.load/agree/revoke` 调用）。
   * `version` 与当前策略版本不一致时视为未同意（改版需重新同意）。
   */
  applyConsent(consented: boolean, version: string, agreedAt: number, currentVersion: string): void {
    const valid: boolean = consented && version === currentVersion;
    this.ready = true;
    this.consented = valid;
    this.agreedAt = valid ? agreedAt : 0;
    this.policyVersion = valid ? version : '';
  }

  /** 门禁判定：未读盘时按「未同意」处理，但 UI 用 `ready` 区分骨架。 */
  needsConsent(): boolean {
    return !this.consented;
  }
}

/** 全局唯一实例（与 ConnectionHub/QuoteHealth 同构）。 */
export class ComplianceHost {
  private static service: ComplianceService | undefined = undefined;

  static getService(): ComplianceService {
    if (ComplianceHost.service === undefined) {
      const connected: ComplianceService | undefined = AppStorageV2.connect(
        ComplianceService,
        'compliance_service_v1',
        () => new ComplianceService()
      );
      ComplianceHost.service = connected !== undefined ? connected : new ComplianceService();
    }
    return ComplianceHost.service;
  }
}
