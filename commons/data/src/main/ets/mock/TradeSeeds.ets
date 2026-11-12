import { AccountInfo } from '../model/TradeModels';

/** 账号脱敏：前 3 后 2（FR-07 §5 Q7；稿内「500****5」视为占位）。 */
export function maskAccountNo(raw: string): string {
  if (raw.length <= 5) {
    return raw;
  }
  return raw.substring(0, 3) + '****' + raw.substring(raw.length - 2);
}

/** Mock 登录态：入口未登录时走登录层，登录成功回到原标的续开（DEC-07-07）。 */
export class TradeAuth {
  static loggedIn: boolean = true;

  static reset(): void {
    TradeAuth.loggedIn = true;
  }
}

/** Mock 股东账户：两个账户用于验证「切换账户后重算可买」（AC-68）。 */
export function buildAccounts(): AccountInfo[] {
  const list: AccountInfo[] = [];
  // 资金按「可买得起高价股」给：设计稿的「可买 0 股」是占位（FR-07 §5 Q4）。
  list.push(new AccountInfo('50012345', maskAccountNo('50012345'), 500000, 0, true, true));
  list.push(new AccountInfo('50098765', maskAccountNo('50098765'), 60000, 500, true, true));
  return list;
}

/** 账号中心不可用时的空列表（未开户，入口禁用，AC-66）。 */
export function buildNoAccounts(): AccountInfo[] {
  return [];
}
