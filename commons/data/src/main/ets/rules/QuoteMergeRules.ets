import { QuotePatch, TradeStatus } from '../model/QuoteModels';

/**
 * 增量帧合并与序号判定（M9-3 / AC-108）。
 *
 * 为什么放在纯函数层：1s 合窗与乱序丢弃是「一帧都不许错」的逻辑，
 * 只有纯函数才能在 Local Test 里穷举乱序/重复/跳帧组合（AC-108 要求单测）。
 *
 * 序号口径（契约 v1.1）：
 * - `seq` 缺省或 0 → 不做序判定（兼容旧实现与 Mock 直连），永远接受；
 * - `seq` > 已收最大 → 接受并更新水位；
 * - `seq` === 已收最大 → 重复帧，丢弃；
 * - `seq` < 已收最大 → 乱序（迟到）帧，丢弃且不进 UI。
 */

/** 缺省序号（契约：缺省视为 0）。 */
export const SEQ_NONE: number = 0;

/** 帧判定结果。 */
export type SeqVerdict = 'accept' | 'duplicate' | 'out_of_order' | 'unsequenced';

export class SeqDecision {
  verdict: SeqVerdict;
  /** 判定后应写回的水位（丢弃时不变）。 */
  nextSeq: number;

  constructor(verdict: SeqVerdict, nextSeq: number) {
    this.verdict = verdict;
    this.nextSeq = nextSeq;
  }

  accepted(): boolean {
    return this.verdict === 'accept' || this.verdict === 'unsequenced';
  }
}

/** 依据已收水位判定本帧；纯函数，不持有状态。 */
export function decideSeq(lastSeq: number, patchSeq: number | undefined): SeqDecision {
  if (patchSeq === undefined || patchSeq <= SEQ_NONE) {
    return new SeqDecision('unsequenced', lastSeq);
  }
  if (patchSeq === lastSeq) {
    return new SeqDecision('duplicate', lastSeq);
  }
  if (patchSeq < lastSeq) {
    return new SeqDecision('out_of_order', lastSeq);
  }
  return new SeqDecision('accept', patchSeq);
}

/** 取帧序号（缺省 0）。 */
export function seqOf(patch: QuotePatch): number {
  return patch.seq !== undefined ? patch.seq : SEQ_NONE;
}

/**
 * 合并同一 code 在 1s 窗口内的多帧：字段级「后到者优先」，
 * `seq` 取两者最大（AC-108「1s 合窗取最大 seq 的合并结果」）。
 * 未定义的字段不覆盖已有值（AC-110「空值不覆盖」）。
 */
export function mergePatch(base: QuotePatch, next: QuotePatch): QuotePatch {
  const merged: QuotePatch = {
    code: base.code,
    snapshotTime: next.snapshotTime,
    seq: Math.max(seqOf(base), seqOf(next))
  };
  merged.last = next.last !== undefined ? next.last : base.last;
  merged.chg = next.chg !== undefined ? next.chg : base.chg;
  merged.pct = next.pct !== undefined ? next.pct : base.pct;
  merged.volume = next.volume !== undefined ? next.volume : base.volume;
  merged.lastVolume = next.lastVolume !== undefined ? next.lastVolume : base.lastVolume;
  merged.amount = next.amount !== undefined ? next.amount : base.amount;
  merged.amplitude = next.amplitude !== undefined ? next.amplitude : base.amplitude;
  merged.turnover = next.turnover !== undefined ? next.turnover : base.turnover;
  merged.pe = next.pe !== undefined ? next.pe : base.pe;
  merged.pb = next.pb !== undefined ? next.pb : base.pb;
  merged.status = next.status !== undefined ? next.status : base.status;
  return merged;
}

/**
 * 把 patch 合进快照（单行刷新）：只写 patch 里出现过的字段，
 * 避免「空值把已有价格抹成 null」。
 */
export function applyPatch(snapshot: QuoteSnapshotLike, patch: QuotePatch): void {
  if (patch.last !== undefined) {
    snapshot.last = patch.last;
  }
  if (patch.chg !== undefined) {
    snapshot.chg = patch.chg;
  }
  if (patch.pct !== undefined) {
    snapshot.pct = patch.pct;
  }
  if (patch.volume !== undefined) {
    snapshot.volume = patch.volume;
  }
  if (patch.lastVolume !== undefined) {
    snapshot.lastVolume = patch.lastVolume;
  }
  if (patch.amount !== undefined) {
    snapshot.amount = patch.amount;
  }
  if (patch.amplitude !== undefined) {
    snapshot.amplitude = patch.amplitude;
  }
  if (patch.turnover !== undefined) {
    snapshot.turnover = patch.turnover;
  }
  if (patch.pe !== undefined) {
    snapshot.pe = patch.pe;
  }
  if (patch.pb !== undefined) {
    snapshot.pb = patch.pb;
  }
  if (patch.status !== undefined) {
    snapshot.status = patch.status;
  }
  snapshot.snapshotTime = patch.snapshotTime;
}

/**
 * 可被 patch 就地更新的行情字段子集。
 * 用最小结构而不是 `QuoteSnapshot`，避免纯函数层反向依赖完整快照与 Market/名称等不变字段。
 */
export interface QuoteSnapshotLike {
  snapshotTime: number;
  status: TradeStatus;
  last: number | null;
  chg: number | null;
  pct: number | null;
  volume: number | null;
  lastVolume: number | null;
  amount: number | null;
  amplitude: number | null;
  turnover: number | null;
  pe: number | null;
  pb: number | null;
}
