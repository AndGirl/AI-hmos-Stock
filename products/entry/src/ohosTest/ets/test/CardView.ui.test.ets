import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry, Component, Driver, ON } from '@kit.TestKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { dismissConsentIfShown, seedCompliance, sharedDriver } from './TestDriver';

const DOMAIN: number = 0x0001;
const TAG: string = 'CardViewUiTest';
const BUNDLE: string = 'com.example.xiaoyangstock';
const ABILITY: string = 'EntryAbility';

/** 启动被测应用（AbilityDelegator 拉起 EntryAbility；已在前台时等价于 bringToFront）。 */
async function startApp(driver: Driver): Promise<void> {
  // M13-1：隐私同意基线（首启同意页会挡住全部入口；已同意时是空操作）。
  await seedCompliance();
  const want: Want = { bundleName: BUNDLE, abilityName: ABILITY };
  await abilityDelegatorRegistry.getAbilityDelegator().startAbility(want);
  await driver.delayMs(1200);
  await dismissConsentIfShown(driver);
}

/** 从任意页回到底部「自选」Tab（最多重试 3 次：返回 → 点自选）。 */
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

/** 点分组栏右侧的视图切换按钮（图标按钮，只有 id 可稳定定位）。 */
async function toggleView(driver: Driver): Promise<boolean> {
  const button: Component | null = await driver.waitForComponent(ON.id('view_switch'), 2000);
  if (button === null) {
    return false;
  }
  await button.click();
  await driver.delayMs(600);
  return true;
}

/** 当前是否为卡片视图（Grid 根节点 id）。 */
async function isCardView(driver: Driver): Promise<boolean> {
  const grid: Component | null = await driver.waitForComponent(ON.id('card_grid'), 2500);
  return grid !== null;
}

/** 当前是否为列表视图（冻结表根节点 id）。 */
async function isListView(driver: Driver): Promise<boolean> {
  const table: Component | null = await driver.waitForComponent(ON.id('list_table'), 2500);
  return table !== null;
}

/** 确保回到列表视图（用例之间互不影响）。 */
async function ensureListView(driver: Driver): Promise<void> {
  if (await isCardView(driver)) {
    await toggleView(driver);
    await driver.delayMs(400);
  }
}

/**
 * M8 卡片视图 UI 自动化（AC-100/101/102/103）。
 * 前置：设备已安装同版本 debug HAP；首次运行前需：
 *   hdc -t <serial> shell param set persist.ace.testmode.enabled 1
 * 说明：`onDeviceTest` 会重装应用，`view_pref_v1` 随之清空 → 初态为列表视图。
 */
export default function cardViewUiTest(): void {
  describe('CardViewUiTest', () => {
    const driver: Driver = sharedDriver();

    it('AC100_switch_to_card_and_back', 0, async (done: Function) => {
      await startApp(driver);
      await ensureWatchlistPage(driver);
      await ensureListView(driver);
      const switched: boolean = await toggleView(driver);
      expect(switched).assertTrue();
      const card: boolean = await isCardView(driver);
      expect(card).assertTrue();
      // 切回列表：视图形态与数据都不丢
      const back: boolean = await toggleView(driver);
      expect(back).assertTrue();
      const list: boolean = await isListView(driver);
      expect(list).assertTrue();
      hilog.info(DOMAIN, TAG, 'AC100 switch ok');
      done();
    });

    it('AC101_card_shows_name_price_and_metrics', 0, async (done: Function) => {
      await startApp(driver);
      await ensureWatchlistPage(driver);
      await ensureListView(driver);
      await toggleView(driver);
      expect(await isCardView(driver)).assertTrue();
      // 卡面固定指标（sm/md 都展示今开）与名称、价格
      const open: Component | null = await driver.waitForComponent(ON.text('今开'), 2500);
      expect(open !== null).assertTrue();
      const name: Component | null = await driver.waitForComponent(ON.text('贵州茅台'), 2500);
      expect(name !== null).assertTrue();
      await ensureListView(driver);
      hilog.info(DOMAIN, TAG, 'AC101 card content ok');
      done();
    });

    it('AC102_sort_chip_visible_and_clearable', 0, async (done: Function) => {
      await startApp(driver);
      await ensureWatchlistPage(driver);
      await ensureListView(driver);
      // 列表态：列头点「涨跌幅」→ 降序（与卡片 chip 共用同一 SortState）
      const header: Component | null = await driver.waitForComponent(ON.text('涨跌幅'), 2500);
      expect(header !== null).assertTrue();
      if (header !== null) {
        const bounds = await header.getBounds();
        await driver.click(Math.floor((bounds.left + bounds.right) / 2),
          Math.floor((bounds.top + bounds.bottom) / 2));
        await driver.delayMs(700);
      }
      await toggleView(driver);
      // 卡片态：分组栏下方出现 chip「按涨跌幅↓」
      const chip: Component | null = await driver.waitForComponent(ON.text('按涨跌幅↓'), 2500);
      expect(chip !== null).assertTrue();
      // 清除后回到默认序，chip 隐藏
      const clear: Component | null = await driver.waitForComponent(ON.id('card_sort_clear'), 2000);
      expect(clear !== null).assertTrue();
      if (clear !== null) {
        await clear.click();
        await driver.delayMs(600);
      }
      const chipGone: Component | null = await driver.waitForComponent(ON.text('按涨跌幅↓'), 900);
      expect(chipGone === null).assertTrue();
      await ensureListView(driver);
      hilog.info(DOMAIN, TAG, 'AC102 sort chip ok');
      done();
    });

    it('AC103_view_mode_kept_after_relaunch', 0, async (done: Function) => {
      await startApp(driver);
      await ensureWatchlistPage(driver);
      await ensureListView(driver);
      await toggleView(driver);
      expect(await isCardView(driver)).assertTrue();
      // 重新拉起（bringToFront，不杀进程）后仍是卡片：视图形态不进 `aboutToAppear` 重置
      await startApp(driver);
      await ensureWatchlistPage(driver);
      expect(await isCardView(driver)).assertTrue();
      // 收尾：回列表，避免影响后续套件与手工验证
      await toggleView(driver);
      await driver.delayMs(400);
      hilog.info(DOMAIN, TAG, 'AC103 relaunch keeps card ok');
      done();
    });
  });
}
