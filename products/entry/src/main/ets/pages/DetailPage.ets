import { AppColor, AppDim, StateMode, StateView } from 'commons_ui';
import { SafeAreaHost, SafeAreaService } from 'commons_basic';
import { DetailParam } from '../router/AppRoutes';

enum DetailUiState {
  LOADING = 0,
  CONTENT = 1,
  ERROR = 2
}

/**
 * 个股详情壳：M0 验证路由/参数/返回栈，同时把「加载 → 内容 / 失败重试」状态机接线。
 * M2 用 DetailRepository 的真实 Promise 替换这里的 300ms 占位延迟，状态分支不变。
 * 参数通过 NavDestination.onReady 的 pathInfo 取，页面不感知调用方。
 */
@ComponentV2
export struct DetailPage {
  @Local detailCode: string = '';
  @Local uiState: DetailUiState = DetailUiState.LOADING;
  @Local retrying: boolean = false;
  @Local safeArea: SafeAreaService = SafeAreaHost.getService();
  private loadTimer: number = -1;
  private retryTimer: number = -1;

  aboutToDisappear(): void {
    this.clearTimers();
  }

  private clearTimers(): void {
    if (this.loadTimer !== -1) {
      clearTimeout(this.loadTimer);
      this.loadTimer = -1;
    }
    if (this.retryTimer !== -1) {
      clearTimeout(this.retryTimer);
      this.retryTimer = -1;
    }
  }

  /** M0 占位加载：M2 改为 DetailRepository.load(code) 的 Promise。 */
  private load(): void {
    this.clearTimers();
    this.uiState = DetailUiState.LOADING;
    this.loadTimer = setTimeout(() => {
      this.loadTimer = -1;
      this.uiState = this.detailCode.length > 0 ? DetailUiState.CONTENT : DetailUiState.ERROR;
    }, 300);
  }

  private retry(): void {
    if (this.retrying) {
      return;
    }
    this.retrying = true;
    this.clearTimers();
    this.retryTimer = setTimeout(() => {
      this.retryTimer = -1;
      this.retrying = false;
      this.load();
    }, 400);
  }

  build() {
    NavDestination() {
      if (this.uiState === DetailUiState.LOADING) {
        StateView({ mode: StateMode.LOADING })
          .width('100%')
          .height('100%')
          .padding({ bottom: this.safeArea.bottomInset })
      } else if (this.uiState === DetailUiState.ERROR) {
        StateView({
          mode: StateMode.ERROR,
          stateDesc: $r('app.string.detail_load_failed'),
          showAction: true,
          actionLabel: $r('app.string.retry'),
          retrying: this.retrying,
          onAction: () => {
            this.retry();
          }
        })
          .width('100%')
          .height('100%')
          .padding({ bottom: this.safeArea.bottomInset })
      } else {
        Column() {
          Text(this.detailCode)
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppColor.textPrimary)

          Column()
            .width('100%')
            .height(180)
            .backgroundColor(AppColor.bgSurface)
            .borderRadius(12)
            .margin({ top: AppDim.gap16 })

          Column()
            .width('100%')
            .height(96)
            .backgroundColor(AppColor.bgSurface)
            .borderRadius(12)
            .margin({ top: AppDim.gap12 })

          Column()
            .width('100%')
            .height(96)
            .backgroundColor(AppColor.bgSurface)
            .borderRadius(12)
            .margin({ top: AppDim.gap12 })
        }
        .width('100%')
        .height('100%')
        .padding({
          left: AppDim.gap16,
          right: AppDim.gap16,
          top: AppDim.gap16,
          bottom: this.safeArea.bottomInset + 16
        })
        .alignItems(HorizontalAlign.Start)
      }
    }
    .title($r('app.string.route_detail_title'))
    .backgroundColor(AppColor.bgPage)
    .onReady((context: NavDestinationContext) => {
      if (context.pathInfo.param !== undefined) {
        const param: DetailParam = context.pathInfo.param as DetailParam;
        this.detailCode = param.code;
      }
      this.load();
    })
  }
}
