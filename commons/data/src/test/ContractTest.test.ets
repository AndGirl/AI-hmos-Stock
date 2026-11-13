import { describe, expect, it } from '@ohos/hypium';
import {
  ConnectionState,
  QuoteCapabilities,
  QuoteListener,
  QuotePatch,
  QuoteProvider,
  QuoteSnapshot,
  QuoteSubscription
} from '../main/ets/model/QuoteModels';
import { DataServices } from '../main/ets/DataServices';

/**
 * M9-1 契约测试（AC-106~111 的公共底座）：
 * 同一套断言跑多个实现——装配点产出的通道实现（当前为 Mock）与
 * `LegacyQuoteProvider`（只实现必需方法的旧式实现）。
 *
 * 注意：按 R-05，测试里**不直接 new 通道实现**，一律从装配点 `DataServices` 取，
 * 这样断言的就是线上真实装配的那一路，而不是测试自造的副本。
 *
 * 验证「契约 v1.1 只加不改」：
 * - `capabilities` / `onError` / `seq` / `retryAfterMs` 全部可选，缺失时行为不破；
 * - 快照必需字段齐备、价格类空值用 null（不用 0/-1）；
 * - 退订幂等；未知 code 返回空集合而不抛错。
 */
class LegacyListener implements QuoteListener {
  onPatch(patch: QuotePatch): void {
  }

  onStatus(state: ConnectionState): void {
  }
}

class NoopSubscription implements QuoteSubscription {
  unsubscribe(): void {
  }
}

/** 旧式实现：不实现任何 M9 可选成员（模拟「未升级的通道」）。 */
class LegacyQuoteProvider implements QuoteProvider {
  getSnapshots(codes: string[]): Promise<QuoteSnapshot[]> {
    return Promise.resolve([]);
  }

  subscribe(codes: string[], listener: QuoteListener): QuoteSubscription {
    listener.onStatus('online');
    return new NoopSubscription();
  }
}

/** 校验一个实现是否满足契约 v1.1 的「必需部分」。 */
async function assertRequiredContract(provider: QuoteProvider, label: string): Promise<void> {
  const snapshots: QuoteSnapshot[] = await provider.getSnapshots(['600519']);
  expect(label.length > 0).assertTrue();
  // 快照可为空（未接入的通道），但字段一旦存在必须同形
  if (snapshots.length > 0) {
    const snap: QuoteSnapshot = snapshots[0];
    expect(snap.code.length > 0).assertTrue();
    expect(snap.name.length > 0).assertTrue();
    expect(snap.snapshotTime > 0).assertTrue();
    expect(snap.market === 'SH' || snap.market === 'SZ' || snap.market === 'BJ').assertTrue();
  }
  // 退订必须幂等：两次调用不抛错
  const listener: LegacyListener = new LegacyListener();
  const subscription: QuoteSubscription = provider.subscribe(['600519'], listener);
  subscription.unsubscribe();
  subscription.unsubscribe();
}

export default function contractTest(): void {
  describe('QuoteContractV11', () => {
    it('assembled_provider_implements_required_contract', 0, async () => {
      const provider: QuoteProvider = DataServices.quoteProvider();
      await assertRequiredContract(provider, 'assembled');
      const snapshots: QuoteSnapshot[] = await provider.getSnapshots(['600519']);
      expect(snapshots.length).assertEqual(1);
      // 快照必须带涨跌停（AC-110 / CK-10：按板块推导）
      expect(snapshots[0].limitUp !== null && snapshots[0].limitUp !== undefined).assertTrue();
    });

    it('legacy_implementation_still_valid', 0, async () => {
      // 以接口类型持有：旧实现没有 capabilities / onError，调用方必须判空
      const provider: QuoteProvider = new LegacyQuoteProvider();
      await assertRequiredContract(provider, 'legacy');
      expect(provider.capabilities === undefined).assertTrue();
    });

    it('capabilities_is_optional', 0, () => {
      const provider: QuoteProvider = DataServices.quoteProvider();
      if (provider.capabilities !== undefined) {
        const caps: QuoteCapabilities = provider.capabilities();
        expect(typeof caps.push).assertEqual('boolean');
        expect(typeof caps.rateLimit).assertEqual('boolean');
      } else {
        // 未声明能力 = 按「全能力」处理（契约 v1.1 缺省语义）
        expect(provider.capabilities === undefined).assertTrue();
      }
    });

    it('unknown_code_returns_empty_not_throw', 0, async () => {
      const provider: QuoteProvider = DataServices.quoteProvider();
      const snapshots: QuoteSnapshot[] = await provider.getSnapshots(['999999']);
      expect(snapshots.length).assertEqual(0);
    });

    it('limit_ratio_by_board_from_snapshot', 0, async () => {
      const provider: QuoteProvider = DataServices.quoteProvider();
      const main: QuoteSnapshot[] = await provider.getSnapshots(['600519']);
      const chinext: QuoteSnapshot[] = await provider.getSnapshots(['300750']);
      const star: QuoteSnapshot[] = await provider.getSnapshots(['688981']);
      // 主板 ±10%、创业板/科创板 ±20%（按昨收推算，允许一分钱误差）
      const mainRatio: number = (main[0].limitUp as number) / (main[0].prevClose as number);
      const chinextRatio: number = (chinext[0].limitUp as number) / (chinext[0].prevClose as number);
      const starRatio: number = (star[0].limitUp as number) / (star[0].prevClose as number);
      expect(Math.abs(mainRatio - 1.1) < 0.005).assertTrue();
      expect(Math.abs(chinextRatio - 1.2) < 0.005).assertTrue();
      expect(Math.abs(starRatio - 1.2) < 0.005).assertTrue();
    });

    it('snapshot_prices_are_null_or_positive', 0, async () => {
      const provider: QuoteProvider = DataServices.quoteProvider();
      // 停牌股：价格类字段必须为 null（契约 §4.3，禁止用 0/-1 代替）
      const suspended: QuoteSnapshot[] = await provider.getSnapshots(['600000']);
      expect(suspended.length).assertEqual(1);
      expect(suspended[0].status).assertEqual('suspended');
      expect(suspended[0].last).assertNull();
      expect(suspended[0].limitUp).assertNull();
    });
  });
}
