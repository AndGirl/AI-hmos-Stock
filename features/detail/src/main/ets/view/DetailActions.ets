import { promptAction, UIContext } from '@kit.ArkUI';
import { AppColor } from 'commons_ui';
import { DetailAction } from '../viewmodel/DetailVM';

function button(text: Resource): promptAction.Button {
  const item: promptAction.Button = {
    text: text,
    color: AppColor.textPrimary
  };
  return item;
}

/**
 * 详情「更多」菜单：page 的动作栏与 compact 的「⋯」共用同一套动作。
 * 只做动作分发，不包含导航（导航归壳层，INV-D1）。
 * compact（pane / window 右栏）不提供「去交易」入口（FR-07.11 / AC-75）。
 */
export function showDetailActionMenu(uiContext: UIContext, compact: boolean,
  handler: (action: DetailAction) => void): void {
  const b0: promptAction.Button = button($r('app.string.detail_action_watchlist'));
  const b1: promptAction.Button = button($r('app.string.detail_action_pk'));
  const b2: promptAction.Button = button($r('app.string.detail_action_trade'));
  if (compact) {
    const two: [promptAction.Button, promptAction.Button] = [b0, b1];
    uiContext.getPromptAction().showActionMenu({ title: '', buttons: two })
      .then((res: promptAction.ActionMenuSuccessResponse): void => {
        if (res.index === 0) {
          handler('watchlist');
        } else if (res.index === 1) {
          handler('pk');
        }
      })
      .catch((): void => {
      });
    return;
  }
  const three: [promptAction.Button, promptAction.Button, promptAction.Button] = [b0, b1, b2];
  uiContext.getPromptAction().showActionMenu({ title: '', buttons: three })
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
