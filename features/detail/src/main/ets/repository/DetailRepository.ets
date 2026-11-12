import {
  ChartPeriod,
  ChartSeries,
  DataServices,
  DetailListener,
  DetailProvider,
  DetailSnapshot,
  SinkTier,
  SubscriptionHandle
} from 'commons_data';

/**
 * 详情仓储（L2）：只做 provider 组合与参数透传，不产出中文文案（附录 C 第 13 条）。
 * 缓存 / 状态机在 DetailVM，页面退出由 VM 负责退订。
 * M4：推送订阅统一经 DataServices 的订阅登记表（同 code 合并 + 档位降频）。
 */
export class DetailRepository {
  private provider(): DetailProvider {
    return DataServices.detailProvider();
  }

  load(code: string): Promise<DetailSnapshot> {
    return this.provider().loadDetail(code);
  }

  loadChart(code: string, period: ChartPeriod): Promise<ChartSeries> {
    return this.provider().loadChart(code, period);
  }

  subscribe(code: string, listener: DetailListener, tier: SinkTier): SubscriptionHandle {
    return DataServices.detailSubs().acquire(code, listener, tier);
  }

  setTier(handle: SubscriptionHandle, tier: SinkTier): void {
    DataServices.detailSubs().setTier(handle, tier);
  }

  cached(code: string): DetailSnapshot | undefined {
    return this.provider().cachedDetail(code);
  }
}

/** 订阅登记表计数（debug 断言 AC-83：3 窗 ≤3 路、全部关闭后归零）。 */
export function detailSubscriptionStats(): string {
  return DataServices.detailSubs().stats();
}
