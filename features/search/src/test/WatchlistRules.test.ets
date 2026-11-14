import { describe, it, expect } from '@ohos/hypium';
import {
  charCount,
  countUserGroups,
  hasEmoji,
  isSystemGroupId,
  isVirtualGroupId,
  limitNameSummary,
  normalizeGroupName,
  resolveGroupMembership,
  systemGroupsOf,
  validateGroupName,
  WATCHLIST_ALL_GROUP,
  WATCHLIST_GROUP_NAME_MAX,
  WATCHLIST_MAX_ITEMS,
  WATCHLIST_MAX_USER_GROUPS,
  WatchGroup
} from 'commons_data';

function userGroup(id: string, name: string): WatchGroup {
  return new WatchGroup(id, 'user', 9, name);
}

/**
 * M7-1 自选管理规则单测（AC-96 / AC-99）：
 * 派生系统组、分组归属叠加、组名校验、容量常量。
 * 纯函数，无 device 依赖（Hypium Local Test）。
 */
export default function watchlistRulesTest(): void {
  describe('WatchlistRules', () => {
    it('case_system_groups_by_code_prefix', 0, () => {
      expect(systemGroupsOf('300750')[0]).assertEqual('star');
      expect(systemGroupsOf('301999')[0]).assertEqual('star');
      expect(systemGroupsOf('688981')[0]).assertEqual('kcb');
      expect(systemGroupsOf('689009')[0]).assertEqual('kcb');
      // 主板没有可用的融资融券字段：Mock 阶段默认落 fin（保证 INV-1）
      expect(systemGroupsOf('600519')[0]).assertEqual('fin');
      expect(systemGroupsOf('000001')[0]).assertEqual('fin');
    });

    it('case_membership_always_has_system_group', 0, () => {
      const groups: string[] = resolveGroupMembership('600519', []);
      expect(groups.length).assertEqual(1);
      expect(groups[0]).assertEqual('fin');
    });

    it('case_membership_union_and_dedupe', 0, () => {
      const groups: string[] = resolveGroupMembership('300750', ['ug1', 'ug1', WATCHLIST_ALL_GROUP]);
      expect(groups.length).assertEqual(2);
      expect(groups[0]).assertEqual('star');
      expect(groups[1]).assertEqual('ug1');
    });

    it('case_membership_keeps_system_choice', 0, () => {
      const groups: string[] = resolveGroupMembership('688981', ['fin', 'ug2']);
      // 派生 kcb + 用户显式勾的 fin（系统组也可叠加）+ 用户组 ug2
      expect(groups.length).assertEqual(3);
      expect(groups[0]).assertEqual('kcb');
      expect(groups.indexOf('fin') >= 0).assertTrue();
      expect(groups.indexOf('ug2') >= 0).assertTrue();
    });

    it('case_group_name_empty', 0, () => {
      expect(validateGroupName('   ', [], '')).assertEqual('empty');
    });

    it('case_group_name_too_long', 0, () => {
      const name: string = '一二三四五六七八九';
      expect(name.length).assertEqual(WATCHLIST_GROUP_NAME_MAX + 1);
      expect(validateGroupName(name, [], '')).assertEqual('too_long');
    });

    it('case_group_name_max_length_ok', 0, () => {
      expect(validateGroupName('一二三四五六七八', [], '')).assertEqual('ok');
    });

    it('case_group_name_emoji', 0, () => {
      expect(hasEmoji('长期🚀')).assertTrue();
      expect(hasEmoji('长期')).assertFalse();
      expect(validateGroupName('长期🚀', [], '')).assertEqual('emoji');
    });

    it('case_group_name_duplicate_ignores_case', 0, () => {
      const existing: string[] = ['Banks'];
      expect(validateGroupName('banks', existing, '')).assertEqual('duplicate');
    });

    it('case_group_name_rename_self_ok', 0, () => {
      const existing: string[] = ['Banks'];
      // 重命名成自己原来的名字（仅大小写变化）不算重名
      expect(validateGroupName('banks', existing, 'Banks')).assertEqual('ok');
    });

    it('case_group_name_normalize', 0, () => {
      expect(normalizeGroupName('  长期   持有  ')).assertEqual('长期 持有');
      expect(validateGroupName('  长期   持有  ', [], '')).assertEqual('ok');
    });

    it('case_char_count_surrogate_pair', 0, () => {
      // 代理对（emoji）按 1 个字计
      expect(charCount('🚀')).assertEqual(1);
      expect(charCount('长期持有')).assertEqual(4);
    });

    it('case_count_user_groups', 0, () => {
      const groups: WatchGroup[] = [
        new WatchGroup(WATCHLIST_ALL_GROUP, 'all', 0, ''),
        new WatchGroup('fin', 'system', 1, ''),
        userGroup('user', '我的关注'),
        userGroup('ug1', '长期')
      ];
      expect(countUserGroups(groups)).assertEqual(2);
      expect(WATCHLIST_MAX_USER_GROUPS).assertEqual(7);
      expect(WATCHLIST_MAX_ITEMS).assertEqual(50);
    });

    it('case_group_id_classification', 0, () => {
      expect(isSystemGroupId('fin')).assertTrue();
      expect(isSystemGroupId('ug1')).assertFalse();
      expect(isVirtualGroupId(WATCHLIST_ALL_GROUP)).assertTrue();
      expect(isVirtualGroupId('user')).assertFalse();
    });

    // AC-96 / C7：部分成功提示要能列出超限标的名称。
    it('case_limit_name_summary', 0, () => {
      expect(limitNameSummary(['贵州茅台'])).assertEqual('贵州茅台');
      expect(limitNameSummary(['贵州茅台', '五粮液'])).assertEqual('贵州茅台、五粮液');
      // 空项被过滤，不出现「、、」
      expect(limitNameSummary(['', '   ', '招商银行'])).assertEqual('招商银行');
      expect(limitNameSummary([])).assertEqual('');
    });

    it('case_limit_name_summary_truncates', 0, () => {
      const names: string[] = ['A股一', 'A股二', 'A股三', 'A股四'];
      expect(limitNameSummary(names)).assertEqual('A股一、A股二、A股三 等');
      // 恰好 3 个不接「等」
      expect(limitNameSummary(['一', '二', '三'])).assertEqual('一、二、三');
      // 自定义上限
      expect(limitNameSummary(names, 2)).assertEqual('A股一、A股二 等');
    });
  });
}
