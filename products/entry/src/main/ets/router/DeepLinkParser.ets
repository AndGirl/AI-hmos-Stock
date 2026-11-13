import { DetailFrom, DetailParam, SearchFrom, SearchParam } from './AppRoutes';

export enum DeepLinkStatus {
  OK = 0,
  INVALID = 1
}

export interface DeepLinkResult {
  status: DeepLinkStatus;
  /** 解析失败时的原因，成功为 'ok' */
  reason: string;
  /** URI 的 host（detail / search），失败时也保留便于埋点 */
  host: string;
  /** 失败时尽量回带的 code（用于 404 埋点） */
  code?: string;
  detail?: DetailParam;
  /** search host 的结果（M6-6）：q 缺省时也返回对象，由页面回落初始态。 */
  search?: SearchParam;
}

/** 深链 q 的最大长度（FR-05.2：粘贴超 20 字截断）。 */
const SEARCH_QUERY_MAX: number = 20;

/**
 * 深链解析（设计 §3.5）：
 * - `zixuangu://detail?code=600519&from=deeplink&rank=0`
 * - `zixuangu://search?q=茅台&from=deeplink`（M6-6；q 截断 20 字，缺省/非法回落初始态，不报 404）
 */
export class DeepLinkParser {
  private static readonly SCHEME_PREFIX: string = 'zixuangu://';
  private static readonly CODE_PATTERN: RegExp = /^[0-9]{6}$/;

  static parse(rawUri: string): DeepLinkResult {
    const uri: string = rawUri.trim();
    if (!uri.toLowerCase().startsWith(DeepLinkParser.SCHEME_PREFIX)) {
      return DeepLinkParser.invalid('bad_scheme', '');
    }

    let rest: string = uri.substring(DeepLinkParser.SCHEME_PREFIX.length);
    const hashIndex: number = rest.indexOf('#');
    if (hashIndex >= 0) {
      rest = rest.substring(0, hashIndex);
    }
    const queryIndex: number = rest.indexOf('?');
    const authority: string = queryIndex >= 0 ? rest.substring(0, queryIndex) : rest;
    const query: string = queryIndex >= 0 ? rest.substring(queryIndex + 1) : '';

    const slashIndex: number = authority.indexOf('/');
    const host: string = (slashIndex >= 0 ? authority.substring(0, slashIndex) : authority).toLowerCase();
    if (host === 'search') {
      return DeepLinkParser.parseSearch(query);
    }
    if (host !== 'detail') {
      return DeepLinkParser.invalid('unknown_host', host);
    }

    let code: string = '';
    let from: DetailFrom = 'deeplink';
    let rank: number | undefined = undefined;

    const pairs: string[] = query.length > 0 ? query.split('&') : [];
    for (let i = 0; i < pairs.length; i++) {
      const pair: string = pairs[i];
      const eqIndex: number = pair.indexOf('=');
      const key: string = eqIndex >= 0 ? pair.substring(0, eqIndex) : pair;
      const rawValue: string = eqIndex >= 0 ? pair.substring(eqIndex + 1) : '';
      const value: string = DeepLinkParser.decode(rawValue);
      if (key === 'code') {
        code = value;
      } else if (key === 'from') {
        from = DeepLinkParser.parseFrom(value);
      } else if (key === 'rank') {
        const parsedRank: number = Number.parseInt(value, 10);
        if (!Number.isNaN(parsedRank) && parsedRank >= 0) {
          rank = parsedRank;
        }
      }
    }

    if (code.length === 0) {
      return DeepLinkParser.invalid('missing_code', host);
    }
    if (!DeepLinkParser.CODE_PATTERN.test(code)) {
      return DeepLinkParser.invalid('invalid_code', host, code);
    }

    const detail: DetailParam = { code: code, from: from };
    if (rank !== undefined) {
      detail.rank = rank;
    }
    return { status: DeepLinkStatus.OK, reason: 'ok', host: host, code: code, detail: detail };
  }

  /** search host：q 可选；缺省也返回 OK（初始态），非法参数只截断不报错。 */
  private static parseSearch(query: string): DeepLinkResult {
    let q: string = '';
    let from: SearchFrom = 'deeplink';
    const pairs: string[] = query.length > 0 ? query.split('&') : [];
    for (let i = 0; i < pairs.length; i++) {
      const pair: string = pairs[i];
      const eqIndex: number = pair.indexOf('=');
      const key: string = eqIndex >= 0 ? pair.substring(0, eqIndex) : pair;
      const rawValue: string = eqIndex >= 0 ? pair.substring(eqIndex + 1) : '';
      if (key === 'q') {
        q = DeepLinkParser.decode(rawValue).trim();
      } else if (key === 'from') {
        from = DeepLinkParser.parseSearchFrom(DeepLinkParser.decode(rawValue));
      }
    }
    if (q.length > SEARCH_QUERY_MAX) {
      q = q.substring(0, SEARCH_QUERY_MAX);
    }
    const search: SearchParam = { from: from };
    if (q.length > 0) {
      search.q = q;
    }
    return { status: DeepLinkStatus.OK, reason: 'ok', host: 'search', search: search };
  }

  private static invalid(reason: string, host: string, code?: string): DeepLinkResult {
    const result: DeepLinkResult = { status: DeepLinkStatus.INVALID, reason: reason, host: host };
    if (code !== undefined) {
      result.code = code;
    }
    return result;
  }

  private static parseFrom(value: string): DetailFrom {
    if (value === 'list' || value === 'card' || value === 'search' || value === 'deeplink') {
      return value;
    }
    return 'deeplink';
  }

  private static parseSearchFrom(value: string): SearchFrom {
    if (value === 'tab' || value === 'watchlist' || value === 'detail' || value === 'deeplink') {
      return value;
    }
    return 'deeplink';
  }

  private static decode(value: string): string {
    try {
      return decodeURIComponent(value);
    } catch (error) {
      return value;
    }
  }
}
