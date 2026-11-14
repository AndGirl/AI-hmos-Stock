import { hilog } from '@kit.PerformanceAnalysisKit';
import { ComplianceHost, PRIVACY_POLICY_VERSION } from 'commons_basic';
import { StorageAdapter } from './StorageAdapter';

const DOMAIN: number = 0x0001;
const TAG: string = 'Compliance';
const CONSENT_KEY: string = 'privacy_consent_v1';
const RISK_KEY: string = 'trade_risk_v1';

/** 落盘结构（只存布尔/字符串/时间戳，不存任何个人信息）。 */
class ConsentRecord {
  agreed: boolean = false;
  version: string = '';
  agreedAt: number = 0;

  constructor(agreed: boolean, version: string, agreedAt: number) {
    this.agreed = agreed;
    this.version = version;
    this.agreedAt = agreedAt;
  }
}

/**
 * 隐私同意（M13-1，计划 §5.5 `privacy_consent_v1`）：
 * - 唯一入口仍是 `StorageAdapter`（feature 不得直接 import preferences）；
 * - 同意后**立即写盘**（不合并写，杀进程也不重复弹）；
 * - 写盘成功后回灌 `ComplianceService`（首启门禁读它，`Index` 首帧前 await）；
 * - 策略版本不一致（文案实质性变更）视为未同意，重新弹一次。
 *
 * 读失败/未注入 context 时退化为「未同意」但不崩溃：内存副本仍生效。
 */
export class PrivacyConsentStore {
  private loading: Promise<void> | undefined = undefined;
  private loaded: boolean = false;
  private record: ConsentRecord = new ConsentRecord(false, '', 0);

  /** 幂等读盘：并发调用共用同一个 Promise（与 `ViewPrefStore` 同构）。 */
  load(): Promise<void> {
    if (this.loaded) {
      return Promise.resolve();
    }
    if (this.loading !== undefined) {
      return this.loading;
    }
    this.loading = this.doLoad();
    return this.loading;
  }

  isLoaded(): boolean {
    return this.loaded;
  }

  /** 当前策略版本下是否已同意（版本不一致按未同意处理）。 */
  consented(): boolean {
    return this.record.agreed && this.record.version === PRIVACY_POLICY_VERSION;
  }

  agreedAt(): number {
    return this.consented() ? this.record.agreedAt : 0;
  }

  /** 同意：写盘 + 回灌 UI 状态。 */
  async agree(): Promise<void> {
    const at: number = Date.now();
    this.record = new ConsentRecord(true, PRIVACY_POLICY_VERSION, at);
    this.loaded = true;
    this.sync();
    await StorageAdapter.putString(CONSENT_KEY, JSON.stringify(this.record));
    hilog.info(DOMAIN, TAG, 'consent_agree version=%{public}s agreedAt=%{public}d',
      PRIVACY_POLICY_VERSION, at);
  }

  /** 撤回同意：删键 + 回灌（下次启动重新弹）。 */
  async revoke(): Promise<void> {
    this.record = new ConsentRecord(false, '', 0);
    this.loaded = true;
    this.sync();
    await StorageAdapter.remove(CONSENT_KEY);
    hilog.info(DOMAIN, TAG, 'consent_revoke');
  }

  private async doLoad(): Promise<void> {
    try {
      const raw: string = await StorageAdapter.getString(CONSENT_KEY, '');
      this.record = PrivacyConsentStore.parse(raw);
    } catch (err) {
      this.record = new ConsentRecord(false, '', 0);
      hilog.warn(DOMAIN, TAG, 'consent_read_fail');
    }
    this.loaded = true;
    this.loading = undefined;
    this.sync();
    hilog.info(DOMAIN, TAG, 'consent_read agreed=%{public}s version=%{public}s',
      this.record.agreed ? 'true' : 'false', this.record.version);
  }

  /** 回灌 UI 可见状态（单测/无 UI 环境没有 AppStorageV2，失败只记日志不影响写盘）。 */
  private sync(): void {
    try {
      ComplianceHost.getService().applyConsent(this.record.agreed, this.record.version,
        this.record.agreedAt, PRIVACY_POLICY_VERSION);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'consent_sync_skip');
    }
  }

  /** 容错解析：坏 JSON/旧格式一律按未同意。 */
  static parse(raw: string): ConsentRecord {
    if (raw.length === 0) {
      return new ConsentRecord(false, '', 0);
    }
    try {
      const obj: ConsentRecord = JSON.parse(raw) as ConsentRecord;
      const agreed: boolean = obj.agreed === true;
      const version: string = typeof obj.version === 'string' ? obj.version : '';
      const at: number = typeof obj.agreedAt === 'number' && obj.agreedAt > 0 ? obj.agreedAt : 0;
      return new ConsentRecord(agreed, version, at);
    } catch (err) {
      return new ConsentRecord(false, '', 0);
    }
  }
}

/**
 * 首笔风险揭示（M13-1，收口 M10-7 遗留；计划 §5.5 `trade_risk_v1`）。
 * 只存一个布尔：首次提交委托前弹一次，勾「我已了解并继续」后不再弹。
 */
export class RiskNoticeStore {
  private loading: Promise<void> | undefined = undefined;
  private loaded: boolean = false;
  private ackedFlag: boolean = false;

  load(): Promise<void> {
    if (this.loaded) {
      return Promise.resolve();
    }
    if (this.loading !== undefined) {
      return this.loading;
    }
    this.loading = this.doLoad();
    return this.loading;
  }

  isLoaded(): boolean {
    return this.loaded;
  }

  acked(): boolean {
    return this.ackedFlag;
  }

  async ack(): Promise<void> {
    this.ackedFlag = true;
    this.loaded = true;
    await StorageAdapter.putString(RISK_KEY, 'true');
    hilog.info(DOMAIN, TAG, 'risk_ack');
  }

  /** 调试「重置风险提示」用（验收需要重放首笔场景）。 */
  async clear(): Promise<void> {
    this.ackedFlag = false;
    this.loaded = true;
    await StorageAdapter.remove(RISK_KEY);
    hilog.info(DOMAIN, TAG, 'risk_clear');
  }

  private async doLoad(): Promise<void> {
    try {
      const raw: string = await StorageAdapter.getString(RISK_KEY, 'false');
      this.ackedFlag = raw === 'true';
    } catch (err) {
      this.ackedFlag = false;
    }
    this.loaded = true;
    this.loading = undefined;
  }
}
