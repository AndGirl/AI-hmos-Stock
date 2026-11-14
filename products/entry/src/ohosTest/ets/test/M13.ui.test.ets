import { describe, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry, Component, Driver, ON } from '@kit.TestKit';
import { Want } from '@kit.AbilityKit';
import { dismissConsentIfShown, seedCompliance, sharedDriver } from './TestDriver';

const BUNDLE: string = 'com.example.xiaoyangstock';
const ABILITY: string = 'EntryAbility';

/**
 * 启动被测应用（AbilityDelegator 拉起 EntryAbility；已在前台时等价于 bringToFront）。
 * 本套件用例自带多次页面往返，启动等待压到 700ms（全局 UiTest 单例 15s 上限）。
 */
async function startApp(driver: Driver): Promise<void> {
  await seedCompliance();
  const want: Want = { bundleName: BUNDLE, abilityName: ABILITY };
  await abilityDelegatorRegistry.getAbilityDelegator().startAbility(want);
  await driver.delayMs(700);
  await dismissConsentIfShown(driver);
}

/**
 * 点底部「首页」Tab：前面套件可能停在详情/委托/持仓等 push 页（底栏不可见），
 * 先按返回退回四 Tab 再点。HyPium 单用例 15s 上限，因此每次等待压到 800ms。
 */
async function ensureHomeTab(driver: Driver): Promise<void> {
  for (let i = 0; i < 3; i++) {
    const home: Component | null = await driver.waitForComponent(ON.text('首页'), 800);
    if (home !== null) {
      await home.click();
      await driver.delayMs(400);
      return;
    }
    await driver.pressBack();
    await driver.delayMs(400);
  }
  throw new Error('cannot reach home tab');
}

/**
 * M13 合规 UI 自动化（AC-125）。
 *
 * 覆盖 2026-11-14 评审发现的回归：**从隐私政策页撤回同意、再重新同意后**，
 * 应用必须回到四 Tab（自选），不能停在残留路由「隐私政策」页上
 * （`ConsentView` 挂载时已清 `NavPathStack`；若回归，`自选股` 断言会失败）。
 * 顺带走一遍「首页 → 隐私政策 → 撤回确认 → 首启同意页」入口链路。
 *
 * 注意：Hypium 单用例 15s 上限，本用例所有等待都压到最短、且不做冗余二次扫描。
 */
export default function m13UiTest(): void {
  describe('M13UiTest', () => {
    const driver: Driver = sharedDriver();

    it('AC125_revoke_then_reagree_returns_to_tabs', 0, async (done: Function) => {
      await startApp(driver);
      await ensureHomeTab(driver);

      const policy: Component | null = await driver.waitForComponent(ON.text('隐私政策'), 1200);
      expect(policy !== null).assertTrue();
      if (policy === null) {
        done();
        return;
      }
      await policy.click();
      await driver.delayMs(600);

      const revoke: Component | null = await driver.waitForComponent(ON.text('撤回同意'), 1500);
      expect(revoke !== null).assertTrue();
      if (revoke !== null) {
        await revoke.click();
        await driver.delayMs(500);
      }

      const confirm: Component | null = await driver.waitForComponent(ON.text('撤回'), 1500);
      if (confirm !== null) {
        await confirm.click();
        await driver.delayMs(600);
      }

      // 撤回后必须回到首启同意页，重新同意后必须回到四 Tab
      const agree: Component | null = await driver.waitForComponent(ON.text('同意并继续'), 2000);
      expect(agree !== null).assertTrue();
      if (agree !== null) {
        await agree.click();
        await driver.delayMs(1200);
      }
      const watchlist: Component | null = await driver.waitForComponent(ON.text('自选股'), 1500);
      expect(watchlist !== null).assertTrue();
      done();
    });
  });
}
