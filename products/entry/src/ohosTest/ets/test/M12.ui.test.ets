import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry, Component, Driver, ON } from '@kit.TestKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { sharedDriver } from './TestDriver';

const DOMAIN: number = 0x0001;
const TAG: string = 'M12UiTest';
const BUNDLE: string = 'com.example.xiaoyangstock';
const ABILITY: string = 'EntryAbility';

async function startApp(driver: Driver): Promise<void> {
  const want: Want = { bundleName: BUNDLE, abilityName: ABILITY };
  await abilityDelegatorRegistry.getAbilityDelegator().startAbility(want);
  await driver.delayMs(1200);
}

/** 回到底部「自选」Tab（最多重试 3 次：返回 → 点自选）。 */
async function ensureWatchlistPage(driver: Driver): Promise<void> {
  for (let i = 0; i < 3; i++) {
    const title: Component | null = await driver.waitForComponent(ON.text('自选股'), 1000);
    if (title !== null) {
      return;
    }
    const tab: Component | null = await driver.waitForComponent(ON.text('自选'), 800);
    if (tab !== null) {
      await tab.click();
      await driver.delayMs(600);
      continue;
    }
    await driver.pressBack();
    await driver.delayMs(600);
  }
  throw new Error('cannot reach watchlist page');
}

/** 确保列表视图（`view_pref_v1` 可能残留卡片态）。 */
async function ensureListView(driver: Driver): Promise<void> {
  const table: Component | null = await driver.waitForComponent(ON.id('list_table'), 2000);
  if (table !== null) {
    return;
  }
  const toggle: Component | null = await driver.waitForComponent(ON.id('view_switch'), 2000);
  if (toggle !== null) {
    await toggle.click();
    await driver.delayMs(600);
  }
}

/** 点冻结表第一行进入详情（行点击挂在 Row 上；避免点到顶部指数条的同名文本）。 */
async function openFirstDetail(driver: Driver): Promise<boolean> {
  const table: Component | null = await driver.waitForComponent(ON.id('list_table'), 2500);
  if (table === null) {
    return false;
  }
  const bounds = await table.getBounds();
  // list_table 含 40vp 表头 + 56vp 行：+120 落在第二行价格区，避开表头排序。
  await driver.click(600, bounds.top + 120);
  await driver.delayMs(2000);
  return true;
}

/**
 * M12 横屏与深色 UI 自动化（AC-122）。
 * 说明：
 * - 旋转与系统深色无法由 UiTest 直接触发，本套件只断言「详情页按窗口宽高进入横屏布局分支」；
 *   62/38 与深色色值以 `ui layout` + 截图取证（见 validation/phase2-m12-test-cases.md）。
 * - 前置：设备已安装同版本 debug HAP；首次运行前 `param set persist.ace.testmode.enabled 1`。
 */
export default function m12UiTest(): void {
  describe('M12UiTest', () => {
    const driver: Driver = sharedDriver();

    it('AC122_detail_landscape_branch_by_display', 0, async (done: Function) => {
      await startApp(driver);
      await ensureWatchlistPage(driver);
      await ensureListView(driver);
      const opened: boolean = await openFirstDetail(driver);
      expect(opened).assertTrue();
      // 详情根节点 id 是布局分支的直接证据；「今开」只是内容探针，加载慢时不做硬断言
      const landRoot: Component | null = await driver.waitForComponent(ON.id('detail_landscape'), 5000);
      const portRoot: Component | null = landRoot === null ?
        await driver.waitForComponent(ON.id('detail_layout'), 1500) : null;
      const detailRoot: Component | null = landRoot !== null ? landRoot : portRoot;
      expect(detailRoot !== null).assertTrue();
      const detail: Component | null = await driver.waitForComponent(ON.text('今开'), 4000);
      if (detail === null) {
        hilog.warn(DOMAIN, TAG, 'metric 今开 not found in 4s (layout branch already asserted)');
      }

      const size = await driver.getDisplaySize();
      const landscape: boolean = size.x > size.y;
      hilog.info(DOMAIN, TAG, 'display=%{public}dx%{public}d landscape=%{public}s',
        size.x, size.y, `${landscape}`);
      if (landscape) {
        expect(landRoot !== null).assertTrue();
      } else {
        expect(portRoot !== null).assertTrue();
      }

      await driver.pressBack();
      await driver.delayMs(700);
      hilog.info(DOMAIN, TAG, 'AC122 landscape branch ok');
      done();
    });
  });
}
