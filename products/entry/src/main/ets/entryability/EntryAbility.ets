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
import { BreakpointHost, ConfigHost, SafeAreaHost } from 'commons_basic';
import { DeepLinkHandler } from '../router/DeepLinkHandler';

const DOMAIN = 0x0000;

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      // 本期只交付浅色 token，强制浅色避免系统深色下出现未定义配色（§6.2）。
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
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
    // 冷启动深链：先暂存，UI 就绪后由 AppRoot 消费（§3.2）。
    DeepLinkHandler.handle(want.uri);
  }

  onConfigurationUpdate(newConfig: Configuration): void {
    ConfigHost.update(newConfig.fontSizeScale);
    hilog.info(DOMAIN, 'testTag', 'onConfigurationUpdate fontSizeScale=%{public}s', `${newConfig.fontSizeScale}`);
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
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, 'testTag', '%{public}s', 'Ability onBackground');
  }
}
