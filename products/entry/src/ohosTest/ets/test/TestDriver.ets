import { Driver } from '@kit.TestKit';

let shared: Driver | null = null;

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
