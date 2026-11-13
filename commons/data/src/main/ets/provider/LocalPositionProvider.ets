import { QuoteProvider, QuoteSnapshot } from '../model/QuoteModels';
import {
  Position,
  PositionError,
  PositionProvider,
  PositionSummary
} from '../model/PositionModels';
import {
  applyWeights,
  computePosition,
  PositionBasis,
  sortPositions,
  summarizePositions
} from '../rules/PositionRules';
import { AccountRecord, HoldRecord, TradeAccountStore } from '../store/TradeAccountStore';
import { MockFaults } from '../mock/MockFaults';

/**
 * 本地持仓源（M11-1，替代计划里的 `MockPositionProvider`；命名与 M10 的 `LocalTradeProvider` 一致）。
 *
 * 口径：
 * - 数据来源只有两处：`trade_account_v1` 的持仓（数量/成本）与 `QuoteProvider` 的行情快照；
 * - **主账户**：`accountId` 缺省时取账户列表第一个（与交易弹窗默认账户一致）；
 * - 估值/盈亏全部走 `PositionRules` 纯函数，Provider 不重复实现公式；
 * - 停牌/退市快照无价时用持仓记录上的 `lastPrice`（最近一次有效价）估值，
 *   并在看到有效行情时顺手更新它（合并写盘，避免每次刷新都写）。
 */
export class LocalPositionProvider implements PositionProvider {
  private quotes: QuoteProvider;
  private accounts: TradeAccountStore;

  constructor(quotes: QuoteProvider, accounts: TradeAccountStore) {
    this.quotes = quotes;
    this.accounts = accounts;
  }

  async positions(accountId?: string): Promise<Position[]> {
    await this.accounts.load();
    if (MockFaults.failPositions) {
      throw new PositionError('internal', 'positions failed');
    }
    const record: AccountRecord | undefined = this.accounts.record(this.resolveAccount(accountId));
    if (record === undefined) {
      return [];
    }
    const holds: HoldRecord[] = record.holdings.filter((item: HoldRecord): boolean => item.qty > 0);
    if (holds.length === 0) {
      return [];
    }
    const codes: string[] = holds.map((item: HoldRecord): string => item.code);
    const snapshots: QuoteSnapshot[] = await this.quotes.getSnapshots(codes);
    const byCode: Map<string, QuoteSnapshot> = new Map<string, QuoteSnapshot>();
    for (let i = 0; i < snapshots.length; i++) {
      byCode.set(snapshots[i].code, snapshots[i]);
    }

    const rows: Position[] = [];
    let dirty: boolean = false;
    for (let i = 0; i < holds.length; i++) {
      const hold: HoldRecord = holds[i];
      const snapshot: QuoteSnapshot | undefined = byCode.get(hold.code);
      const last: number | null = snapshot !== undefined ? snapshot.last : null;
      if (last !== null && last > 0) {
        dirty = this.accounts.noteLastPrice(record.id, hold.code, last) || dirty;
      }
      const basis: PositionBasis = new PositionBasis(hold.code, snapshot !== undefined ? snapshot.name : hold.code,
        hold.qty, hold.qty, hold.costPrice, last, hold.lastPrice,
        snapshot !== undefined ? snapshot.prevClose : null,
        snapshot !== undefined ? snapshot.status : 'closed', record.id, 'withoutFee');
      rows.push(computePosition(basis));
    }
    applyWeights(rows);
    if (dirty) {
      await this.accounts.flush();
    }
    // 默认按市值降序：与券商持仓页一致，也让页面首次渲染就有稳定顺序。
    return sortPositions(rows, 'marketValue', 'desc');
  }

  async summary(accountId?: string): Promise<PositionSummary> {
    const rows: Position[] = await this.positions(accountId);
    return summarizePositions(rows);
  }

  /** 单标的持仓（详情页「已持有」；无持仓返回 null）。 */
  async positionOf(code: string): Promise<Position | null> {
    await this.accounts.load();
    if (MockFaults.failPositions) {
      throw new PositionError('internal', 'positions failed');
    }
    const record: AccountRecord | undefined = this.accounts.record(this.resolveAccount(''));
    if (record === undefined) {
      return null;
    }
    const holding: HoldRecord | undefined = this.accounts.holdingOf(record.id, code);
    if (holding === undefined || holding.qty <= 0) {
      return null;
    }
    const snapshots: QuoteSnapshot[] = await this.quotes.getSnapshots([code]);
    const snapshot: QuoteSnapshot | undefined = snapshots.length > 0 ? snapshots[0] : undefined;
    const last: number | null = snapshot !== undefined ? snapshot.last : null;
    if (last !== null && last > 0 && this.accounts.noteLastPrice(record.id, code, last)) {
      await this.accounts.flush();
    }
    const basis: PositionBasis = new PositionBasis(code, snapshot !== undefined ? snapshot.name : code,
      holding.qty, holding.qty, holding.costPrice, last, holding.lastPrice,
      snapshot !== undefined ? snapshot.prevClose : null,
      snapshot !== undefined ? snapshot.status : 'closed', record.id, 'withoutFee');
    // 单只没有「仓位占比」口径（weight 留 null），页面不展示该列。
    return computePosition(basis);
  }

  private resolveAccount(accountId?: string): string {
    if (accountId !== undefined && accountId.length > 0 && this.accounts.record(accountId) !== undefined) {
      return accountId;
    }
    return this.accounts.primaryId();
  }
}
