/** 市场与交易状态（设计 §4.2）。 */
export type Market = 'SH' | 'SZ' | 'BJ';

export type TradeStatus = 'pre' | 'auction' | 'open' | 'lunch' | 'closed' | 'suspended' | 'delisted';

export type ConnectionState = 'online' | 'offline' | 'delayed';

/**
 * 行情错误原因。
 * M9-1（契约 v1.1，只加不改）：增 `unauthorized`——模拟鉴权票据失效且刷新一次仍失败时下发，
 * 上层据此进「未授权」态并停止重试，避免死循环。
 */
export type QuoteErrorReason =
  'timeout' | 'offline' | 'rate_limited' | 'not_found' | 'internal' | 'unauthorized';

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

/**
 * 增量 patch：只带变化的字段，消费方按字段合并（设计 §4.4）。
 * M9-1（契约 v1.1）：增可选 `seq`——乱序丢弃与 1s 合窗取最大 seq 的依据。
 * 缺省视为 0，此时不做序判定（Mock 直连与旧实现行为等价）。
 */
export interface QuotePatch {
  code: string;
  snapshotTime: number;
  seq?: number;
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

/** 行情错误体（M9-1 增可选 `retryAfterMs`：429 时通道建议的等待时长）。 */
export interface QuoteError {
  code: string;
  reason: QuoteErrorReason;
  retryAfterMs?: number;
}

export interface QuoteListener {
  onPatch(patch: QuotePatch): void;

  onStatus(state: ConnectionState): void;

  /**
   * M9-1 可选下行错误通道（现只有 onStatus）：限流 / 鉴权失败走这里。
   * 未实现者不受影响，通道侧必须判空后再调用。
   */
  onError?(error: QuoteError): void;
}

/** 退订必须幂等（设计 §4.4）。 */
export interface QuoteSubscription {
  unsubscribe(): void;
}

/**
 * 通道能力声明（M9-1，全字段布尔，不做三态）：
 * 供上层在能力缺失时降级（无推送退轮询、无盘口不渲染盘口），UI 不得直接调用。
 */
export interface QuoteCapabilities {
  /** 是否有增量推送；false 时只能快照轮询。 */
  push: boolean;
  /** 是否有五档盘口。 */
  orderBook: boolean;
  /** 是否有逐笔成交。 */
  ticks: boolean;
  /** 是否有 K 线/分时序列。 */
  chart: boolean;
  /** 是否可能下发 429（false 时不必展示降频提示）。 */
  rateLimit: boolean;
}

/**
 * 行情提供方。M1 只用快照 + 推送；盘口/分笔/图表在 M2 扩展同一接口。
 * M9-1（只加不改）：增可选 `capabilities()`。
 */
export interface QuoteProvider {
  getSnapshots(codes: string[]): Promise<QuoteSnapshot[]>;

  subscribe(codes: string[], listener: QuoteListener): QuoteSubscription;

  capabilities?(): QuoteCapabilities;
}
