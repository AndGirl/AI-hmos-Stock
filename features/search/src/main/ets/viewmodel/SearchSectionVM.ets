import { SEARCH_SECTION_LIMIT, SearchKind, SearchSection } from 'commons_data';
import { SearchRowVM } from './SearchRowVM';

/**
 * 结果段（股票 / 指数 / 板块）：默认展示 20 条，可展开；展开状态是视图态，不进存储。
 */
@ObservedV2
export class SearchSectionVM {
  kind: SearchKind = 'stock';
  @Trace rows: SearchRowVM[] = [];
  @Trace total: number = 0;
  @Trace expanded: boolean = false;

  static from(section: SearchSection): SearchSectionVM {
    const vm: SearchSectionVM = new SearchSectionVM();
    vm.kind = section.kind;
    const rows: SearchRowVM[] = [];
    for (let i = 0; i < section.hits.length; i++) {
      const row: SearchRowVM = new SearchRowVM();
      row.apply(section.hits[i], i);
      rows.push(row);
    }
    vm.rows = rows;
    vm.total = section.total;
    return vm;
  }

  visibleRows(): SearchRowVM[] {
    if (this.expanded) {
      return this.rows;
    }
    return this.rows.slice(0, SEARCH_SECTION_LIMIT);
  }

  canExpand(): boolean {
    return !this.expanded && this.rows.length > SEARCH_SECTION_LIMIT;
  }

  canCollapse(): boolean {
    return this.expanded && this.rows.length > SEARCH_SECTION_LIMIT;
  }
}

/** 扁平化后的列表项：段标题 / 结果行 / 展开 / 收起。 */
export type SearchItemKind = 'header' | 'row' | 'expand' | 'less';

/**
 * 列表项（M6-4）：把「段 + 行 + 展开」拍平成一条数组，
 * 由 VM 统一生成唯一 key（含版本号）。这样 ForEach 的 key 随结果/展开变化，
 * 不会因为 key 不变而复用旧组件导致界面停留在上一帧结果。
 */
export class SearchItemVM {
  kind: SearchItemKind = 'header';
  key: string = '';
  sectionKind: SearchKind = 'stock';
  sectionIndex: number = 0;
  total: number = 0;
  row: SearchRowVM = new SearchRowVM();
}
