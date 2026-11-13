import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry, Component, Driver, ON } from '@kit.TestKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0001;
const TAG: string = 'SearchUiTest';
const BUNDLE: string = 'com.example.xiaoyangstock';
const ABILITY: string = 'EntryAbility';

/** 启动被测应用（AbilityDelegator 拉起 EntryAbility；已在前台时等价于 bringToFront）。 */
async function startApp(driver: Driver): Promise<void> {
  const want: Want = { bundleName: BUNDLE, abilityName: ABILITY };
  await abilityDelegatorRegistry.getAbilityDelegator().startAbility(want);
  await driver.delayMs(1200);
}

/** 保证停在「行情」Tab 的搜索页：最多重试 3 次（详情页 → 返回；其它 Tab → 点行情）。 */
async function ensureSearchPage(driver: Driver): Promise<void> {
  for (let i = 0; i < 3; i++) {
    const input: Component | null = await driver.waitForComponent(ON.type('TextInput'), 1200);
    if (input !== null) {
      return;
    }
    const marketTab: Component | null = await driver.waitForComponent(ON.text('行情'), 800);
    if (marketTab !== null) {
      await marketTab.click();
      await driver.delayMs(700);
      continue;
    }
    await driver.pressBack();
    await driver.delayMs(700);
  }
  throw new Error('cannot reach search page');
}

/** 清空并输入关键词；输入后等待防抖（300ms）+ Mock 时延（120ms）+ 渲染。 */
async function typeSearch(driver: Driver, term: string): Promise<void> {
  const input: Component | null = await driver.waitForComponent(ON.type('TextInput'), 2000);
  if (input === null) {
    throw new Error('search input not found');
  }
  await input.click();
  await driver.delayMs(150);
  await input.clearText();
  await driver.delayMs(200);
  await input.inputText(term);
  await driver.delayMs(700);
}

/** 输入框清空（回到初始态：历史 + 热搜）。 */
async function clearSearch(driver: Driver): Promise<void> {
  const input: Component | null = await driver.waitForComponent(ON.type('TextInput'), 2000);
  if (input === null) {
    throw new Error('search input not found');
  }
  await input.click();
  await driver.delayMs(150);
  await input.clearText();
  await driver.delayMs(600);
}

/**
 * M6 搜索 UI 自动化（AC-87 / 88 / 90 / 91 / 92）。
 * 前置：设备已安装同版本 debug HAP；首次运行前需：
 *   hdc -t <serial> shell param set persist.ace.testmode.enabled 1
 */
export default function searchUiTest(): void {
  describe('SearchUiTest', () => {
    const driver: Driver = Driver.create();

    it('AC87_search_entry_from_market_tab', 0, async (done: Function) => {
      hilog.info(DOMAIN, TAG, 'start AC87_search_entry_from_market_tab');
      await startApp(driver);
      await ensureSearchPage(driver);
      const input: Component | null = await driver.waitForComponent(ON.type('TextInput'), 3000);
      expect(input !== null).assertTrue();
      done();
    });

    it('AC87_latest_term_wins_after_debounce', 0, async (done: Function) => {
      await startApp(driver);
      await ensureSearchPage(driver);
      await typeSearch(driver, '宁德');
      await typeSearch(driver, '平安');
      await driver.delayMs(1000);
      const hit: Component | null = await driver.waitForComponent(ON.text('平安银行'), 3000);
      expect(hit !== null).assertTrue();
      // 旧 term 的结果不得残留（seq 丢弃旧响应）
      const stale: Component | null = await driver.waitForComponent(ON.text('宁德时代'), 1000);
      expect(stale === null).assertTrue();
      done();
    });

    it('AC92_empty_state', 0, async (done: Function) => {
      await startApp(driver);
      await ensureSearchPage(driver);
      await typeSearch(driver, 'zzzz');
      const empty: Component | null = await driver.waitForComponent(ON.text('没有找到相关股票'), 3000);
      expect(empty !== null).assertTrue();
      done();
    });

    it('AC92_browse_list_visible', 0, async (done: Function) => {
      await startApp(driver);
      await ensureSearchPage(driver);
      await clearSearch(driver);
      const title: Component | null = await driver.waitForComponent(ON.text('全部股票'), 3000);
      expect(title !== null).assertTrue();
      // 空词列表默认 80 只；分页/到底提示（80/80）走真机手动用例，避免滑动动画拖长用例
      const total: Component | null = await driver.waitForComponent(ON.text('共 80 只'), 2000);
      expect(total !== null).assertTrue();
      done();
    });

    it('AC90_history_written_on_hotword_click', 0, async (done: Function) => {
      await startApp(driver);
      await ensureSearchPage(driver);
      await clearSearch(driver);
      // 热搜点击 = 一次「提交搜索」，写历史（不依赖详情往返，路径最短）
      const hot: Component | null = await driver.waitForComponent(ON.text('贵州茅台'), 3000);
      expect(hot !== null).assertTrue();
      if (hot !== null) {
        await hot.click();
        await driver.delayMs(700);
      }
      await clearSearch(driver);
      const title: Component | null = await driver.waitForComponent(ON.text('最近搜索'), 3000);
      expect(title !== null).assertTrue();
      const chip: Component | null = await driver.waitForComponent(ON.text('贵州茅台'), 2000);
      expect(chip !== null).assertTrue();
      done();
    });

    it('AC91_open_detail_and_back', 0, async (done: Function) => {
      await startApp(driver);
      await ensureSearchPage(driver);
      await typeSearch(driver, '600519');
      const row: Component | null = await driver.waitForComponent(ON.text('贵州茅台'), 3000);
      expect(row !== null).assertTrue();
      if (row !== null) {
        // 行点击挂在 Row 上：点文本中心不一定命中，改在行内价格区点击（真机 1260px 宽）
        const bounds = await row.getBounds();
        const rowY: number = Math.floor((bounds.top + bounds.bottom) / 2);
        await driver.click(600, rowY);
        await driver.delayMs(1500);
      }
      // NavDestination 标题栏不一定暴露为 Text 节点，用详情页内容（指标「今开」）判定已进入详情
      const detail: Component | null = await driver.waitForComponent(ON.text('今开'), 3000);
      expect(detail !== null).assertTrue();
      await driver.pressBack();
      await driver.delayMs(800);
      const input: Component | null = await driver.waitForComponent(ON.type('TextInput'), 3000);
      expect(input !== null).assertTrue();
      done();
    });

    it('AC91_add_to_watchlist_inline', 0, async (done: Function) => {
      await startApp(driver);
      await ensureSearchPage(driver);
      await typeSearch(driver, '601398');
      const addButton: Component | null = await driver.waitForComponent(ON.text('＋'), 1500);
      if (addButton !== null) {
        await addButton.click();
        await driver.delayMs(1200);
      }
      // 首次运行：点击后变「已添加」；重复运行：本来就「已添加」
      const added: Component | null = await driver.waitForComponent(ON.text('已添加'), 3000);
      expect(added !== null).assertTrue();
      done();
    });

    // M6 追加：已添加再点一次 = 撤出自选（AC-91 变更），行回到「＋」且可再加回。
    it('AC91_remove_from_watchlist_inline', 0, async (done: Function) => {
      await startApp(driver);
      await ensureSearchPage(driver);
      await typeSearch(driver, '600888');
      // 前置：保证从「未添加」开始（上次异常中断可能停在已添加）
      const leftover: Component | null = await driver.waitForComponent(ON.text('已添加'), 800);
      if (leftover !== null) {
        await leftover.click();
        await driver.delayMs(900);
      }
      const add: Component | null = await driver.waitForComponent(ON.text('＋'), 2000);
      expect(add !== null).assertTrue();
      if (add !== null) {
        await add.click();
        await driver.delayMs(1000);
      }
      const added: Component | null = await driver.waitForComponent(ON.text('已添加'), 2000);
      expect(added !== null).assertTrue();
      if (added !== null) {
        await added.click();
        await driver.delayMs(1000);
      }
      // 撤出成功：行尾恢复「＋」，同一位置不再显示「已添加」
      const reset: Component | null = await driver.waitForComponent(ON.text('＋'), 3000);
      expect(reset !== null).assertTrue();
      const stillAdded: Component | null = await driver.waitForComponent(ON.text('已添加'), 600);
      expect(stillAdded === null).assertTrue();
      done();
    });
  });
}
