import { SESSION_SEED } from '../mock/SeededRandom';

/**
 * 行情数据源与通道配置（M9-2）。
 *
 * 数据源只有两种，**没有真实供应商**：
 * - `mock`    直连：`MockQuoteProvider` → `QuoteBus`（阶段一/二期既有路径，最短链路）；
 * - `sandbox` 通道：`QuoteChannel(MockQuoteProvider)` → `QuoteBus`，
 *   额外获得 鉴权 token / 帧校验 / 429 降频 / 健康状态，行为与将来接本地后端一致。
 *
 * 灰度：`grayPercent` 用于「按比例走通道」的过渡（0~100）；100 表示全量走通道。
 * 真实后端接入时，新增 `'real'` 并把 transport 换成 HTTP/WS 即可，业务层不动。
 */
export type QuoteSource = 'mock' | 'sandbox';

export class AppConfig {
  /** 当前数据源（调试面板可切；release 由常量决定）。 */
  static quoteSource: QuoteSource = 'sandbox';
  /** 灰度比例：0~100，仅 DEBUG 调试用；100 = 全量。 */
  static grayPercent: number = 100;
  /** 演示种子：换值即换一套走势（写入 docs/api-contract-v1.md 的算法口径）。 */
  static readonly sessionSeed: number = SESSION_SEED;
  /** token 有效期（模拟 2 小时）。 */
  static readonly tokenTtlMs: number = 7200 * 1000;
  /** 是否走通道。 */
  static useChannel(): boolean {
    return AppConfig.quoteSource === 'sandbox';
  }

  /** 调试切换数据源（仅 debug 入口调用）。 */
  static setQuoteSource(source: QuoteSource): void {
    AppConfig.quoteSource = source;
  }
}
