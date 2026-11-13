import { ConnectionHost, ConnectionHub, NetState } from 'commons_basic';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { WatchlistStore } from './WatchlistStore';

const DOMAIN: number = 0x0001;
const TAG: string = 'WatchSync';

/**
 * 自选待同步（M7-1 / §5.5 规则 4）：
 * 离线加入的自选先落本地并标 pending；联网（状态不是 offline）后一次性清零标记。
 * - Mock 阶段同步即时成功；阻塞/失败只保留标记，下次网络恢复再试，不重复插入；
 * - 只做数据，不弹提示；提示由自选页监听 Store 变更后决定。
 */
export class WatchlistSyncService {
  private store: WatchlistStore;
  private attached: boolean = false;
  private listener: (state: NetState) => void;

  constructor(store: WatchlistStore) {
    this.store = store;
    this.listener = (state: NetState): void => {
      if (state !== 'offline') {
        this.trySync();
      }
    };
  }

  start(): void {
    if (this.attached) {
      return;
    }
    ConnectionHost.getService().subscribe(this.listener);
    this.attached = true;
    // 冷启时 store 还没加载：先读一次盘再判断 pending（离线期间攒下的标记）。
    this.store.load().then((): void => {
      this.trySync();
    }).catch((err: Error): void => {
      hilog.warn(DOMAIN, TAG, 'pending_load_fail %{public}s', JSON.stringify(err));
    });
  }

  stop(): void {
    if (!this.attached) {
      return;
    }
    ConnectionHost.getService().unsubscribe(this.listener);
    this.attached = false;
  }

  /** 供页面在回到前台时补一次（避免错过状态迁移）。 */
  trySync(): void {
    const hub: ConnectionHub = ConnectionHost.getService();
    if (hub.isOffline() || this.store.pendingCount() === 0) {
      return;
    }
    this.store.syncPending().catch((err: Error): void => {
      hilog.warn(DOMAIN, TAG, 'pending_sync_fail %{public}s', JSON.stringify(err));
    });
  }
}
