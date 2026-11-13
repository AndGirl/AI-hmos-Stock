import { AccountInfo, OrderSide } from '../model/TradeModels';
import { StorageAdapter } from './StorageAdapter';
import { buildAccounts } from '../mock/TradeSeeds';
import { round2 } from '../rules/MatchingRules';

const KEY: string = 'trade_account_v1';
const WRITE_MERGE_MS: number = 200;
/** 首次初始化可用资金（元）：够买 A 股主流标的，便于演示。 */
export const DEFAULT_CASH: number = 500000;

/** 持仓（纯数据类，不要加方法：JSON 还原后方法会丢）。 */
export class HoldRecord {
  code: string;
  qty: number;
  costPrice: number;
  /**
   * 最近一次有效价（M11 新增）：停牌/退市行情快照无价时用它估值。
   * 旧版本 JSON 没有该字段，还原时回落成本价（见 `restore`）。
   */
  lastPrice: number;

  constructor(code: string, qty: number, costPrice: number, lastPrice?: number) {
    this.code = code;
    this.qty = qty;
    this.costPrice = costPrice;
    this.lastPrice = lastPrice !== undefined && lastPrice > 0 ? lastPrice : costPrice;
  }
}

/** 单账户（纯数据类）。 */
export class AccountRecord {
  id: string;
  maskNo: string;
  /** 现金总额（含被委托冻结的部分）。 */
  cash: number;
  /** 买单冻结金额。 */
  frozen: number;
  opened: boolean;
  holdings: HoldRecord[] = [];

  constructor(id: string, maskNo: string, cash: number, frozen: number, opened: boolean) {
    this.id = id;
    this.maskNo = maskNo;
    this.cash = cash;
    this.frozen = frozen;
    this.opened = opened;
  }
}

class AccountDoc {
  version: number = 1;
  accounts: AccountRecord[] = [];
}

/**
 * 交易账户与持仓（M10-2 / AC-117，`trade_account_v1`）。
 *
 * 为什么单独一个 store：M10 要验「成交后持仓与可买刷新」，而 M11 的持仓页也要读同一份数据。
 * 这里先落**最小口径**：现金（含冻结）、持仓（数量 + 成本价），不做当日盈亏/市值（M11 再算）。
 *
 * 口径：
 * - `available = cash - frozen`（挂单买入冻结，成交/撤单释放）；
 * - 首次初始化按 `buildAccounts()` 的两个账户建记录（保留「切账户重算可买」的既有验收）；
 * - 全部走 `StorageAdapter`（唯一存储入口），200ms 合并写。
 */
export class TradeAccountStore {
  private accounts: AccountRecord[] = [];
  private loaded: boolean = false;
  private loading: Promise<void> | undefined = undefined;
  private writeTimer: number = -1;
  private dirty: boolean = false;

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
        const doc: AccountDoc = JSON.parse(raw) as AccountDoc;
        const items: AccountRecord[] = doc.accounts !== undefined && doc.accounts !== null ? doc.accounts : [];
        this.accounts = this.restore(items);
      }
    } catch (err) {
      // 读失败回默认（首次初始化），不阻塞弹窗。
    }
    if (this.accounts.length === 0) {
      this.accounts = this.seed();
    }
    this.loaded = true;
  }

  private restore(items: AccountRecord[]): AccountRecord[] {
    const result: AccountRecord[] = [];
    for (let i = 0; i < items.length; i++) {
      const item: AccountRecord = items[i];
      if (item === null || item.id === undefined) {
        continue;
      }
      const record: AccountRecord = new AccountRecord(item.id, item.maskNo, item.cash, item.frozen, item.opened);
      const holds: HoldRecord[] = item.holdings !== undefined && item.holdings !== null ? item.holdings : [];
      for (let j = 0; j < holds.length; j++) {
        // 旧版本没有 lastPrice：回落成本价，停牌估值不会变成 0。
        const raw: HoldRecord = holds[j];
        const last: number = raw.lastPrice !== undefined && raw.lastPrice > 0 ? raw.lastPrice : raw.costPrice;
        record.holdings.push(new HoldRecord(raw.code, raw.qty, raw.costPrice, last));
      }
      result.push(record);
    }
    return result;
  }

  private seed(): AccountRecord[] {
    const seeds: AccountInfo[] = buildAccounts();
    const result: AccountRecord[] = [];
    for (let i = 0; i < seeds.length; i++) {
      const seed: AccountInfo = seeds[i];
      const record: AccountRecord =
        new AccountRecord(seed.id, seed.maskNo, seed.available, 0, seed.opened);
      if (seed.holdQty > 0) {
        // 种子持仓没有成本价：按一次「历史买入」给个确定值，避免 0 成本导致收益率除零。
        // M11：`lastPrice` 给一个确定的有效价，停牌时估值可用。
        record.holdings.push(new HoldRecord('600519', seed.holdQty, 1500, 1680));
      }
      // M11-1：主账户给 3 只样例持仓，持仓页冷启即有内容，且盈亏有正有负便于验排序/合计。
      // 代码避开 M10 单测用到的 000001 / 600519。
      if (i === 0) {
        record.holdings.push(new HoldRecord('601318', 1000, 45, 48.9));
        record.holdings.push(new HoldRecord('000858', 200, 150, 142.8));
        record.holdings.push(new HoldRecord('600036', 300, 30, 34.6));
      }
      result.push(record);
    }
    return result;
  }

  /** 主账户 id：账户列表第一个（与交易弹窗默认账户一致；持仓页只展示主账户）。 */
  primaryId(): string {
    return this.accounts.length > 0 ? this.accounts[0].id : '';
  }

  /**
   * 记录最近一次有效价（M11：停牌估值的兜底）。
   * 返回是否发生变化（避免每次刷新都写盘）。
   */
  noteLastPrice(accountId: string, code: string, price: number): boolean {
    if (!Number.isFinite(price) || price <= 0) {
      return false;
    }
    const holding: HoldRecord | undefined = this.holdingOf(accountId, code);
    if (holding === undefined) {
      return false;
    }
    if (holding.lastPrice === price) {
      return false;
    }
    holding.lastPrice = price;
    this.markDirty();
    return true;
  }

  ready(): boolean {
    return this.loaded;
  }

  ids(): string[] {
    const result: string[] = [];
    for (let i = 0; i < this.accounts.length; i++) {
      result.push(this.accounts[i].id);
    }
    return result;
  }

  records(): AccountRecord[] {
    return this.accounts;
  }

  record(id: string): AccountRecord | undefined {
    for (let i = 0; i < this.accounts.length; i++) {
      if (this.accounts[i].id === id) {
        return this.accounts[i];
      }
    }
    return undefined;
  }

  /** 组装对外 `AccountInfo`（available 已扣冻结）。 */
  infos(): AccountInfo[] {
    const result: AccountInfo[] = [];
    for (let i = 0; i < this.accounts.length; i++) {
      const record: AccountRecord = this.accounts[i];
      let holdQty: number = 0;
      for (let j = 0; j < record.holdings.length; j++) {
        holdQty += record.holdings[j].qty;
      }
      result.push(new AccountInfo(record.id, record.maskNo, this.availableOf(record.id), holdQty,
        record.opened, true, this.sellableOf(record.id)));
    }
    return result;
  }

  availableOf(id: string): number {
    const record: AccountRecord | undefined = this.record(id);
    if (record === undefined) {
      return 0;
    }
    return round2(Math.max(0, record.cash - record.frozen));
  }

  /** 可卖数量（M10 简化：持仓全可卖；T+1 在 M11 细化）。 */
  sellableOf(id: string): number {
    const record: AccountRecord | undefined = this.record(id);
    if (record === undefined) {
      return 0;
    }
    let qty: number = 0;
    for (let i = 0; i < record.holdings.length; i++) {
      qty += record.holdings[i].qty;
    }
    return qty;
  }

  holdingOf(id: string, code: string): HoldRecord | undefined {
    const record: AccountRecord | undefined = this.record(id);
    if (record === undefined) {
      return undefined;
    }
    for (let i = 0; i < record.holdings.length; i++) {
      if (record.holdings[i].code === code) {
        return record.holdings[i];
      }
    }
    return undefined;
  }

  /** 本地开户（M10-1）：把 `opened` 置真并落盘。 */
  async open(id: string): Promise<boolean> {
    await this.load();
    const record: AccountRecord | undefined = this.record(id);
    if (record === undefined) {
      return false;
    }
    record.opened = true;
    this.markDirty();
    return true;
  }

  /** 调试：模拟「未开户」/恢复。 */
  async setOpened(id: string, opened: boolean): Promise<void> {
    await this.load();
    const record: AccountRecord | undefined = this.record(id);
    if (record === undefined) {
      return;
    }
    record.opened = opened;
    this.markDirty();
    await this.flush();
  }

  /** 买单冻结。 */
  async freeze(id: string, amount: number): Promise<void> {
    await this.load();
    const record: AccountRecord | undefined = this.record(id);
    if (record === undefined || amount <= 0) {
      return;
    }
    record.frozen = round2(record.frozen + amount);
    this.markDirty();
  }

  /** 释放冻结（撤单/部分成交）。 */
  async unfreeze(id: string, amount: number): Promise<void> {
    await this.load();
    const record: AccountRecord | undefined = this.record(id);
    if (record === undefined || amount <= 0) {
      return;
    }
    record.frozen = round2(Math.max(0, record.frozen - amount));
    this.markDirty();
  }

  /** 成交记账：买 → 扣现金、增持仓（加权成本）；卖 → 增现金、减持仓。 */
  async applyFill(id: string, side: OrderSide, code: string, price: number, qty: number): Promise<void> {
    await this.load();
    const record: AccountRecord | undefined = this.record(id);
    if (record === undefined || qty <= 0) {
      return;
    }
    const amount: number = round2(price * qty);
    if (side === 'buy') {
      record.cash = round2(Math.max(0, record.cash - amount));
      const holding: HoldRecord | undefined = this.holdingOf(id, code);
      if (holding === undefined) {
        record.holdings.push(new HoldRecord(code, qty, price, price));
      } else {
        const totalCost: number = holding.costPrice * holding.qty + amount;
        const totalQty: number = holding.qty + qty;
        holding.costPrice = totalQty > 0 ? round2(totalCost / totalQty) : price;
        holding.qty = totalQty;
        holding.lastPrice = price;
      }
    } else {
      record.cash = round2(record.cash + amount);
      const holding: HoldRecord | undefined = this.holdingOf(id, code);
      if (holding !== undefined) {
        holding.qty = Math.max(0, holding.qty - qty);
        holding.lastPrice = price;
        if (holding.qty === 0) {
          record.holdings = record.holdings.filter((item: HoldRecord): boolean => item.code !== code);
        }
      }
    }
    this.markDirty();
  }

  /** 调试「重置账户」：回到种子状态（现金/持仓/开户标记）。 */
  async resetAll(): Promise<void> {
    await this.load();
    this.accounts = this.seed();
    this.markDirty();
    await this.flush();
  }

  /** 调试（M11）：清空持仓并立即落盘（验持仓页空态；现金不变）。 */
  async clearHoldings(accountId?: string): Promise<void> {
    await this.load();
    if (accountId !== undefined && accountId.length > 0) {
      const record: AccountRecord | undefined = this.record(accountId);
      if (record !== undefined) {
        record.holdings = [];
        this.markDirty();
      }
    } else {
      for (let i = 0; i < this.accounts.length; i++) {
        this.accounts[i].holdings = [];
      }
      this.markDirty();
    }
    await this.flush();
  }

  async flush(): Promise<void> {
    this.clearTimer();
    if (!this.dirty) {
      return;
    }
    this.dirty = false;
    const doc: AccountDoc = new AccountDoc();
    doc.accounts = this.accounts;
    await StorageAdapter.putString(KEY, JSON.stringify(doc));
  }

  private markDirty(): void {
    this.dirty = true;
    if (this.writeTimer !== -1) {
      return;
    }
    this.writeTimer = setTimeout((): void => {
      this.writeTimer = -1;
      this.flush().catch((): void => {
      });
    }, WRITE_MERGE_MS);
  }

  private clearTimer(): void {
    if (this.writeTimer !== -1) {
      clearTimeout(this.writeTimer);
      this.writeTimer = -1;
    }
  }
}
