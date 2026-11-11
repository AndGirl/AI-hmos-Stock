import { promptAction, UIContext } from '@kit.ArkUI';
import { AppColor } from 'commons_ui';
import { DetailAction } from '../viewmodel/DetailVM';

/**
 * 详情「更多」菜单：page 的动作栏与 compact 的「⋯」共用同一套动作。
 * 只做动作分发，不包含导航（导航归壳层，INV-D1）。
 */
export function showDetailActionMenu(uiContext: UIContext, handler: (action: DetailAction) => void): void {
  const b0: promptAction.Button = {
    text: $r('app.string.detail_action_watchlist'),
    color: AppColor.textPrimary
  };
  const b1: promptAction.Button = {
    text: $r('app.string.detail_action_pk'),
    color: AppColor.textPrimary
  };
  const b2: promptAction.Button = {
    text: $r('app.string.detail_action_trade'),
    color: AppColor.textPrimary
  };
  const buttons: [promptAction.Button, promptAction.Button, promptAction.Button] = [b0, b1, b2];
  uiContext.getPromptAction().showActionMenu({ title: '', buttons: buttons })
    .then((res: promptAction.ActionMenuSuccessResponse): void => {
      if (res.index === 0) {
        handler('watchlist');
      } else if (res.index === 1) {
        handler('pk');
      } else if (res.index === 2) {
        handler('trade');
      }
    })
    .catch((): void => {
    });
}
