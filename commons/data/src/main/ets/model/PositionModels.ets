import { TradeStatus } from './QuoteModels';

/**
 * 持仓与收益契约（M11-1 / AC-119~121）。
 *
 * 口径（逐条写在 `docs/phase2-position-metrics.md`）：
 * - 估值价：优先行情最新价；停牌/退市回落到「最近一次有效价」（持仓记录上的 `lastPrice`）；
 * - 成本口径 `withoutFee`：本地撮合按委托价成交、不计佣金与印花税，页面必须明示（AC-121）；
 * - 可卖数量沿用 M10 简化（持仓全可卖），T+1 冻结不在本期；
 * - 不处理除权除息。
 *
 * 与 `TradeProvider` 一样：这里只定义「消费」契约，盈亏公式在
 * `commons/data/rules/PositionRules.ets`（纯函数、可单测），不写进模型。
 */

/** 成本是否含交易费用（本期恒 `withoutFee`，字段留给接真实券商时只加不改）。 */
export type CostBasis = 'withFee' | 'withoutFee';

/** 单只持仓（Provider 每次按「持仓 + 行情快照」现算，不落盘、不缓存）。 */
export class Position {
  code: string;
  name: string;
  /** 持仓数量（股）。 */
  qty: number;
  /** 可卖数量（股；M11 简化 = qty）。 */
  available: number;
  /** 成本价（元/股）。 */
  costPrice: number;
  /** 估值价（元/股）；null 表示无有效价（页面显示 `--`，不计入市值合计）。 */
  last: number | null;
  /** 昨收（元/股）；停牌/退市为 null。用于当日盈亏与行情回推。 */
  prevClose: number | null;
  /** 市值（元）；无估值价时为 null。 */
  marketValue: number | null;
  /** 累计盈亏（元）；无估值价时为 null。 */
  pnl: number | null;
  /** 累计盈亏率（%）；成本额 ≤0 或无法估值时为 null。 */
  pnlRatio: number | null;
  /** 仓位占比（%）：个股市值 / 持仓总市值；无法估值时为 null。 */
  weight: number | null;
  /** 当日盈亏（元）：按昨收计算；停牌或昨收缺失时计 0。 */
  dayPnl: number | null;
  costBasis: CostBasis;
  /** 行情状态（停牌/退市用于页面标注）。 */
  status: TradeStatus;
  /** 所属账户（M11 单账户口径下仅用于展示与校验）。 */
  accountId: string;

  constructor(code: string, name: string, qty: number, available: number, costPrice: number,
    last: number | null, prevClose: number | null, marketValue: number | null, pnl: number | null,
    pnlRatio: number | null, weight: number | null, dayPnl: number | null, costBasis: CostBasis,
    status: TradeStatus, accountId: string) {
    this.code = code;
    this.name = name;
    this.qty = qty;
    this.available = available;
    this.costPrice = costPrice;
    this.last = last;
    this.prevClose = prevClose;
    this.marketValue = marketValue;
    this.pnl = pnl;
    this.pnlRatio = pnlRatio;
    this.weight = weight;
    this.dayPnl = dayPnl;
    this.costBasis = costBasis;
    this.status = status;
    this.accountId = accountId;
  }
}

/** 持仓汇总（页面顶部一条）。 */
export class PositionSummary {
  /** 总市值（元）：只累加有估值价的行。 */
  marketValue: number;
  /** 当日盈亏（元）。 */
  dayPnl: number;
  /** 累计盈亏（元）。 */
  totalPnl: number;
  /** 成本额合计（元）：含未估值行，便于对账。 */
  costTotal: number;
  /** 持仓只数。 */
  count: number;
  /** 未估值只数（停牌且无最近有效价）：页面提示「N 只未估值」。 */
  unvalued: number;

  constructor(marketValue: number, dayPnl: number, totalPnl: number, costTotal: number, count: number,
    unvalued: number) {
    this.marketValue = marketValue;
    this.dayPnl = dayPnl;
    this.totalPnl = totalPnl;
    this.costTotal = costTotal;
    this.count = count;
    this.unvalued = unvalued;
  }

  /** 累计盈亏率（%）；成本额 ≤0 时为 null（页面显示 `--`）。 */
  ratio(): number | null {
    if (this.costTotal <= 0) {
      return null;
    }
    return Math.round(this.totalPnl / this.costTotal * 10000) / 100;
  }
}

/** 持仓加载失败原因（上层按枚举映射文案，L2 不出现中文）。 */
export type PositionErrorReason = 'internal' | 'not_found';

/** 持仓加载失败。 */
export class PositionError extends Error {
  reason: PositionErrorReason;

  constructor(reason: PositionErrorReason, message: string) {
    super(message);
    this.reason = reason;
  }
}

/**
 * 持仓提供方（M11-1）。
 *
 * 契约 v1.1「只加不改」：
 * - `positions` / `summary` 的 `accountId` 为可选入参，缺省用主账户（账户列表第一个，
 *   与交易弹窗默认账户一致）；
 * - `positionOf` 为**可选**成员（详情页「已持有」用；缺失时调用方按 0 处理），
 *   与 `check-contracts.mjs` 的 `OPTIONAL_MEMBERS` 对齐；
 * - **不设 `subscribe`**：行情推送统一走 `QuoteBus`（M11-2「不新建通道」）。
 */
export interface PositionProvider {
  positions(accountId?: string): Promise<Position[]>;

  summary(accountId?: string): Promise<PositionSummary>;

  positionOf?(code: string): Promise<Position | null>;
}
