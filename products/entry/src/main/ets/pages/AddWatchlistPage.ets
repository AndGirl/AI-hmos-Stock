import { AppColor } from 'commons_ui';
import { BreakpointHost, BreakpointService } from 'commons_basic';
import { AddWatchlistPanel } from 'search';
import { AddWatchlistParam } from '../router/AppRoutes';
import { AppServices } from '../di/AppServices';

/**
 * 添加自选路由壳（M7-7 / AC-94）：
 * - sm/md：全屏页；
 * - lg/xl：居中模态 560vp、高 ≤82%（遮罩上一点即返回）；
 * - 页面只做容器与返回栈，搜索/多选/分组/提交全在 features/search 的 AddWatchlistPanel。
 */
@ComponentV2
export struct AddWatchlistPage {
  @Local breakpoint: BreakpointService = BreakpointHost.getService();
  @Local ready: boolean = false;
  @Local currentGroup: string = '';
  @Local presetCode: string = '';
  @Local fromSource: string = '';

  private isWide(): boolean {
    return this.breakpoint.widthBp === 'lg' || this.breakpoint.widthBp === 'xl';
  }

  private close(): void {
    AppServices.get().pop();
  }

  @Builder
  panel() {
    AddWatchlistPanel({
      currentGroupId: this.currentGroup,
      presetCode: this.presetCode,
      fromSource: this.fromSource,
      onClose: (): void => {
        this.close();
      }
    })
  }

  build() {
    NavDestination() {
      if (this.isWide()) {
        Stack({ alignContent: Alignment.Center }) {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor(AppColor.scrim)
            .onClick(() => {
              this.close();
            })

          if (this.ready) {
            Column() {
              this.panel()
            }
            .width(560)
            .height('82%')
            .borderRadius(16)
            .clip(true)
            .backgroundColor(AppColor.bgPage)
            .border({ width: 0.5, color: AppColor.divider })
          }
        }
        .width('100%')
        .height('100%')
        .backgroundColor(AppColor.bgPage)
      } else {
        Column() {
          if (this.ready) {
            this.panel()
          }
        }
        .width('100%')
        .height('100%')
        .backgroundColor(AppColor.bgPage)
      }
    }
    .hideTitleBar(true)
    .backgroundColor(AppColor.bgPage)
    .onReady((context: NavDestinationContext) => {
      if (context.pathInfo.param !== undefined) {
        const param: AddWatchlistParam = context.pathInfo.param as AddWatchlistParam;
        if (param.code !== undefined) {
          this.presetCode = param.code;
        }
        if (param.group !== undefined) {
          this.currentGroup = param.group;
        }
        if (param.from !== undefined) {
          this.fromSource = param.from;
        }
      }
      this.ready = true;
    })
  }
}
