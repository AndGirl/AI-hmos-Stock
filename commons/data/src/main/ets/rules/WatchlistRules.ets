import { WatchGroup } from '../entities/WatchEntities';

/**
 * 自选管理纯函数（M7-1，L2 规则层）：
 * 容量 / 分组名 / 分组归属派生的唯一实现，Store 与 VM 都只调用这里，便于单测。
 * 约束：零中文、零 UI 依赖（附录 C 第 13 条）。
 */

/** 自选上限（CC-1.1 / AC-96）：账号级 50 只。 */
export const WATCHLIST_MAX_ITEMS: number = 50;
/** 用户组上限（CC-2.1）：不含「全部」与系统组（融/创/科）。 */
export const WATCHLIST_MAX_USER_GROUPS: number = 7;
/** 用户组名长度上限（M7-6：≤8 字）。 */
export const WATCHLIST_GROUP_NAME_MAX: number = 8;
/** 「全部」虚拟组 id（CC-2.3）。 */
export const WATCHLIST_ALL_GROUP: string = 'all';

const SYSTEM_GROUP_IDS: string[] = ['fin', 'star', 'kcb'];

/** 组名校验结论：'ok' 通过，其余为拒绝原因。 */
export type GroupNameIssue = 'ok' | 'empty' | 'too_long' | 'emoji' | 'duplicate';

/** 组编辑结论：组名问题 + 容量/只读/不存在。 */
export type GroupEditReason = GroupNameIssue | 'limit' | 'system_readonly' | 'not_found';

export function isSystemGroupId(id: string): boolean {
  return SYSTEM_GROUP_IDS.indexOf(id) >= 0;
}

export function isVirtualGroupId(id: string): boolean {
  return id === WATCHLIST_ALL_GROUP;
}

/** 用户组数量（不含「全部」与系统组）。 */
export function countUserGroups(groups: WatchGroup[]): number {
  let count: number = 0;
  for (let i = 0; i < groups.length; i++) {
    if (groups[i].type === 'user') {
      count++;
    }
  }
  return count;
}

/**
 * 派生系统组（AC-96 / CC-2.2「至少 1 个系统组」）：
 * 30x → star（创业板）、68x → kcb（科创板）、其余 → fin（融资融券）。
 * 融资融券没有可用的行情字段，Mock 阶段按主板的默认归属处理（见 M7 偏差登记）。
 */
export function systemGroupsOf(code: string): string[] {
  if (code.startsWith('30')) {
    return ['star'];
  }
  if (code.startsWith('68')) {
    return ['kcb'];
  }
  return ['fin'];
}

/**
 * 最终分组归属：用户选中的组（去重、剔除「全部」）+ 派生的系统组。
 * 保证 INV-1（不存在无组股票）与多归属叠加（AC-95 / FR-04.6）。
 */
export function resolveGroupMembership(code: string, chosen: string[]): string[] {
  const result: string[] = [];
  const derived: string[] = systemGroupsOf(code);
  for (let i = 0; i < derived.length; i++) {
    result.push(derived[i]);
  }
  for (let i = 0; i < chosen.length; i++) {
    const id: string = chosen[i];
    if (id.length === 0 || isVirtualGroupId(id) || result.indexOf(id) >= 0) {
      continue;
    }
    result.push(id);
  }
  return result;
}

/** 组名归一化：去首尾空白，连续空白压成一个空格。 */
export function normalizeGroupName(raw: string): string {
  const trimmed: string = raw.trim();
  let out: string = '';
  let lastSpace: boolean = false;
  for (let i = 0; i < trimmed.length; i++) {
    const ch: string = trimmed.charAt(i);
    const isSpace: boolean = ch === ' ' || ch === '\t' || ch === '\n';
    if (isSpace) {
      if (!lastSpace) {
        out += ' ';
      }
      lastSpace = true;
    } else {
      out += ch;
      lastSpace = false;
    }
  }
  return out;
}

/** 字符数（按码点计，代理对算 1 个），用于 ≤8 字校验。 */
export function charCount(text: string): number {
  let count: number = 0;
  for (let i = 0; i < text.length; i++) {
    const code: number = text.charCodeAt(i);
    if (code >= 0xD800 && code <= 0xDBFF && i + 1 < text.length) {
      const next: number = text.charCodeAt(i + 1);
      if (next >= 0xDC00 && next <= 0xDFFF) {
        i++;
      }
    }
    count++;
  }
  return count;
}

/** 是否含 emoji / 变体选择符 / 零宽连接符（组名禁止）。 */
export function hasEmoji(text: string): boolean {
  for (let i = 0; i < text.length; i++) {
    const code: number = text.charCodeAt(i);
    if (code >= 0xD800 && code <= 0xDBFF && i + 1 < text.length) {
      const next: number = text.charCodeAt(i + 1);
      if (next >= 0xDC00 && next <= 0xDFFF) {
        const point: number = (code - 0xD800) * 0x400 + (next - 0xDC00) + 0x10000;
        if (point >= 0x1F000 && point <= 0x1FAFF) {
          return true;
        }
        i++;
        continue;
      }
    }
    if (code === 0xFE0F || code === 0x200D) {
      return true;
    }
    if (code >= 0x2600 && code <= 0x27BF) {
      return true;
    }
    if (code >= 0x2B00 && code <= 0x2BFF) {
      return true;
    }
  }
  return false;
}

/**
 * 组名校验（M7-6）：非空、≤8 字、禁 emoji、与其它组重名（大小写不敏感）。
 * `excludeName` 为重命名时的原名，避免自己和自己判重。
 */
export function validateGroupName(raw: string, existingNames: string[], excludeName: string): GroupNameIssue {
  const name: string = normalizeGroupName(raw);
  if (name.length === 0) {
    return 'empty';
  }
  if (charCount(name) > WATCHLIST_GROUP_NAME_MAX) {
    return 'too_long';
  }
  if (hasEmoji(name)) {
    return 'emoji';
  }
  const key: string = name.toLowerCase();
  for (let i = 0; i < existingNames.length; i++) {
    const other: string = normalizeGroupName(existingNames[i]);
    if (other.length === 0) {
      continue;
    }
    if (other.toLowerCase() === key && other.toLowerCase() !== excludeName.trim().toLowerCase()) {
      return 'duplicate';
    }
  }
  return 'ok';
}
