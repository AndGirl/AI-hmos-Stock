/** 市场与交易状态（设计 §4.2）。 */
export type Market = 'SH' | 'SZ' | 'BJ';

export type TradeStatus = 'pre' | 'auction' | 'open' | 'lunch' | 'closed' | 'suspended' | 'delisted';

export type ConnectionState = 'online' | 'offline' | 'delayed';

export type QuoteErrorReason = 'timeout' | 'offline' | 'rate_limited' | 'not_found' | 'internal';

/**
 * 行情快照（契约与真实同形，设计 §4.3）。
 * 价格类空值一律用 null，禁止用 0 / -1 代替；由 View 层渲染 `--`。
 */
export interface QuoteSnapshot {
  code: string;
  market: Market;
  name: string;
  status: TradeStatus;
  snapshotTime: number;
  isNew: boolean;
  last: number | null;
  prevClose: number | null;
  chg: number | null;
  pct: number | null;
  volume: number | null;
  lastVolume: number | null;
  amount: number | null;
  amplitude: number | null;
  turnover: number | null;
  pe: number | null;
  pb: number | null;
  /** M2 详情新增（列表不消费）：今开 / 最高 / 最低。 */
  open?: number | null;
  high?: number | null;
  low?: number | null;
  limitUp?: number | null;
  limitDown?: number | null;
  volumeRatio?: number | null;
  marketCap?: number | null;
  floatCap?: number | null;
}

/** 增量 patch：只带变化的字段，消费方按字段合并（设计 §4.4）。 */
export interface QuotePatch {
  code: string;
  snapshotTime: number;
  last?: number;
  chg?: number;
  pct?: number;
  volume?: number;
  lastVolume?: number;
  amount?: number;
  amplitude?: number;
  turnover?: number;
  pe?: number;
  pb?: number;
  status?: TradeStatus;
}

export interface QuoteError {
  code: string;
  reason: QuoteErrorReason;
}

export interface QuoteListener {
  onPatch(patch: QuotePatch): void;

  onStatus(state: ConnectionState): void;
}

/** 退订必须幂等（设计 §4.4）。 */
export interface QuoteSubscription {
  unsubscribe(): void;
}

/**
 * 行情提供方。M1 只用快照 + 推送；盘口/分笔/图表在 M2 扩展同一接口。
 */
export interface QuoteProvider {
  getSnapshots(codes: string[]): Promise<QuoteSnapshot[]>;

  subscribe(codes: string[], listener: QuoteListener): QuoteSubscription;
}
