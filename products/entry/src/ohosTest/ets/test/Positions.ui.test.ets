import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry, Component, Driver, ON } from '@kit.TestKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { sharedDriver } from './TestDriver';

const DOMAIN: number = 0x0001;
const TAG: string = 'PositionsUiTest';
const BUNDLE: string = 'com.example.xiaoyangstock';
const ABILITY: string = 'EntryAbility';
/** 点行验详情用主数据标的名（样例持仓的第一行）。 */
const DETAIL_CODE: string = '601318';

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

/** 自选 → 当日委托 → 持仓（M11 入口：委托页标题栏「持仓」）。 */
async function openPositions(driver: Driver): Promise<void> {
  const orders: Component | null = await driver.waitForComponent(ON.text('当日委托'), 3000);
  if (orders === null) {
    throw new Error('orders entry not found');
  }
  await orders.click();
  await driver.delayMs(1000);
  const entry: Component | null = await driver.waitForComponent(ON.text('持仓'), 3000);
  if (entry === null) {
    throw new Error('positions entry not found');
  }
  await entry.click();
  await driver.delayMs(1500);
}

/**
 * M11 持仓 UI 自动化（AC-119/120）。
 *
 * 说明：
 * - 断言「列表 + 汇总 + 排序 chip + 样例行」与「点行进详情并返回」，不依赖自选状态；
 * - 「＋ → 已添加」需要干净的 601398 未加自选状态，作为手工取证（见
 *   validation/phase2-m11-test-cases.md 与 shots/phase2/m11）；
 * - 前置：设备已安装同版本 debug HAP；首次运行前 `param set persist.ace.testmode.enabled 1`。
 */
export default function positionsUiTest(): void {
  describe('PositionsUiTest', () => {
    const driver: Driver = sharedDriver();

    it('AC119_positions_list_summary_and_sort', 0, async (done: Function) => {
      await startApp(driver);
      await ensureWatchlistPage(driver);
      await openPositions(driver);

      const list: Component | null = await driver.waitForComponent(ON.id('position_list'), 5000);
      expect(list !== null).assertTrue();
      const summary: Component | null = await driver.waitForComponent(ON.text('总市值'), 3000);
      expect(summary !== null).assertTrue();
      const note: Component | null = await driver.waitForComponent(ON.text('当日盈亏按昨收计算；累计盈亏按成本价计算，不含交易费用'), 3000);
      expect(note !== null).assertTrue();

      // 排序 chip 三项齐全
      const sortValue: Component | null = await driver.waitForComponent(ON.text('市值'), 2000);
      const sortPnl: Component | null = await driver.waitForComponent(ON.text('盈亏'), 2000);
      const sortRatio: Component | null = await driver.waitForComponent(ON.text('盈亏比'), 2000);
      expect(sortValue !== null).assertTrue();
      expect(sortPnl !== null).assertTrue();
      expect(sortRatio !== null).assertTrue();

      // 样例持仓（主账户 3 只种子之一）
      const row: Component | null = await driver.waitForComponent(ON.text('中国平安'), 3000);
      expect(row !== null).assertTrue();

      // 排序可点：点「盈亏」后列表仍在（值变化由截图取证）
      if (sortPnl !== null) {
        await sortPnl.click();
        await driver.delayMs(600);
      }
      const afterSort: Component | null = await driver.waitForComponent(ON.id('position_list'), 2000);
      expect(afterSort !== null).assertTrue();
      hilog.info(DOMAIN, TAG, 'AC119 positions list ok');
      done();
    });

    it('AC120_row_opens_detail_and_returns', 0, async (done: Function) => {
      // 承接上一例：当前在持仓页；若不在，重新进入。
      const existing: Component | null = await driver.waitForComponent(ON.id('position_list'), 1500);
      if (existing === null) {
        await ensureWatchlistPage(driver);
        await openPositions(driver);
      }
      const row: Component | null = await driver.waitForComponent(ON.id(`position_row_${DETAIL_CODE}`), 4000);
      if (row === null) {
        throw new Error('seed position row not found');
      }
      await row.click();
      await driver.delayMs(2000);

      // 详情页路由到位的直接证据是根节点 id；「今开」只是内容探针（首屏慢时不做硬断言）。
      const landRoot: Component | null = await driver.waitForComponent(ON.id('detail_landscape'), 5000);
      const portRoot: Component | null = landRoot !== null ? null :
        await driver.waitForComponent(ON.id('detail_layout'), 2000);
      expect(landRoot !== null || portRoot !== null).assertTrue();
      const detail: Component | null = await driver.waitForComponent(ON.text('今开'), 4000);
      if (detail === null) {
        hilog.warn(DOMAIN, TAG, 'metric 今开 not found in 4s (detail root already asserted)');
      }

      await driver.pressBack();
      await driver.delayMs(900);
      const backList: Component | null = await driver.waitForComponent(ON.id('position_list'), 3000);
      expect(backList !== null).assertTrue();
      hilog.info(DOMAIN, TAG, 'AC120 row -> detail -> back ok');
      done();
    });
  });
}
