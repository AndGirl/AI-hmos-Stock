import { DetailFrom, DetailParam } from './AppRoutes';

export enum DeepLinkStatus {
  OK = 0,
  INVALID = 1
}

export interface DeepLinkResult {
  status: DeepLinkStatus;
  /** 解析失败时的原因，成功为 'ok' */
  reason: string;
  /** URI 的 host（detail），失败时也保留便于埋点 */
  host: string;
  /** 失败时尽量回带的 code（用于 404 埋点） */
  code?: string;
  detail?: DetailParam;
}

/**
 * 深链解析（设计 §3.5）：zixuangu://detail?code=600519&from=deeplink&rank=0
 * 只接受 detail host；code 必须是 6 位数字（存在性/下架校验在 M2 数据层，届时再进 404）。
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

  private static decode(value: string): string {
    try {
      return decodeURIComponent(value);
    } catch (error) {
      return value;
    }
  }
}
