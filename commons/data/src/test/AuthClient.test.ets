import { describe, expect, it } from '@ohos/hypium';
import { QuoteTokenState } from 'commons_basic';
import { AuthClient } from '../main/ets/real/AuthClient';
import { AppConfig } from '../main/ets/real/AppConfig';

/**
 * M9-2 / AC-106 鉴权单测：
 * 首次换票成功、过期重换、401 只刷新一次、刷新失败转未授权（不死循环）、reset 解锁。
 */
export default function authClientTest(): void {
  describe('AuthClient', () => {
    it('first_exchange_issues_token', 0, () => {
      const auth: AuthClient = new AuthClient();
      expect(auth.tokenState()).assertEqual('none');
      const state: QuoteTokenState = auth.ensureToken(1000, false);
      expect(state).assertEqual('valid');
      expect(auth.tokenValue().length > 0).assertTrue();
      expect(auth.hasValidToken(1000)).assertTrue();
    });

    it('token_not_persisted_in_describe', 0, () => {
      const auth: AuthClient = new AuthClient();
      auth.ensureToken(1000, false);
      const text: string = auth.describe();
      expect(text.indexOf('mock-token') < 0).assertTrue();
    });

    it('expired_token_is_reissued', 0, () => {
      const auth: AuthClient = new AuthClient();
      auth.ensureToken(1000, false);
      const first: string = auth.tokenValue();
      const later: number = 1000 + AppConfig.tokenTtlMs + 1;
      expect(auth.hasValidToken(later)).assertFalse();
      const state: QuoteTokenState = auth.ensureToken(later, false);
      expect(state).assertEqual('valid');
      expect(auth.tokenValue() === first).assertFalse();
    });

    it('initial_exchange_failure_locks', 0, () => {
      const auth: AuthClient = new AuthClient();
      const state: QuoteTokenState = auth.ensureToken(1000, true);
      expect(state).assertEqual('unauthorized');
      expect(auth.hasValidToken(1000)).assertFalse();
    });

    it('401_refreshes_once', 0, () => {
      const auth: AuthClient = new AuthClient();
      auth.ensureToken(1000, false);
      const before: string = auth.tokenValue();
      const state: QuoteTokenState = auth.handleUnauthorized(2000, false);
      expect(state).assertEqual('valid');
      expect(auth.tokenValue() === before).assertFalse();
    });

    it('second_401_after_refresh_locks', 0, () => {
      const auth: AuthClient = new AuthClient();
      auth.ensureToken(1000, false);
      expect(auth.handleUnauthorized(2000, false)).assertEqual('valid');
      // 已用掉一次刷新：再 401 直接锁定，不再换票（防死循环）
      const second: QuoteTokenState = auth.handleUnauthorized(3000, false);
      expect(second).assertEqual('unauthorized');
      expect(auth.tokenState()).assertEqual('unauthorized');
    });

    it('refresh_failure_locks_immediately', 0, () => {
      const auth: AuthClient = new AuthClient();
      auth.ensureToken(1000, false);
      const state: QuoteTokenState = auth.handleUnauthorized(2000, true);
      expect(state).assertEqual('unauthorized');
      expect(auth.tokenValue().length).assertEqual(0);
    });

    it('locked_state_stays_locked_without_reset', 0, () => {
      const auth: AuthClient = new AuthClient();
      auth.ensureToken(1000, true);
      expect(auth.ensureToken(2000, false)).assertEqual('unauthorized');
      expect(auth.handleUnauthorized(3000, false)).assertEqual('unauthorized');
    });

    it('reset_unlocks', 0, () => {
      const auth: AuthClient = new AuthClient();
      auth.ensureToken(1000, true);
      expect(auth.tokenState()).assertEqual('unauthorized');
      const state: QuoteTokenState = auth.reset(4000);
      expect(state).assertEqual('valid');
      expect(auth.hasValidToken(4000)).assertTrue();
    });

    it('invalidate_clears_token', 0, () => {
      const auth: AuthClient = new AuthClient();
      auth.ensureToken(1000, false);
      auth.invalidate();
      expect(auth.tokenState()).assertEqual('none');
      expect(auth.hasValidToken(1000)).assertFalse();
    });
  });
}
