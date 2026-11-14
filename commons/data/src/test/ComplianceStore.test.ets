import { describe, expect, it } from '@ohos/hypium';
import { PrivacyConsentStore, RiskNoticeStore } from '../main/ets/store/ComplianceStore';
import { StabilitySnapshot, StabilityStore } from '../main/ets/store/StabilityStore';
import { StorageAdapter } from '../main/ets/store/StorageAdapter';

const CONSENT_KEY: string = 'privacy_consent_v1';
const RISK_KEY: string = 'trade_risk_v1';
const STABILITY_KEY: string = 'stability_v1';

/** 每个用例前清掉内存/落盘状态（未注入 context 时 `StorageAdapter` 退化为内存）。 */
async function resetKeys(): Promise<void> {
  await StorageAdapter.remove(CONSENT_KEY);
  await StorageAdapter.remove(RISK_KEY);
  await StorageAdapter.remove(STABILITY_KEY);
}

/**
 * M13-1 合规存储单测：隐私同意（`privacy_consent_v1`）与首笔风险揭示（`trade_risk_v1`）。
 * 断言点是「门禁口径」：未同意、版本不一致、坏 JSON 都必须回到「需要同意」。
 */
export default function complianceStoreTest(): void {
  describe('PrivacyConsentStore', () => {
    it('absent_needs_consent', 0, async () => {
      await resetKeys();
      const store: PrivacyConsentStore = new PrivacyConsentStore();
      await store.load();
      expect(store.consented()).assertFalse();
      expect(store.agreedAt()).assertEqual(0);
    });

    it('agree_persists_across_instances', 0, async () => {
      await resetKeys();
      const first: PrivacyConsentStore = new PrivacyConsentStore();
      await first.load();
      await first.agree();
      expect(first.consented()).assertTrue();
      expect(first.agreedAt() > 0).assertTrue();

      // 新实例模拟重启：从同一个键读回
      const second: PrivacyConsentStore = new PrivacyConsentStore();
      await second.load();
      expect(second.consented()).assertTrue();
      expect(second.agreedAt()).assertEqual(first.agreedAt());
    });

    it('revoke_requires_consent_again', 0, async () => {
      await resetKeys();
      const store: PrivacyConsentStore = new PrivacyConsentStore();
      await store.load();
      await store.agree();
      await store.revoke();
      expect(store.consented()).assertFalse();

      const next: PrivacyConsentStore = new PrivacyConsentStore();
      await next.load();
      expect(next.consented()).assertFalse();
    });

    it('version_mismatch_needs_reconsent', 0, async () => {
      await resetKeys();
      // 旧版本同意记录：策略改版后必须重新同意
      await StorageAdapter.putString(CONSENT_KEY,
        JSON.stringify({ agreed: true, version: '0.9', agreedAt: 1700000000000 }));
      const store: PrivacyConsentStore = new PrivacyConsentStore();
      await store.load();
      expect(store.consented()).assertFalse();
      expect(store.agreedAt()).assertEqual(0);
    });

    it('bad_json_falls_back_to_unconsented', 0, async () => {
      const record = PrivacyConsentStore.parse('{not-json');
      expect(record.agreed).assertFalse();
      expect(record.version).assertEqual('');
      const empty = PrivacyConsentStore.parse('');
      expect(empty.agreed).assertFalse();
    });

    it('parse_keeps_valid_record', 0, async () => {
      const record = PrivacyConsentStore.parse('{"agreed":true,"version":"1.0","agreedAt":1700000000000}');
      expect(record.agreed).assertTrue();
      expect(record.version).assertEqual('1.0');
      expect(record.agreedAt).assertEqual(1700000000000);
    });
  });

  describe('RiskNoticeStore', () => {
    it('default_not_acked', 0, async () => {
      await resetKeys();
      const store: RiskNoticeStore = new RiskNoticeStore();
      await store.load();
      expect(store.acked()).assertFalse();
    });

    it('ack_persists_and_clear_resets', 0, async () => {
      await resetKeys();
      const store: RiskNoticeStore = new RiskNoticeStore();
      await store.load();
      await store.ack();
      expect(store.acked()).assertTrue();

      const second: RiskNoticeStore = new RiskNoticeStore();
      await second.load();
      expect(second.acked()).assertTrue();

      await second.clear();
      expect(second.acked()).assertFalse();
      const third: RiskNoticeStore = new RiskNoticeStore();
      await third.load();
      expect(third.acked()).assertFalse();
    });
  });

  describe('StabilityStore', () => {
    it('counts_session_and_events', 0, async () => {
      await resetKeys();
      const store: StabilityStore = new StabilityStore();
      await store.load();
      store.countSession();
      store.countSession();
      store.mark('APP_CRASH');
      store.mark('js_error');
      const snap: StabilitySnapshot = store.snapshot();
      expect(snap.sessions).assertEqual(2);
      expect(snap.crashes).assertEqual(1);
      expect(snap.jsErrors).assertEqual(1);
      expect(snap.lastEvent).assertEqual('js_error');
      expect(store.describe().indexOf('session=2') === 0).assertTrue();
    });

    it('persists_and_separates_crash_from_freeze', 0, async () => {
      await resetKeys();
      const store: StabilityStore = new StabilityStore();
      await store.load();
      store.countSession();
      store.mark('APP_FREEZE');
      const second: StabilityStore = new StabilityStore();
      await second.load();
      const snap: StabilitySnapshot = second.snapshot();
      expect(snap.sessions).assertEqual(1);
      expect(snap.freezes).assertEqual(1);
      expect(snap.crashes).assertEqual(0);
    });

    it('clear_keeps_session_count', 0, async () => {
      await resetKeys();
      const store: StabilityStore = new StabilityStore();
      await store.load();
      store.countSession();
      store.mark('APP_CRASH');
      store.clear();
      const snap: StabilitySnapshot = store.snapshot();
      expect(snap.crashes).assertEqual(0);
      expect(snap.sessions).assertEqual(1);
    });

    it('parse_bad_json_returns_zero', 0, async () => {
      const snap = StabilityStore.parse('{bad');
      expect(snap.sessions).assertEqual(0);
      expect(snap.crashes).assertEqual(0);
      const filled = StabilityStore.parse('{"sessions":3,"crashes":1,"freezes":0,"jsErrors":2,' +
        '"rejections":1,"lastEvent":"APP_CRASH","lastEventAt":1700000000000}');
      expect(filled.sessions).assertEqual(3);
      expect(filled.crashes).assertEqual(1);
      expect(filled.jsErrors).assertEqual(2);
      expect(filled.rejections).assertEqual(1);
    });
  });
}
