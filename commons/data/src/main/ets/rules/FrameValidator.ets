import { QuotePatch, QuoteSnapshot } from '../model/QuoteModels';
import { priceInRange, priceWithinLimits } from './LimitRules';

/**
 * 增量帧校验（M9-5 / AC-110）。
 *
 * 目标：任何脏帧都**丢弃但不报错给用户**，只累计计数并随埋点上报 `quote_drop`；
 * 连续 `BAD_FRAME_RESUBSCRIBE_THRESHOLD` 帧异常时触发一次全量重订阅（防止通道错位后永久失真）。
 *
 * 五类判定：
 * - `stale_time`   snapshotTime 不晚于上一条 → 时间回退帧，丢弃；
 * - `price_invalid` 价格不在 [0.01, 100000] → 越界帧，丢弃；
 * - `price_out_of_limit` `last` 在涨跌停 ±2% 容差外 → 丢弃；
 * - `empty_frame`   patch 不含任何可变字段（只有 code/snapshotTime）→ 丢弃（防止空帧推进时间水位）；
 * - `ok`           接受。
 *
 * 只做判定，不写 UI；状态按 code 维护，`reset()` 用于切标的/重订阅。
 */

/** 连续异常帧达到此值触发一次全量重订阅（计划 M9-5 要点）。 */
export const BAD_FRAME_RESUBSCRIBE_THRESHOLD: number = 10;

export type FrameVerdict = 'ok' | 'stale_time' | 'price_invalid' | 'price_out_of_limit' | 'empty_frame';

/** 单个 code 的校验参考：涨跌停由快照给出（停牌/新股为空则跳过涨跌停判定）。 */
export class FrameReference {
  limitUp: number | null;
  limitDown: number | null;

  constructor(limitUp: number | null, limitDown: number | null) {
    this.limitUp = limitUp;
    this.limitDown = limitDown;
  }

  static fromSnapshot(snapshot: QuoteSnapshot | undefined): FrameReference {
    if (snapshot === undefined) {
      return new FrameReference(null, null);
    }
    const up: number | null = snapshot.limitUp !== undefined && snapshot.limitUp !== null ? snapshot.limitUp : null;
    const down: number | null =
      snapshot.limitDown !== undefined && snapshot.limitDown !== null ? snapshot.limitDown : null;
    return new FrameReference(up, down);
  }
}

class CodeState {
  lastTime: number = 0;
  consecutiveBad: number = 0;
}

/** 丢弃计数（随埋点上报；UI 不展示）。 */
export class FrameStats {
  staleTime: number = 0;
  priceInvalid: number = 0;
  priceOutOfLimit: number = 0;
  emptyFrame: number = 0;
  accepted: number = 0;

  dropped(): number {
    return this.staleTime + this.priceInvalid + this.priceOutOfLimit + this.emptyFrame;
  }

  /** 稳定串：`accepted=12 drop=3/stale=1,range=1,limit=1,empty=0`。 */
  describe(): string {
    return `accepted=${this.accepted} drop=${this.dropped()}/stale=${this.staleTime},` +
      `range=${this.priceInvalid},limit=${this.priceOutOfLimit},empty=${this.emptyFrame}`;
  }
}

export class FrameValidator {
  private states: Map<string, CodeState> = new Map<string, CodeState>();
  private stats: FrameStats = new FrameStats();

  /** 判定一帧；接受时推进该 code 的时间水位并清零连续异常计数。 */
  validate(patch: QuotePatch, reference: FrameReference): FrameVerdict {
    let state: CodeState | undefined = this.states.get(patch.code);
    if (state === undefined) {
      state = new CodeState();
      // 首帧不判时间单调（没有可比的前一条），但仍校验价格。
      state.lastTime = 0;
      this.states.set(patch.code, state);
    }
    if (!hasMutableField(patch)) {
      state.consecutiveBad++;
      this.stats.emptyFrame++;
      return 'empty_frame';
    }
    if (state.lastTime > 0 && patch.snapshotTime <= state.lastTime) {
      state.consecutiveBad++;
      this.stats.staleTime++;
      return 'stale_time';
    }
    if (patch.last !== undefined && !priceInRange(patch.last)) {
      state.consecutiveBad++;
      this.stats.priceInvalid++;
      return 'price_invalid';
    }
    if (patch.last !== undefined && !priceWithinLimits(patch.last, reference.limitUp, reference.limitDown)) {
      state.consecutiveBad++;
      this.stats.priceOutOfLimit++;
      return 'price_out_of_limit';
    }
    state.lastTime = patch.snapshotTime;
    state.consecutiveBad = 0;
    this.stats.accepted++;
    return 'ok';
  }

  /** 连续异常是否已达重订阅阈值（AC-110：连续 10 帧异常 → 全量重订阅一次）。 */
  shouldResubscribe(code: string): boolean {
    const state: CodeState | undefined = this.states.get(code);
    if (state === undefined) {
      return false;
    }
    return state.consecutiveBad >= BAD_FRAME_RESUBSCRIBE_THRESHOLD;
  }

  /** 取/清计数（清后不影响时间水位）。 */
  snapshotStats(): FrameStats {
    return this.stats;
  }

  resetStats(): void {
    this.stats = new FrameStats();
  }

  /** 切标的或重订阅后调用：清时间水位，让新通道的首帧不被误判为回退。 */
  resetCode(code: string): void {
    this.states.delete(code);
  }

  resetAll(): void {
    this.states.clear();
    this.stats = new FrameStats();
  }
}

/** patch 是否至少带一个可变行情字段（空帧只推进时间，没有信息量）。 */
export function hasMutableField(patch: QuotePatch): boolean {
  return patch.last !== undefined || patch.chg !== undefined || patch.pct !== undefined ||
    patch.volume !== undefined || patch.lastVolume !== undefined || patch.amount !== undefined ||
    patch.amplitude !== undefined || patch.turnover !== undefined || patch.pe !== undefined ||
    patch.pb !== undefined || patch.status !== undefined;
}
