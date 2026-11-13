import { AppColor, AppDim, StateMode, StateView } from 'commons_ui';
import { SearchRowVM } from '../viewmodel/SearchRowVM';
import { SearchVM } from '../viewmodel/SearchVM';
import { HotWordsView } from './HotWords';
import { SearchHistoryView } from './SearchHistory';
import { SearchRowView } from './SearchRowView';
import { SearchSections } from './SearchSections';
import { SearchStatesView } from './SearchStates';

/**
 * 搜索主体（M6-4）：输入历史/热搜、六态、结果分段与展开。
 * `mode='add'` 由 M7 添加页复用（同一套输入/防抖/结果，只换底部选择栏）。
 */
@ComponentV2
export struct SearchBody {
  @Param vm: SearchVM = new SearchVM();
  @Param mode: string = 'search';
  @Event onRowTap: (row: SearchRowVM) => void = (row: SearchRowVM): void => {
  };
  @Event onRowAdd: (row: SearchRowVM) => void = (row: SearchRowVM): void => {
  };

  build() {
    Column() {
      // 搜索中：保留上一帧结果 + 顶部 2vp 进度条，不整页骨架（G-1）。
      if (this.vm.searching) {
        Progress({ value: 60, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(2)
          .color(AppColor.accent)
          .backgroundColor(AppColor.divider)
      }

      if (this.vm.state === 'initial' && !this.vm.hasQuery()) {
        this.initialBrowse()
      } else if (this.vm.state === 'empty' || this.vm.state === 'error' ||
        this.vm.state === 'rateLimited') {
        // 异常/空态优先于旧结果渲染：失败后不能继续显示上一帧结果（AC-92）。
        SearchStatesView({
          state: this.vm.state,
          suggestions: this.vm.suggestions,
          cooldownLeft: this.vm.cooldownLeft,
          onRetry: (): void => {
            this.vm.retry();
          },
          onPick: (text: string): void => {
            this.vm.pickQuery(text);
          }
        })
          .layoutWeight(1)
      } else if (this.vm.items.length > 0) {
        SearchSections({
          items: this.vm.items,
          showAdd: this.mode === 'search',
          onTapRow: (row: SearchRowVM): void => {
            this.onRowTap(row);
          },
          onAddRow: (row: SearchRowVM): void => {
            this.onRowAdd(row);
          },
          onToggle: (sectionIndex: number): void => {
            this.vm.toggleSection(sectionIndex);
          }
        })
      } else {
        // searching（首次查询，尚无上一帧）/ offline（无结果）：留白 + 顶部进度条，不做整页骨架。
        Column()
          .width('100%')
          .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColor.bgPage)
  }

  /**
   * 空关键词初始态（M6 追加）：历史 + 热搜 + 全部股票列表。
   * 下拉刷新（Refresh）与上拉加载（onReachEnd）共用同一个 List；不用 Scroll 套 List，避免手势冲突。
   */
  @Builder
  initialBrowse() {
    Refresh({ refreshing: this.vm.refreshing }) {
      List() {
        if (this.vm.history.length > 0) {
          ListItem() {
            SearchHistoryView({
              items: this.vm.history,
              onPick: (text: string): void => {
                this.vm.pickQuery(text);
              },
              onRemove: (text: string): void => {
                this.vm.removeHistory(text);
              },
              onClear: (): void => {
                this.confirmClearHistory();
              }
            })
          }
        }

        ListItem() {
          HotWordsView({
            words: this.vm.hot,
            state: this.vm.hotState,
            onPick: (text: string): void => {
              this.vm.pickQuery(text);
            }
          })
            .margin({ top: AppDim.gap8 })
        }

        // 8vp 浅灰分隔块：把「热门搜索」与「全部股票」分成两组
        ListItem() {
          Row()
            .width('100%')
            .height(8)
            .backgroundColor(AppColor.disabledBg)
        }
        .height(8)

        // 「全部股票」作为 ListItemGroup 的吸顶头：滚动到顶后固定，股票行在其下滚动
        ListItemGroup({ header: this.browseHeader() }) {

        if (this.vm.browseRows.length === 0) {
          if (this.vm.browseState === 'loading') {
            ListItem() {
              Column() {
                LoadingProgress()
                  .width(28)
                  .height(28)
                  .color(AppColor.accent)
                Text($r('app.string.loading'))
                  .fontSize(12)
                  .fontColor(AppColor.textSecondary)
                  .margin({ top: AppDim.gap8 })
              }
              .width('100%')
              .height(200)
              .justifyContent(FlexAlign.Center)
            }
          } else if (this.vm.browseState === 'error') {
            ListItem() {
              StateView({
                mode: StateMode.ERROR,
                stateDesc: $r('app.string.search_browse_failed'),
                showAction: true,
                actionLabel: $r('app.string.retry'),
                onAction: (): void => {
                  this.vm.retryBrowse();
                }
              })
                .width('100%')
                .height(240)
            }
          } else {
            ListItem() {
              Text($r('app.string.search_browse_empty'))
                .fontSize(13)
                .fontColor(AppColor.textSecondary)
                .width('100%')
                .height(160)
                .textAlign(TextAlign.Center)
            }
          }
        } else {
          ForEach(this.vm.browseRows, (row: SearchRowVM) => {
            ListItem() {
              SearchRowView({
                row: row,
                showAdd: this.mode === 'search',
                onTap: (tapped: SearchRowVM): void => {
                  this.onRowTap(tapped);
                },
                onAdd: (target: SearchRowVM): void => {
                  this.onRowAdd(target);
                }
              })
            }
          }, (row: SearchRowVM) => `${this.vm.browseVersion}-${row.code}`)

          if (this.vm.loadingMore) {
            ListItem() {
              this.footerLoading()
            }
          } else if (this.vm.browseState === 'error') {
            ListItem() {
              this.footerLoadMoreFailed()
            }
          } else if (this.vm.allLoaded()) {
            ListItem() {
              this.footerAllLoaded()
            }
          }
        }
        }
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      .sticky(StickyStyle.Header)
      .onReachEnd(() => {
        this.vm.loadMore();
      })
    }
    .width('100%')
    .layoutWeight(1)
    .onRefreshing(() => {
      this.vm.refreshBrowse();
    })
  }

  /** 「全部股票」吸顶分组头（高度 36，白底，滚动到顶后固定）。 */
  @Builder
  browseHeader() {
    Row() {
      Text($r('app.string.search_browse_title'))
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColor.textPrimary)
      Blank()
      if (this.vm.browseTotal > 0) {
        Text($r('app.string.search_browse_total', this.vm.browseTotal.toString()))
          .fontSize(11)
          .fontColor(AppColor.textSecondary)
      }
    }
    .width('100%')
    .height(36)
    .padding({ left: AppDim.gap16, right: AppDim.gap16 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(AppColor.bgPage)
  }

  @Builder
  footerLoading() {
    Row() {
      LoadingProgress()
        .width(16)
        .height(16)
        .color(AppColor.textSecondary)
        .margin({ right: AppDim.gap8 })
      Text($r('app.string.search_loading_more'))
        .fontSize(12)
        .fontColor(AppColor.textSecondary)
    }
    .width('100%')
    .height(44)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  footerLoadMoreFailed() {
    Row() {
      Text($r('app.string.search_load_more_failed'))
        .fontSize(13)
        .fontColor(AppColor.accent)
    }
    .width('100%')
    .height(44)
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.vm.retryBrowse();
    })
  }

  /** 全部加载完：醒目提示 + 具体数值（AC-92 追加口径）。 */
  @Builder
  footerAllLoaded() {
    Row() {
      Text($r('app.string.search_all_loaded', this.vm.browseRows.length.toString(),
        this.vm.browseTotal.toString()))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColor.textPrimary)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .height(48)
    .padding({ left: AppDim.gap16, right: AppDim.gap16 })
    .justifyContent(FlexAlign.Center)
    .backgroundColor(AppColor.bgSurface)
  }

  /** 清空历史二次确认（AC-90）。 */
  private confirmClearHistory(): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.search_history_clear'),
      message: $r('app.string.search_history_clear_confirm'),
      primaryButton: {
        value: $r('app.string.search_cancel'),
        action: (): void => {
        }
      },
      secondaryButton: {
        value: $r('app.string.search_history_clear'),
        action: (): void => {
          this.vm.clearHistory();
        }
      }
    });
  }
}
