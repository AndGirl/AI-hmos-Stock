/**
 * 涨跌停规则（M9-5 / AC-110，CK-10 口径）。
 *
 * 为什么必须做：模拟数据也必须是「合法的行情」，否则详情页涨跌停、委托价格上限、
 * 卡片与列表的极值展示会互相矛盾。原实现一律 10%（`MockQuoteProvider.LIMIT_RATIO`），
 * 与创业板/科创板/北交所的板块规则不符。
 *
 * 口径：
 * - 板块比例：主板 10%、ST 5%、科创板 20%、创业板 20%、北交所 30%；
 * - 服务端（此处为通道/后端）下发优先：`resolveLimits` 有值即用，缺失才按规则推导；
 * - 价格两位小数（与交易侧 round2 同口径），空/非正值返回 null（渲染 `--`）。
 */

/** 板块类型：主板 / 科创板 / 创业板 / 北交所。 */
export type BoardKind = 'main' | 'star' | 'chinext' | 'bse';

/** 各板块涨跌停比例（小数）。 */
export const LIMIT_RATIO_MAIN: number = 0.10;
export const LIMIT_RATIO_ST: number = 0.05;
export const LIMIT_RATIO_STAR: number = 0.20;
export const LIMIT_RATIO_CHINEXT: number = 0.20;
export const LIMIT_RATIO_BSE: number = 0.30;

/** 价格区间（AC-110）：低于 0.01 或高于 10 万视为异常帧。 */
export const PRICE_MIN: number = 0.01;
export const PRICE_MAX: number = 100000;

/** 涨跌停容差（AC-110）：`last` 落在 ±2% 容差外视为异常帧。 */
export const LIMIT_TOLERANCE_RATIO: number = 0.02;

export function round2(value: number): number {
  return Math.round(value * 100) / 100;
}

/**
 * 按代码前缀判板块：
 * - 688 → 科创板；
 * - 300/301 → 创业板；
 * - 8xx/43x/83x/87x/920 → 北交所；
 * - 其余（600/601/603/605/000/001/002/003 等）→ 主板。
 */
export function boardOf(code: string): BoardKind {
  if (code.startsWith('688')) {
    return 'star';
  }
  if (code.startsWith('300') || code.startsWith('301')) {
    return 'chinext';
  }
  if (code.startsWith('920')) {
    return 'bse';
  }
  if (code.startsWith('8') || code.startsWith('43') || code.startsWith('83') || code.startsWith('87')) {
    return 'bse';
  }
  return 'main';
}

/** 名称含 ST（含 *ST / SST）按 5%。大小写与全角星号都接受。 */
export function isStName(name: string | undefined): boolean {
  if (name === undefined || name.length === 0) {
    return false;
  }
  return name.toUpperCase().indexOf('ST') >= 0;
}

/** 板块 + 名称 → 涨跌停比例。 */
export function limitRatioOf(code: string, name?: string): number {
  const board: BoardKind = boardOf(code);
  if (board === 'bse') {
    return LIMIT_RATIO_BSE;
  }
  if (board === 'star') {
    return LIMIT_RATIO_STAR;
  }
  if (board === 'chinext') {
    return LIMIT_RATIO_CHINEXT;
  }
  return isStName(name) ? LIMIT_RATIO_ST : LIMIT_RATIO_MAIN;
}

/** 由昨收推导涨停价；prevClose 为空/非正返回 null。 */
export function deriveLimitUp(prevClose: number | null, code: string, name?: string): number | null {
  if (prevClose === null || !(prevClose > 0)) {
    return null;
  }
  return round2(prevClose * (1 + limitRatioOf(code, name)));
}

/** 由昨收推导跌停价；prevClose 为空/非正返回 null。 */
export function deriveLimitDown(prevClose: number | null, code: string, name?: string): number | null {
  if (prevClose === null || !(prevClose > 0)) {
    return null;
  }
  return round2(prevClose * (1 - limitRatioOf(code, name)));
}

/** 一对涨跌停价。 */
export class LimitPair {
  limitUp: number | null;
  limitDown: number | null;

  constructor(limitUp: number | null, limitDown: number | null) {
    this.limitUp = limitUp;
    this.limitDown = limitDown;
  }
}

/**
 * 服务端下发优先，缺失才推导（CK-10）：
 * 只要下发值为正数就直接采用，不做二次修正（服务端与本地规则不一致时以服务端为准）。
 */
export function resolveLimits(prevClose: number | null, code: string, name: string | undefined,
  serverLimitUp: number | null | undefined, serverLimitDown: number | null | undefined): LimitPair {
  const up: number | null = serverLimitUp !== null && serverLimitUp !== undefined && serverLimitUp > 0 ?
    round2(serverLimitUp) : deriveLimitUp(prevClose, code, name);
  const down: number | null = serverLimitDown !== null && serverLimitDown !== undefined && serverLimitDown > 0 ?
    round2(serverLimitDown) : deriveLimitDown(prevClose, code, name);
  return new LimitPair(up, down);
}

/** 价是否在 [0.01, 100000]（AC-110 价格区间校验）。 */
export function priceInRange(price: number | null | undefined): boolean {
  if (price === null || price === undefined) {
    return false;
  }
  return price >= PRICE_MIN && price <= PRICE_MAX;
}

/**
 * 价是否落在涨跌停容差内（AC-110）：区间外扩 `tolerance` 后判定。
 * 涨跌停任一为空时只判价格区间，不做涨跌停判定（停牌/新股无涨跌停）。
 */
export function priceWithinLimits(price: number | null | undefined, limitUp: number | null,
  limitDown: number | null, tolerance: number = LIMIT_TOLERANCE_RATIO): boolean {
  if (!priceInRange(price)) {
    return false;
  }
  const value: number = price as number;
  if (limitUp !== null && value > limitUp * (1 + tolerance)) {
    return false;
  }
  if (limitDown !== null && value < limitDown * (1 - tolerance)) {
    return false;
  }
  return true;
}
