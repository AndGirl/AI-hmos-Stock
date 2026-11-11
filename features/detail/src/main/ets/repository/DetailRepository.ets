import {
  ChartPeriod,
  ChartSeries,
  DataServices,
  DetailListener,
  DetailProvider,
  DetailSnapshot,
  DetailSubscription
} from 'commons_data';

/**
 * 详情仓储（L2）：只做 provider 组合与参数透传，不产出中文文案（附录 C 第 13 条）。
 * 缓存 / 状态机在 DetailVM，页面退出由 VM 负责退订。
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

  subscribe(code: string, listener: DetailListener): DetailSubscription {
    return this.provider().subscribe(code, listener);
  }

  cached(code: string): DetailSnapshot | undefined {
    return this.provider().cachedDetail(code);
  }
}
