import { window } from '@kit.ArkUI';
import { AppColor, AppDim } from 'commons_ui';
import { ConnectionHost, ConnectionHub } from 'commons_basic';
import { AddGroupVM, AddSubmitResult, AddWatchlistVM } from '../viewmodel/AddWatchlistVM';
import { SearchRowVM } from '../viewmodel/SearchRowVM';
import { SearchBar } from './SearchBar';
import { SearchBody } from './SearchBody';

/**
 * 添加自选面板（M7-2/M7-3）：
 * 页头（返回 / 标题 / N/50）+ 搜索条 + 目标分组 chips + 结果多选 + 底部「加入自选（N）」。
 * 容器形态由入口壳决定（sm/md 全屏、lg/xl 居中 560vp），本组件只负责内容。
 */
@ComponentV2
export struct AddWatchlistPanel {
  @Param vm: AddWatchlistVM = new AddWatchlistVM();
  @Param currentGroupId: string = '';
  @Param presetCode: string = '';
  /** 入口来源（watchlist/detail/search/pane），只透传给 VM 做埋点维度。 */
  @Param fromSource: string = '';
  @Event onClose: () => void = (): void => {
  };
  /** 连接态：页面打开期间断线/恢复时刷新离线提示与容量（AC-96）。 */
  @Local hub: ConnectionHub = ConnectionHost.getService();
  /** 键盘高度：底部「加入自选」必须落在键盘上沿（否则被键盘盖住无法提交）。 */
  @Local keyboardVp: number = 0;
  private hostWindow: window.Window | undefined = undefined;
  private detached: boolean = false;

  aboutToAppear(): void {
    this.vm.init(this.currentGroupId, this.presetCode, this.fromSource);
    window.getLastWindow(getContext(this)).then((win: window.Window): void => {
      if (this.detached) {
        return;
      }
      this.hostWindow = win;
      win.on('keyboardHeightChange', (height: number): void => {
        try {
          this.keyboardVp = this.getUIContext().px2vp(height);
        } catch (err) {
          this.keyboardVp = 0;
        }
      });
    }).catch((): void => {
    });
  }

  aboutToDisappear(): void {
    this.detached = true;
    if (this.hostWindow !== undefined) {
      this.hostWindow.off('keyboardHeightChange');
      this.hostWindow = undefined;
    }
    this.vm.dispose();
  }

  /** 结果/浏览列表重建后把勾选态刷回新行对象（SearchRowVM 是新的）。 */
  @Monitor('vm.search.resultVersion')
  onRowsChanged(): void {
    this.vm.reapplyPicks();
  }

  /** 断网/恢复：页内「当前离线，加入后将标记待同步」实时跟随（提交本身以 hub 实时状态为准）。 */
  @Monitor('hub.state')
  onConnectionChanged(): void {
    this.vm.refresh();
  }

  private groupLabel(group: AddGroupVM): ResourceStr {
    if (!group.system) {
      if (group.name.length > 0) {
        return group.name;
      }
      // 阶段一遗留的用户组 id `user` 无自带 name，显示名走 i18n（改名后才有 name）。
      return group.id === 'user' ? $r('app.string.watch_group_user') : group.name;
    }
    if (group.id === 'fin') {
      return $r('app.string.watch_group_fin');
    }
    if (group.id === 'star') {
      return $r('app.string.watch_group_star');
    }
    if (group.id === 'kcb') {
      return $r('app.string.watch_group_kcb');
    }
    return group.name;
  }

  private toast(message: ResourceStr): void {
    this.getUIContext().getPromptAction().showToast({ message: message, duration: 1800 });
  }

  private async submit(): Promise<void> {
    const result: AddSubmitResult = await this.vm.submit();
    if (result.reason === 'none') {
      this.toast($r('app.string.add_none_selected'));
      return;
    }
    if (result.reason === 'failed') {
      this.toast($r('app.string.add_failed'));
      return;
    }
    // 竞态兜底：勾选后被别处加过，提交只剩「已存在」时不报「已加入 0 只」。
    if (result.added === 0 && result.limit === 0 && result.existed > 0) {
      this.toast($r('app.string.add_all_existed'));
      this.onClose();
      return;
    }
    if (result.done) {
      if (result.pending > 0) {
        this.toast($r('app.string.add_pending_toast', `${result.added}`));
      } else {
        this.toast($r('app.string.add_added_toast', `${result.added}`));
      }
      this.onClose();
      return;
    }
    if (result.added === 0 && result.limit > 0) {
      this.toast($r('app.string.add_limit_hint', `${this.vm.maxItems}`));
      return;
    }
    // AC-96 / C7：部分成功时列出超限标的名称（最多 3 个），不再只报个数。
    const names: string = this.vm.limitSummary(result.limitCodes);
    if (names.length > 0) {
      this.toast($r('app.string.add_partial_hint_names', `${result.added}`, `${result.limit}`, names));
      return;
    }
    this.toast($r('app.string.add_partial_hint', `${result.added}`, `${result.limit}`));
  }

  private async updatePresetGroups(): Promise<void> {
    const ok: boolean = await this.vm.updatePresetGroups();
    this.toast(ok ? $r('app.string.add_group_updated') : $r('app.string.add_failed'));
  }

  private hasTarget(): boolean {
    for (let i = 0; i < this.vm.groups.length; i++) {
      if (this.vm.groups[i].selected) {
        return true;
      }
    }
    return false;
  }

  @Builder
  header() {
    Row() {
      Text('‹')
        .fontSize(26)
        .fontColor(AppColor.textPrimary)
        .width(44)
        .height(44)
        .textAlign(TextAlign.Center)
        .accessibilityText($r('app.string.search_cancel'))
        .onClick(() => {
          this.onClose();
        })
      Text($r('app.string.add_title'))
        .fontSize(17)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppColor.textPrimary)
        .layoutWeight(1)
      Text(`${this.vm.count}/${this.vm.maxItems}`)
        .fontSize(13)
        .fontColor(this.vm.limitReached ? AppColor.error : AppColor.textSecondary)
        .margin({ right: AppDim.gap16 })
    }
    .width('100%')
    .height(52)
    .alignItems(VerticalAlign.Center)
    .border({ width: { bottom: 0.5 }, color: AppColor.divider })
  }

  @Builder
  groupChips() {
    Column() {
      Scroll() {
        Row() {
          ForEach(this.vm.groups, (group: AddGroupVM) => {
            Row() {
              Text(this.groupLabel(group))
                .fontSize(12)
                .fontColor(group.selected ? AppColor.accent : AppColor.textSecondary)
                .maxLines(1)
              Text(`${group.count}`)
                .fontSize(11)
                .fontColor(group.selected ? AppColor.accent : AppColor.textSecondary)
                .margin({ left: 2 })
                .maxLines(1)
            }
            .height(28)
            .padding({ left: AppDim.gap12, right: AppDim.gap12 })
            .borderRadius(14)
            .margin({ right: AppDim.gap8 })
            .backgroundColor(group.selected ? AppColor.accentSoft : AppColor.disabledBg)
            .alignItems(VerticalAlign.Center)
            .onClick(() => {
              this.vm.toggleGroup(group.id);
            })
          }, (group: AddGroupVM) => group.id)
        }
        .height(36)
        .alignItems(VerticalAlign.Center)
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      .width('100%')
      .height(36)

      if (!this.hasTarget()) {
        Text($r('app.string.add_target_auto'))
          .fontSize(10)
          .fontColor(AppColor.textSecondary)
          .maxLines(1)
      }
    }
    .width('100%')
    .padding({ left: AppDim.gap16, right: AppDim.gap16 })
    .alignItems(HorizontalAlign.Start)
  }

  /** 详情入口预置标的：直接在页头下方展示归属，不必再去结果里找。 */
  @Builder
  presetStrip() {
    Row() {
      Column() {
        Text(this.vm.presetName.length > 0 ? this.vm.presetName : this.vm.presetCode)
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppColor.textPrimary)
          .maxLines(1)
        Text(this.vm.presetAdded ?
          $r('app.string.add_preset_added_groups', `${this.vm.presetGroupCount}`) :
          $r('app.string.add_preset_not_added'))
          .fontSize(11)
          .fontColor(AppColor.textSecondary)
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      if (this.vm.presetAdded && this.hasTarget()) {
        Text($r('app.string.add_group_update'))
          .fontSize(12)
          .fontColor(AppColor.accent)
          .height(32)
          .padding({ left: AppDim.gap12, right: AppDim.gap12 })
          .borderRadius(16)
          .border({ width: 1, color: AppColor.accent })
          .textAlign(TextAlign.Center)
          .onClick(() => {
            this.updatePresetGroups();
          })
      }
    }
    .width('100%')
    .padding({ left: AppDim.gap16, right: AppDim.gap16, top: AppDim.gap8, bottom: AppDim.gap8 })
    .alignItems(VerticalAlign.Center)
    .backgroundColor(AppColor.bgSurface)
  }

  @Builder
  hintBar() {
    if (this.vm.offline || this.vm.limitReached) {
      Row() {
        Text(this.vm.offline ? $r('app.string.add_offline_hint') :
          $r('app.string.add_limit_hint', `${this.vm.maxItems}`))
          .fontSize(11)
          .fontColor(AppColor.textSecondary)
          .layoutWeight(1)
      }
      .width('100%')
      .height(28)
      .padding({ left: AppDim.gap16, right: AppDim.gap16 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor(AppColor.bgSurface)
    }
  }

  @Builder
  footer() {
    Row() {
      Text(this.vm.pickedCount > 0 ?
        $r('app.string.add_join_count', `${this.vm.pickedCount}`) : $r('app.string.add_join'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.vm.pickedCount > 0 ? AppColor.textOnAccent : AppColor.disabledText)
        .height(44)
        .width('100%')
        .textAlign(TextAlign.Center)
        .backgroundColor(this.vm.pickedCount > 0 ? AppColor.accentFill : AppColor.disabledBg)
        .borderRadius(AppDim.pillRadius)
        .enabled(this.vm.pickedCount > 0 && !this.vm.submitting)
        .accessibilityText($r('app.string.add_join'))
        .onClick(() => {
          this.submit();
        })
    }
    .width('100%')
    .padding({ left: AppDim.gap16, right: AppDim.gap16, top: AppDim.gap8, bottom: AppDim.gap8 })
    .border({ width: { top: 0.5 }, color: AppColor.divider })
  }

  build() {
    Column() {
      this.header()

      SearchBar({
        term: this.vm.search.term,
        autoFocus: true,
        onTermChange: (text: string): void => {
          this.vm.search.onTermChange(text);
        },
        onSubmit: (): void => {
          this.vm.search.submit();
        }
      })

      this.groupChips()

      if (this.vm.presetCode.length > 0) {
        this.presetStrip()
      }

      this.hintBar()

      SearchBody({
        vm: this.vm.search,
        mode: 'add',
        pickMode: true,
        onRowTap: (row: SearchRowVM): void => {
          this.vm.togglePick(row);
        }
      })
        .layoutWeight(1)

      this.footer()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppColor.bgPage)
    // 键盘上沿让位：底部提交按钮始终可点（与交易弹窗同一套兜底）。
    .padding({ bottom: this.keyboardVp })
  }
}
