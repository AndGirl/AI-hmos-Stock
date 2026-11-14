import { process } from '@kit.ArkTS';
import { systemDateTime } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0001;
const TAG: string = 'StartupPerf';

/**
 * 冷启打点（M13-2 / AC-126）。
 *
 * 口径（本轮确认）：**应用内冷启**＝进程创建 → 首个内容帧渲染完成。
 *   - 起点：`process.getStartRealtime()`（进程启动时刻）；
 *   - 终点：根页面首帧 `onAppear`；
 *   - 两端必须用**同一时钟**：实测 `getStartRealtime()` 落在「系统启动至今、不含深度休眠」
 *     （ACTIVE）这条时间轴上，与 `getUptime(STARTUP)` 相差的正是设备累计深睡时间（本机约 49.7h），
 *     混用会算出「49 小时冷启」这种荒谬值。因此统一取 `TimeType.ACTIVE`。
 *
 * 每个进程只打一条，标签 `StartupPerf`，字段 `cold_start_ms` / `oncreate_ms`。
 * 系统级首帧（含 AbilityManager 调度）需 AGC/Profiler，本轮以本指标为口径（见 docs/perf/phase2-m13.md）。
 */
export class StartupMeter {
  private static reported: boolean = false;
  private static startRealtime: number = 0;
  private static onCreateUptime: number = 0;

  /** `EntryAbility.onCreate` 调用：记录进程起点与 onCreate 时刻（同一时钟，便于拆分阶段）。 */
  static markProcessStart(): void {
    try {
      StartupMeter.startRealtime = process.getStartRealtime();
      StartupMeter.onCreateUptime = systemDateTime.getUptime(systemDateTime.TimeType.ACTIVE);
      hilog.info(DOMAIN, TAG, 'startup_mark start_realtime=%{public}d uptime_active=%{public}d',
        StartupMeter.startRealtime, StartupMeter.onCreateUptime);
    } catch (err) {
      StartupMeter.startRealtime = 0;
      StartupMeter.onCreateUptime = 0;
      hilog.warn(DOMAIN, TAG, 'startup_mark_fail');
    }
  }

  /** 首帧调用（幂等）：输出 `cold_start_ms` 与 `oncreate_ms`。 */
  static markFirstFrame(phase: string): void {
    if (StartupMeter.reported) {
      return;
    }
    StartupMeter.reported = true;
    if (StartupMeter.startRealtime <= 0) {
      hilog.warn(DOMAIN, TAG, 'startup_skip no_mark phase=%{public}s', phase);
      return;
    }
    try {
      const now: number = systemDateTime.getUptime(systemDateTime.TimeType.ACTIVE);
      const cold: number = Math.max(0, Math.round(now - StartupMeter.startRealtime));
      const onCreate: number = Math.max(0, Math.round(StartupMeter.onCreateUptime - StartupMeter.startRealtime));
      hilog.info(DOMAIN, TAG, 'cold_start_ms=%{public}d oncreate_ms=%{public}d phase=%{public}s',
        cold, onCreate, phase);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'startup_report_fail');
    }
  }

  /** 仅用于调试面板/单测断言（是否已打过点）。 */
  static isReported(): boolean {
    return StartupMeter.reported;
  }
}
