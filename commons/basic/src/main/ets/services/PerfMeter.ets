import { FrameCallback, UIContext } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'PerfMeter';
const JANK_MS: number = 25;
const WINDOW_MS: number = 1000;

class MeterCallback extends FrameCallback {
  private handler: (ns: number) => void;

  constructor(handler: (ns: number) => void) {
    super();
    this.handler = handler;
  }

  onFrame(frameTimeInNano: number): void {
    this.handler(frameTimeInNano);
  }
}

/**
 * 帧率探针（设计 §5.6.6）：`postFrameCallback` 逐帧串联，1s 窗口打点。
 * 仅在 debug 构建通过调试面板开启；release 不调用（调用方以 BuildProfile.DEBUG 判定）。
 * 日志：`PERF_START` / `PERF_WIN` / `PERF_STOP`，可用 `hilog | grep PerfMeter` 采集。
 */
export class PerfMeter {
  private static ui: UIContext | undefined = undefined;
  private static cb: MeterCallback | undefined = undefined;
  private static running: boolean = false;
  private static label: string = '';
  private static sessionStartMs: number = 0;
  private static windowStartMs: number = 0;
  private static lastMs: number = 0;
  private static deltas: number[] = [];
  private static window: number = 0;
  private static frames: number = 0;
  private static jank: number = 0;

  static start(ui: UIContext, label: string): void {
    PerfMeter.stop();
    PerfMeter.ui = ui;
    PerfMeter.label = label;
    PerfMeter.running = true;
    PerfMeter.sessionStartMs = 0;
    PerfMeter.windowStartMs = 0;
    PerfMeter.lastMs = 0;
    PerfMeter.deltas = [];
    PerfMeter.window = 0;
    PerfMeter.frames = 0;
    PerfMeter.jank = 0;
    const cb: MeterCallback = new MeterCallback((ns: number): void => {
      PerfMeter.onFrame(ns);
    });
    PerfMeter.cb = cb;
    hilog.info(DOMAIN, TAG, 'PERF_START %{public}s', label);
    ui.postFrameCallback(cb);
  }

  static stop(): void {
    if (!PerfMeter.running) {
      return;
    }
    PerfMeter.running = false;
    PerfMeter.cb = undefined;
    const elapsed: number = PerfMeter.lastMs - PerfMeter.sessionStartMs;
    const avg: number = elapsed > 0 ? PerfMeter.frames * 1000 / elapsed : 0;
    hilog.info(DOMAIN, TAG, 'PERF_STOP %{public}s frames=%{public}d avg=%{public}s jank=%{public}d windows=%{public}d',
      PerfMeter.label, PerfMeter.frames, avg.toFixed(1), PerfMeter.jank, PerfMeter.window);
  }

  static isRunning(): boolean {
    return PerfMeter.running;
  }

  private static onFrame(ns: number): void {
    if (!PerfMeter.running) {
      return;
    }
    const now: number = ns / 1000000;
    if (PerfMeter.sessionStartMs === 0) {
      PerfMeter.sessionStartMs = now;
      PerfMeter.windowStartMs = now;
      PerfMeter.lastMs = now;
    } else {
      const dt: number = now - PerfMeter.lastMs;
      if (dt > 0) {
        PerfMeter.deltas.push(dt);
        PerfMeter.frames++;
        if (dt > JANK_MS) {
          PerfMeter.jank++;
        }
      }
    }
    PerfMeter.lastMs = now;
    if (now - PerfMeter.windowStartMs >= WINDOW_MS) {
      PerfMeter.flush(now);
    }
    const cb: MeterCallback | undefined = PerfMeter.cb;
    const ui: UIContext | undefined = PerfMeter.ui;
    if (cb !== undefined && ui !== undefined) {
      ui.postFrameCallback(cb);
    }
  }

  private static flush(now: number): void {
    const elapsed: number = now - PerfMeter.windowStartMs;
    const frames: number = PerfMeter.deltas.length;
    const fps: number = elapsed > 0 ? frames * 1000 / elapsed : 0;
    const sorted: number[] = PerfMeter.deltas.slice().sort((a: number, b: number): number => a - b);
    const p95: number = sorted.length > 0 ?
      sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * 0.95))] : 0;
    let jank: number = 0;
    for (let i = 0; i < PerfMeter.deltas.length; i++) {
      if (PerfMeter.deltas[i] > JANK_MS) {
        jank++;
      }
    }
    PerfMeter.window++;
    const sessionElapsed: number = now - PerfMeter.sessionStartMs;
    const avg: number = sessionElapsed > 0 ? PerfMeter.frames * 1000 / sessionElapsed : 0;
    hilog.info(DOMAIN, TAG,
      'PERF_WIN fps=%{public}s p95=%{public}s jank=%{public}d frames=%{public}d win=%{public}d avg=%{public}s',
      fps.toFixed(1), p95.toFixed(1), jank, frames, PerfMeter.window, avg.toFixed(1));
    PerfMeter.deltas = [];
    PerfMeter.windowStartMs = now;
  }
}
