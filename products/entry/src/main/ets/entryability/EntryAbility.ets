/*
 * Copyright (c) 2026 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { AbilityConstant, Configuration, ConfigurationConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import { BackDispatcher, BreakpointHost, ConfigHost, OrientationHost, SafeAreaHost, StartupMeter } from 'commons_basic';
import { DataServices, StorageAdapter } from 'commons_data';
import { DeepLinkHandler } from '../router/DeepLinkHandler';

const DOMAIN = 0x0000;

/** 系统 ColorMode → 应用外观名（未知/未设置按浅色）。 */
function colorModeName(mode: ConfigurationConstant.ColorMode | undefined): string {
  return mode === ConfigurationConstant.ColorMode.COLOR_MODE_DARK ? 'dark' : 'light';
}

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    // 冷启打点起点（M13-2）：进程启动时刻与 onCreate 时刻都取同一时钟（ms since boot）。
    StartupMeter.markProcessStart();
    try {
      // M12-2：不再强制浅色，跟随系统深/浅色（深色资源见 commons/ui/resources/dark）。
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      hilog.error(DOMAIN, 'testTag', 'Failed to set colorMode. Cause: %{public}s', JSON.stringify(err));
    }
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onCreate');
    // 字号缩放要在首帧前就绪：表格列宽按 fontScale 等比放大（CC-6.5）。
    try {
      ConfigHost.update(this.context.config.fontSizeScale);
      hilog.info(DOMAIN, 'testTag', 'fontSizeScale=%{public}s', `${this.context.config.fontSizeScale}`);
    } catch (err) {
      hilog.warn(DOMAIN, 'testTag', 'read fontSizeScale failed: %{public}s', JSON.stringify(err));
    }
    // 深浅色（M12-2）：首帧前写入，图表等命令式绘制组件据此解析配色。
    try {
      ConfigHost.updateColorMode(colorModeName(this.context.config.colorMode));
      hilog.info(DOMAIN, 'testTag', 'colorMode=%{public}s', colorModeName(this.context.config.colorMode));
    } catch (err) {
      hilog.warn(DOMAIN, 'testTag', 'read colorMode failed: %{public}s', JSON.stringify(err));
    }
    // 存储入口注入（§5.5）：搜索历史 / 自选写盘都在首帧前具备能力。
    StorageAdapter.init(this.context);
    // 视图偏好预热（M8-4）：预读 `view_pref_v1` 写进 ConfigService，
    // 页面出内容前还会再 await 一次同一个 Promise，因此冷启不会「先列表后卡片」。
    DataServices.viewPref().load().then((): void => {
      const mode: string = DataServices.viewPref().current();
      ConfigHost.getService().applyViewMode(mode);
      hilog.info(DOMAIN, 'testTag', 'viewMode=%{public}s', mode);
    }).catch((err: BusinessError): void => {
      hilog.warn(DOMAIN, 'testTag', 'preheat viewMode failed: %{public}s', JSON.stringify(err));
    });
    // 行情缓存预热（M9-6）：首帧前把 `quote_cache_v1` 读进内存，
    // 自选页 `loadCached()` 就能直接命中，AC-111 要求 ≤800ms 出内容。
    DataServices.quoteCache().load().then((): void => {
      hilog.info(DOMAIN, 'testTag', 'quoteCache ready size=%{public}d', DataServices.quoteCache().size());
    }).catch((err: BusinessError): void => {
      hilog.warn(DOMAIN, 'testTag', 'preheat quoteCache failed: %{public}s', JSON.stringify(err));
    });
    // 隐私同意预热（M13-1）：首帧前读 `privacy_consent_v1`，`Index` 只等同一个 Promise，
    // 已同意则不出现骨架闪烁，未同意则直接落到同意页（不渲染 TabShell）。
    DataServices.privacyConsent().load().then((): void => {
      hilog.info(DOMAIN, 'testTag', 'consent ready=%{public}s',
        DataServices.privacyConsent().consented() ? 'true' : 'false');
    }).catch((err: BusinessError): void => {
      hilog.warn(DOMAIN, 'testTag', 'preheat consent failed: %{public}s', JSON.stringify(err));
    });
    // 首笔风险揭示标记（M13-1）：与本机其它偏好一样在首帧前就绪，交易确认层直接读内存。
    DataServices.riskNotice().load().catch((err: BusinessError): void => {
      hilog.warn(DOMAIN, 'testTag', 'preheat risk failed: %{public}s', JSON.stringify(err));
    });
    // 稳定性采集（M13-3）：会话 +1、挂 HiAppEvent（崩溃/冻屏）与 errorManager（JS 异常/拒绝）。
    // 只记本机计数，不上报、不采集任何个人信息。
    DataServices.stability().start();
    // 冷启动深链：先暂存，UI 就绪后由 AppRoot 消费（§3.2）。
    DeepLinkHandler.handle(want.uri);
  }

  /**
   * 系统返回键（M8，关闭 M7 遗留 §9-28⑥）：
   * 自选页没有 NavDestination 挂点，分组管理浮层 / 编辑态 / 比价多选态通过
   * `BackDispatcher` 先退一层；没有页面消费时返回 false，交给系统（退出/回桌面）。
   */
  onBackPressed(): boolean {
    if (BackDispatcher.handle()) {
      hilog.info(DOMAIN, 'testTag', 'back consumed by page');
      return true;
    }
    return false;
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    ConfigHost.update(newConfig.fontSizeScale);
    // M12-2 / M12-5：热切深浅色只更新配置，不触发任何 load()（状态保留）。
    const mode: string = colorModeName(newConfig.colorMode);
    ConfigHost.updateColorMode(mode);
    hilog.info(DOMAIN, 'testTag', 'onConfigurationUpdate fontSizeScale=%{public}s colorMode=%{public}s',
      `${newConfig.fontSizeScale}`, mode);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onNewWant');
    // 热启动深链：UI 已就绪，直接分发。
    DeepLinkHandler.handle(want.uri);
  }

  onDestroy(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err: BusinessError) => {
      if (err.code) {
        hilog.error(DOMAIN, 'testTag', 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      // 首帧内容就绪后再挂断点/安全区监听，保证窗口尺寸与 UIContext 均可用（§3.2）。
      const mainWindow: window.Window = windowStage.getMainWindowSync();
      BreakpointHost.init(mainWindow, mainWindow.getUIContext());
      // 屏幕方向（M12-1）：应用不全局锁方向，详情页可见时再允许旋转。
      OrientationHost.init(mainWindow);
      // 全屏布局：页面背景延伸到状态栏/导航条，再由 SafeAreaService 做内容避让（§5.1.2）。
      mainWindow.setWindowLayoutFullScreen(true).then(() => {
        hilog.info(DOMAIN, 'testTag', 'Succeeded in setting full-screen layout.');
        SafeAreaHost.init(mainWindow);
      }).catch((error: BusinessError) => {
        hilog.error(DOMAIN, 'testTag', 'Failed to set full screen. Cause: %{public}s', JSON.stringify(error));
        SafeAreaHost.init(mainWindow);
      });
      hilog.info(DOMAIN, 'testTag', 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    SafeAreaHost.detach();
    BreakpointHost.detach();
    OrientationHost.detach();
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
