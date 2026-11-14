import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry, Component, Driver, ON } from '@kit.TestKit';
import { Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { dismissConsentIfShown, seedCompliance, sharedDriver } from './TestDriver';

const DOMAIN: number = 0x0001;
const TAG: string = 'AddWatchlistUiTest';
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

/** 打开添加页：点底部胶囊「添加自选」。 */
async function openAddPage(driver: Driver): Promise<void> {
  const entry: Component | null = await driver.waitForComponent(ON.text('添加自选'), 2000);
  if (entry === null) {
    throw new Error('add entry not found');
  }
  await entry.click();
  await driver.delayMs(900);
}

/** 行内点击坐标：取名称节点右侧（价格区），避免写死 x 在不同宽度设备上失效。 */
async function rowClickX(row: Component): Promise<number> {
  const bounds = await row.getBounds();
  const x: number = Math.floor(bounds.right + 120);
  return x > 1150 ? 1150 : x;
}

/** 添加页内输入关键词（输入框默认聚焦，直接输入；先清空避免脏词）。 */
async function typeTerm(driver: Driver, term: string): Promise<void> {
  const input: Component | null = await driver.waitForComponent(ON.type('TextInput'), 2000);
  if (input === null) {
    throw new Error('add page input not found');
  }
  await input.click();
  await driver.delayMs(150);
  await input.clearText();
  await driver.delayMs(200);
  await input.inputText(term);
  await driver.delayMs(900);
}

/**
 * M7 添加自选与分组 UI 自动化（AC-94/95/96/98/99）。
 * 前置：设备已安装同版本 debug HAP；首次运行前需：
 *   hdc -t <serial> shell param set persist.ace.testmode.enabled 1
 * 说明：`onDeviceTest` 会重装应用并把自选恢复为 45 只种子，用例按该初态编写。
 */
export default function addWatchlistUiTest(): void {
  describe('AddWatchlistUiTest', () => {
    const driver: Driver = sharedDriver();

    it('AC94_add_page_from_watchlist_capsule', 0, async (done: Function) => {
      await startApp(driver);
      await ensureWatchlistPage(driver);
      await openAddPage(driver);
      // 先取证据再断言，保证失败时也会关闭页面，不影响后续用例
      const input: Component | null = await driver.waitForComponent(ON.type('TextInput'), 3000);
      const submit: Component | null = await driver.waitForComponent(ON.text('加入自选'), 3000);
      await driver.pressBack();
      await driver.delayMs(700);
      expect(input !== null).assertTrue();
      expect(submit !== null).assertTrue();
      done();
    });

    it('AC95_multi_select_updates_count', 0, async (done: Function) => {
      await startApp(driver);
      await ensureWatchlistPage(driver);
      await openAddPage(driver);
      // 用未被其它用例增删的标的，避免套件顺序互相影响（M6 会加 601398）
      await typeTerm(driver, '601988');
      const row: Component | null = await driver.waitForComponent(ON.text('中国银行'), 3000);
      expect(row !== null).assertTrue();
      if (row !== null) {
        // 行点击挂在 Row 上：点文本中心不一定命中，取名称右侧价格区坐标（不写死 x）
        const bounds = await row.getBounds();
        await driver.click(await rowClickX(row), Math.floor((bounds.top + bounds.bottom) / 2));
        await driver.delayMs(700);
      }
      const picked: Component | null = await driver.waitForComponent(ON.text('加入自选（1）'), 3000);
      expect(picked !== null).assertTrue();
      await driver.pressBack();
      await driver.delayMs(700);
      done();
    });

    it('AC96_added_row_not_selectable', 0, async (done: Function) => {
      await startApp(driver);
      await ensureWatchlistPage(driver);
      await openAddPage(driver);
      await typeTerm(driver, '600519');
      const added: Component | null = await driver.waitForComponent(ON.text('已添加'), 3000);
      expect(added !== null).assertTrue();
      // 已添加行不可复选：点行后提交按钮仍为「加入自选」（无计数）
      const bounds = await added.getBounds();
      await driver.click(await rowClickX(added), Math.floor((bounds.top + bounds.bottom) / 2));
      await driver.delayMs(600);
      const stillEmpty: Component | null = await driver.waitForComponent(ON.text('加入自选（1）'), 800);
      expect(stillEmpty === null).assertTrue();
      await driver.pressBack();
      await driver.delayMs(700);
      done();
    });

    it('AC98_edit_mode_enter_select_and_exit', 0, async (done: Function) => {
      await startApp(driver);
      await ensureWatchlistPage(driver);
      const edit: Component | null = await driver.waitForComponent(ON.text('编辑'), 2000);
      expect(edit !== null).assertTrue();
      if (edit !== null) {
        await edit.click();
        await driver.delayMs(700);
      }
      const bar: Component | null = await driver.waitForComponent(ON.text('全选'), 2000);
      expect(bar !== null).assertTrue();
      // 编辑态点首行 = 勾选（不跳详情）
      await driver.click(700, 900);
      await driver.delayMs(600);
      const remove: Component | null = await driver.waitForComponent(ON.text('移出（1）'), 2000);
      expect(remove !== null).assertTrue();
      const cancel: Component | null = await driver.waitForComponent(ON.text('取消'), 1500);
      if (cancel !== null) {
        await cancel.click();
        await driver.delayMs(600);
      }
      // 退出编辑后回到常规态：标题「自选股」与「编辑」入口重新出现
      const title: Component | null = await driver.waitForComponent(ON.text('自选股'), 2000);
      expect(title !== null).assertTrue();
      done();
    });

    it('AC99_group_manage_sheet_open_and_close', 0, async (done: Function) => {
      await startApp(driver);
      await ensureWatchlistPage(driver);
      const manage: Component | null = await driver.waitForComponent(ON.text('管理'), 2000);
      expect(manage !== null).assertTrue();
      if (manage !== null) {
        await manage.click();
        await driver.delayMs(800);
      }
      const title: Component | null = await driver.waitForComponent(ON.text('分组管理'), 3000);
      expect(title !== null).assertTrue();
      const create: Component | null = await driver.waitForComponent(ON.text('新建分组'), 3000);
      expect(create !== null).assertTrue();
      const close: Component | null = await driver.waitForComponent(ON.text('关闭'), 2000);
      if (close !== null) {
        await close.click();
        await driver.delayMs(700);
      }
      const back: Component | null = await driver.waitForComponent(ON.text('自选股'), 3000);
      expect(back !== null).assertTrue();
      done();
    });

    it('AC96_online_add_page_has_no_offline_hint', 0, async (done: Function) => {
      // 在线初态（MockFaults 随进程重启复位）：添加页不出现离线提示；
      // 离线提示本身由 `@Monitor('hub.state')` 驱动，真机手动取证见 19-offline-add.png。
      await startApp(driver);
      await ensureWatchlistPage(driver);
      await openAddPage(driver);
      const offlineHint: Component | null =
        await driver.waitForComponent(ON.text('当前离线，加入后将标记待同步'), 900);
      expect(offlineHint === null).assertTrue();
      await driver.pressBack();
      await driver.delayMs(700);
      hilog.info(DOMAIN, TAG, 'offline hint absent when online');
      done();
    });
  });
}
