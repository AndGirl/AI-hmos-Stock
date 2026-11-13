import { QuoteTokenState } from 'commons_basic';
import { AppConfig } from './AppConfig';

/**
 * 行情鉴权（M9-2 / AC-106）。
 *
 * 现状：**没有真实账号体系**，票据由设备内生成（`dev-<seed>-<n>`），
 * token 是本地签发的模拟串，只放内存、**不落盘**（避免日志/磁盘出现凭证）。
 *
 * 语义（与将来本地后端保持一致，便于直接换实现）：
 * - `ensureToken`：有未过期 token 直接用，否则换一次；
 * - `handleUnauthorized`：收到 401 后**只刷新一次**；刷新失败、或一次刷新后再次 401
 *   → 锁定为 `unauthorized`，上层停止重试并引导重新登录（不得死循环）；
 * - 失败锁定只能由 `reset()`（用户动作：调试「恢复」/重进页面）解除。
 *
 * 全部同步：本地模拟没有网络往返；接后端时把返回值改成 Promise 即可，调用点结构不变。
 */
export class AuthClient {
  private token: string = '';
  private issuedAt: number = 0;
  private state: QuoteTokenState = 'none';
  private ticketSeq: number = 0;
  /** 自上次成功换票以来的刷新次数（≥1 后再次 401 即锁定）。 */
  private refreshesUsed: number = 0;

  /** 取可用 token；没有就换一次。 */
  ensureToken(now: number, forceFail: boolean): QuoteTokenState {
    if (this.state === 'unauthorized') {
      return 'unauthorized';
    }
    if (this.hasValidToken(now)) {
      this.state = 'valid';
      // 当前 token 被实际用上，说明上一轮 401 已恢复：刷新配额归零。
      this.refreshesUsed = 0;
      return 'valid';
    }
    return this.issue(now, forceFail);
  }

  /** 401 处理：最多刷新一次；失败或已刷新过仍 401 → 锁定。 */
  handleUnauthorized(now: number, forceFail: boolean): QuoteTokenState {
    if (this.state === 'unauthorized') {
      return 'unauthorized';
    }
    if (this.refreshesUsed >= 1) {
      return this.lock();
    }
    this.refreshesUsed++;
    if (forceFail) {
      return this.lock();
    }
    return this.issue(now, false);
  }

  /** 当前 token（无则空串；调用方不得落盘或打印）。 */
  tokenValue(): string {
    return this.token;
  }

  /** 当前 token 状态（`none` / `valid` / `refreshing` / `unauthorized`）。 */
  tokenState(): QuoteTokenState {
    return this.state;
  }

  hasValidToken(now: number): boolean {
    return this.token.length > 0 && now - this.issuedAt < AppConfig.tokenTtlMs;
  }

  /** 主动失效（换票据/退出登录）。 */
  invalidate(): void {
    this.token = '';
    this.issuedAt = 0;
    this.state = 'none';
  }

  /** 调试「恢复」/重新登录：清锁定并换票。 */
  reset(now: number): QuoteTokenState {
    this.refreshesUsed = 0;
    this.invalidate();
    return this.issue(now, false);
  }

  /** 稳定串：`token_state=valid refresh=0`（不含 token 值）。 */
  describe(): string {
    return `token_state=${this.state} refresh=${this.refreshesUsed}`;
  }

  private issue(now: number, forceFail: boolean): QuoteTokenState {
    if (forceFail) {
      return this.lock();
    }
    this.ticketSeq++;
    // 票据 → token：模拟签发，只留内存（token 不落盘）。
    this.token = `mock-token-${AppConfig.sessionSeed}-${this.ticketSeq}`;
    this.issuedAt = now;
    this.state = 'valid';
    return 'valid';
  }

  private lock(): QuoteTokenState {
    this.token = '';
    this.issuedAt = 0;
    this.state = 'unauthorized';
    return 'unauthorized';
  }
}
