import { PersistenceV2 } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0001;
const TAG: string = 'PkLog';

/** 持久化载体：只用基本类型（字符串/数字），避免嵌套对象序列化差异（设计 §5.5.5）。 */
@ObservedV2
export class PkPersist {
  /** 有序标的，逗号分隔（窗序即顺序）。 */
  @Trace codes: string = '';
  /** 与 codes 对齐的周期，逗号分隔；缺省位为空串。 */
  @Trace periods: string = '';
  @Trace focus: number = 0;
  @Trace savedAt: number = 0;
}

/** 恢复用快照（纯数据，不含行情）。 */
export class PkSavedGroup {
  codes: string[] = [];
  periods: string[] = [];
  focus: number = 0;
  savedAt: number = 0;

  /** 至少 2 只且不重复才算可用组合（DEC-08-03 / 恢复失败降级单窗）。 */
  usable(): boolean {
    if (this.codes.length < 2 || this.codes.length > 3) {
      return false;
    }
    const seen: Set<string> = new Set<string>();
    for (let i = 0; i < this.codes.length; i++) {
      const code: string = this.codes[i];
      if (code.length !== 6 || seen.has(code)) {
        return false;
      }
      seen.add(code);
    }
    return this.focus >= 0 && this.focus < this.codes.length;
  }

  periodOf(code: string): string {
    for (let i = 0; i < this.codes.length; i++) {
      if (this.codes[i] === code) {
        return i < this.periods.length ? this.periods[i] : '';
      }
    }
    return '';
  }
}

/**
 * PK 组合持久化（FR-08.8 / DEC-08-05）：只保留最后 1 组 `{ codes, periods, focus }`。
 * 失败降级：读写异常时退化为内存单例，不阻塞 PK 使用（不写行情数据）。
 */
export class PkStore {
  private static instance: PkStore | null = null;
  private memory: PkPersist = new PkPersist();
  private disk: PkPersist | undefined = undefined;
  private diskTried: boolean = false;

  static get(): PkStore {
    if (PkStore.instance === null) {
      PkStore.instance = new PkStore();
    }
    return PkStore.instance;
  }

  private carrier(): PkPersist {
    if (!this.diskTried) {
      this.diskTried = true;
      try {
        const connected: PkPersist | undefined = PersistenceV2.connect(PkPersist,
          (): PkPersist => new PkPersist());
        if (connected !== undefined) {
          this.disk = connected;
        }
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'pk_store_connect_fail');
      }
    }
    return this.disk !== undefined ? this.disk : this.memory;
  }

  save(codes: string[], periods: string[], focus: number): void {
    const carrier: PkPersist = this.carrier();
    carrier.codes = codes.join(',');
    carrier.periods = periods.join(',');
    carrier.focus = focus;
    carrier.savedAt = Date.now();
    try {
      PersistenceV2.save(PkPersist);
    } catch (err) {
      // 落盘失败不影响本次会话（内存态已更新）。
    }
    hilog.info(DOMAIN, TAG, 'pk_persist codes=%{public}s focus=%{public}d',
      carrier.codes, carrier.focus);
  }

  load(): PkSavedGroup {
    const carrier: PkPersist = this.carrier();
    const group: PkSavedGroup = new PkSavedGroup();
    group.codes = splitCodes(carrier.codes);
    group.periods = splitCodes(carrier.periods);
    group.focus = carrier.focus;
    group.savedAt = carrier.savedAt;
    return group;
  }

  /** 按 code 取上次周期（换股/重进 PK 时沿用），无记录返回 ''。 */
  periodOf(code: string): string {
    return this.load().periodOf(code);
  }

  clear(): void {
    const carrier: PkPersist = this.carrier();
    carrier.codes = '';
    carrier.periods = '';
    carrier.focus = 0;
    carrier.savedAt = 0;
    try {
      PersistenceV2.save(PkPersist);
    } catch (err) {
      // 同上。
    }
    hilog.info(DOMAIN, TAG, 'pk_persist_clear');
  }
}

function splitCodes(text: string): string[] {
  if (text.length === 0) {
    return [];
  }
  return text.split(',');
}
