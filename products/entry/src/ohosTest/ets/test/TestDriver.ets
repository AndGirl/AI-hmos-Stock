import { Driver, ON, abilityDelegatorRegistry } from '@kit.TestKit';
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';

let shared: Driver | null = null;

/** 应用偏好库名（与 `StorageAdapter.STORE_NAME` 一致）。 */
const PREF_STORE: string = 'xiaoyang_stock_v1';
/** 隐私政策版本（与 `PRIVACY_POLICY_VERSION` 一致）。 */
const POLICY_VERSION: string = '1.0';

/**
 * UiTest 全局唯一 Driver（M7 收尾发现）：
 * 每个 `describe` 各自 `Driver.create()` 时，两个测试套件同跑会触发
 * `uitest-api dose not allow calling concurrently`；所有套件统一从这里取实例。
 */
export function sharedDriver(): Driver {
  if (shared === null) {
    shared = Driver.create();
  }
  return shared;
}

/**
 * 隐私同意基线（M13-1）：直接把 `privacy_consent_v1` / `trade_risk_v1` 写进被测应用的
 * preferences，让既有 21 例用例在「已同意」基线上跑（否则首启同意页会挡住全部入口）。
 *
 * 说明：写在 `beforeAll` 只对**本次启动**有效——应用若已在运行，内存状态不会回灌，
 * 因此各套件 `startApp` 之后还会调 `dismissConsentIfShown`（同意页可见就点「同意并继续」），
 * 两条路径都保留，既覆盖首启流程，也不让用例依赖安装顺序。
 */
export async function seedCompliance(): Promise<void> {
  try {
    const context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
    const store: preferences.Preferences = await preferences.getPreferences(context, { name: PREF_STORE });
    const record: string = JSON.stringify({ agreed: true, version: POLICY_VERSION, agreedAt: Date.now() });
    await store.put('privacy_consent_v1', record);
    await store.put('trade_risk_v1', 'true');
    await store.flush();
    hilog.info(0x0001, 'UiTestSetup', 'seed_compliance ok');
  } catch (err) {
    hilog.warn(0x0001, 'UiTestSetup', 'seed_compliance fail');
  }
}

/** 首启同意页兜底：可见「同意并继续」就点掉（已在已同意状态时静默跳过）。 */
export async function dismissConsentIfShown(driver: Driver): Promise<void> {
  const agree = await driver.waitForComponent(ON.text('同意并继续'), 700);
  if (agree !== null) {
    await agree.click();
    await driver.delayMs(600);
    hilog.info(0x0001, 'UiTestSetup', 'consent_dismissed');
  }
}
