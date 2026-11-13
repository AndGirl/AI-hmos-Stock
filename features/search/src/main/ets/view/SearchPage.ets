import { promptAction } from '@kit.ArkUI';
import { AppColor } from 'commons_ui';
import {
  BreakpointHost,
  BreakpointService,
  ConnectionHost,
  ConnectionHub,
  SafeAreaHost,
  SafeAreaService
} from 'commons_basic';
import { StateMode, StateView } from 'commons_ui';
import { DetailAction, DetailContent, showDetailActionMenu } from 'detail';
import { DEBUG } from '../../../../BuildProfile';
import { SearchRowVM } from '../viewmodel/SearchRowVM';
import { SearchRowAction, SearchVM } from '../viewmodel/SearchVM';
import { SearchBar } from './SearchBar';
import { SearchBody } from './SearchBody';

export type SearchMode = 'tab' | 'push';

/**
 * 搜索页（M6-4 / M6-6）：
 * - `tab`：行情 Tab 内嵌；`push`：路由全屏（自选空态 / 深链）。
 * - sm/md 单列；lg/xl 左结果 38% + 右 DetailContent(pane) 62%，选中行只换右栏 code、不 push（AC-87）。
 * - 路由/开窗由 entry 装配，本组件只上抛事件（INV-D1）。
 */
@ComponentV2
export struct SearchPage {
  @Param mode: SearchMode = 'tab';
  @Param initialQuery: string = '';
  @Event onOpenDetail: (code: string, rank: number) => void = (code: string, rank: number): void => {
  };
  @Event onOpenTrade: (code: string) => void = (code: string): void => {
  };
  @Event onOpenAddWatchlist: (code: string) => void = (code: string): void => {
  };
  @Event onOpenPk: (codes: string[]) => void = (codes: string[]): void => {
  };
  @Event onClose: () => void = (): void => {
  };
  @Local vm: SearchVM = new SearchVM();
  @Local breakpoint: BreakpointService = BreakpointHost.getService();
  @Local hub: ConnectionHub = ConnectionHost.getService();
  @Local safeArea: SafeAreaService = SafeAreaHost.getService();

  aboutToAppear(): void {
    this.vm.init();
    if (this.initialQuery.trim().length > 0) {
      this.vm.pickQuery(this.initialQuery);
    }
  }

  aboutToDisappear(): void {
    this.vm.dispose();
  }

  @Monitor('hub.state')
  onConnectionChanged(): void {
    this.vm.refreshOffline();
  }

  /** 分栏阈值按 G-1（lg/xl），不改全局 BreakpointService（避免自选页 xl 规则回归）。 */
  private isSplit(): boolean {
    return this.breakpoint.widthBp === 'lg' || this.breakpoint.widthBp === 'xl';
  }

  private viewportWidth(): number {
    return this.breakpoint.viewportWidth > 0 ? this.breakpoint.viewportWidth : 360;
  }

  private leftWidth(): number {
    return Math.floor(this.viewportWidth() * 0.38);
  }

  private paneWidth(): number {
    return Math.max(320, this.viewportWidth() - this.leftWidth() - 1);
  }

  /** 右栏标的：用户点过的优先，否则取第一条股票命中。 */
  private paneCode(): string {
    if (this.vm.selectedCode.length > 0) {
      return this.vm.selectedCode;
    }
    for (let i = 0; i < this.vm.sections.length; i++) {
      const rows: SearchRowVM[] = this.vm.sections[i].rows;
      for (let j = 0; j < rows.length; j++) {
        if (rows[j].kind === 'stock') {
          return rows[j].code;
        }
      }
    }
    return '';
  }

  private handleRowTap(row: SearchRowVM): void {
    const action: SearchRowAction = this.vm.pickRow(row);
    if (action === 'detail' && !this.isSplit()) {
      this.onOpenDetail(row.code, row.rank);
    }
  }

  /** 行尾动作：未添加→加自选，已添加→撤出自选（AC-91 变更，M6 追加）。 */
  private async handleRowAdd(row: SearchRowVM): Promise<void> {
    const wasAdded: boolean = row.added;
    const result: string = await this.vm.toggleWatch(row);
    if (result === 'added') {
      this.toast($r('app.string.search_add_success'));
    } else if (result === 'removed') {
      this.toast($r('app.string.search_remove_success'));
    } else if (result === 'limit') {
      this.toast($r('app.string.search_add_limit'));
    } else if (result === 'failed') {
      this.toast(wasAdded ? $r('app.string.search_remove_failed') : $r('app.string.search_add_failed'));
    }
  }

  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message: message, duration: 1800 });
  }

  /**
   * 仅 debug 可用的六态注入入口（长按搜索条）：失败 / 429 / 离线 / 热搜失败 / 恢复。
   * release 由 BuildProfile.DEBUG=false 关闭（AC-92 取证用）。
   */
  private openDebugMenu(): void {
    if (!DEBUG) {
      return;
    }
    const b0: promptAction.Button = { text: '失败（fail）', color: AppColor.debug };
    const b1: promptAction.Button = { text: '429 限流', color: AppColor.debug };
    const b2: promptAction.Button = { text: '离线（offline）', color: AppColor.debug };
    const b3: promptAction.Button = { text: '热搜失败', color: AppColor.debug };
    const b4: promptAction.Button = { text: '慢请求（1.5s）', color: AppColor.debug };
    const b5: promptAction.Button = { text: '恢复（reset）', color: AppColor.debug };
    const buttons: [promptAction.Button, promptAction.Button, promptAction.Button,
      promptAction.Button, promptAction.Button, promptAction.Button] = [b0, b1, b2, b3, b4, b5];
    this.getUIContext().getPromptAction().showActionMenu({ title: '搜索调试（debug）', buttons: buttons })
      .then((res: promptAction.ActionMenuSuccessResponse): void => {
        if (res.index === 0) {
          this.vm.applyDebugFault('fail');
        } else if (res.index === 1) {
          this.vm.applyDebugFault('rate');
        } else if (res.index === 2) {
          this.vm.applyDebugFault('offline');
        } else if (res.index === 3) {
          this.vm.applyDebugFault('hot');
        } else if (res.index === 4) {
          this.vm.applyDebugFault('slow');
        } else if (res.index === 5) {
          this.vm.applyDebugFault('reset');
        }
      }).catch((): void => {
    });
  }

  private handlePaneAction(code: string, action: DetailAction): void {    if (action === 'watchlist') {
      this.onOpenAddWatchlist(code);
      return;
    }
    if (action === 'pk') {
      this.onOpenPk([code]);
      return;
    }
    if (action === 'trade') {
      this.onOpenTrade(code);
      return;
    }
    if (action === 'more') {
      showDetailActionMenu(this.getUIContext(), true, (picked: DetailAction): void => {
        this.handlePaneAction(code, picked);
      });
      return;
    }
  }

  build() {
    Column() {
      Column() {
        SearchBar({
          term: this.vm.term,
          showCancel: this.mode === 'push',
          autoFocus: this.mode === 'push',
          onTermChange: (text: string): void => {
            this.vm.onTermChange(text);
          },
          onSubmit: (): void => {
            this.vm.submit();
          },
          onCancel: (): void => {
            this.onClose();
          }
        })
      }
      .width('100%')
      .gesture(
        LongPressGesture({ repeat: false })
          .onAction(() => {
            this.openDebugMenu();
          })
      )

      // 离线提示条 28vp：结果照常展示、不置灰（G-1）。
      if (this.vm.showOfflineBanner) {
        Row() {
          Text($r('app.string.search_offline_banner'))
            .fontSize(12)
            .fontColor(AppColor.textSecondary)
        }
        .width('100%')
        .height(28)
        .padding({ left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)
        .backgroundColor(AppColor.bgSurface)
        .border({ width: { bottom: 0.5 }, color: AppColor.divider })
      }

      Row() {
        Column() {
          SearchBody({
            vm: this.vm,
            mode: 'search',
            onRowTap: (row: SearchRowVM): void => {
              this.handleRowTap(row);
            },
            onRowAdd: (row: SearchRowVM): void => {
              this.handleRowAdd(row);
            }
          })
        }
        .width(this.isSplit() ? this.leftWidth() : '100%')
        .height('100%')

        if (this.isSplit()) {
          Divider()
            .vertical(true)
            .height('100%')
            .strokeWidth(1)
            .color(AppColor.divider)

          Column() {
            if (this.paneCode().length > 0) {
              DetailContent({
                code: this.paneCode(),
                mode: 'pane',
                contentWidth: this.paneWidth(),
                bottomInset: this.safeArea.bottomInset,
                onAction: (action: DetailAction): void => {
                  this.handlePaneAction(this.paneCode(), action);
                }
              })
            } else {
              StateView({
                mode: StateMode.EMPTY,
                stateDesc: $r('app.string.search_pane_empty')
              })
                .width('100%')
                .height('100%')
            }
          }
          .height('100%')
          .width(this.paneWidth())
          .backgroundColor(AppColor.bgPage)
        }
      }
      .width('100%')
      .layoutWeight(1)
      .alignItems(VerticalAlign.Top)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColor.bgPage)
  }
}
