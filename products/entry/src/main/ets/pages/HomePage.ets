import { ComingSoonText } from 'commons_basic';
import { PlaceholderPage } from '../shell/PlaceholderPage';

/** 首页 Tab（占位，G1）：整页空态，只有标题与「首页下阶段开放」。 */
@ComponentV2
export struct HomePage {
  build() {
    PlaceholderPage({
      pageTitle: $r('app.string.placeholder_home_title'),
      pageDesc: ComingSoonText.HOME
    })
  }
}
