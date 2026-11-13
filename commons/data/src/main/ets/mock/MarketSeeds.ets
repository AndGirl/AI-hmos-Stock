import { Market, TradeStatus } from '../model/QuoteModels';
import { WatchGroup, WatchItem } from '../entities/WatchEntities';

/** 标的种子（Mock 数据集，覆盖涨/跌/平/停牌/新股/负市盈率；基线 §7 下限 12 只，本期 50 只）。 */
export class StockSeed {
  code: string;
  name: string;
  market: Market;
  base: number;
  status: TradeStatus;
  isNew: boolean;
  pe: number;
  pb: number;
  /** 每次推送的价格波动幅度（0 = 价格不动，用于平盘样本）。 */
  volatility: number;
  groups: string[];

  constructor(code: string, name: string, market: Market, base: number, status: TradeStatus,
    isNew: boolean, pe: number, pb: number, volatility: number) {
    this.code = code;
    this.name = name;
    this.market = market;
    this.base = base;
    this.status = status;
    this.isNew = isNew;
    this.pe = pe;
    this.pb = pb;
    this.volatility = volatility;
    this.groups = [];
  }
}

export class IndexSeed {
  code: string;
  name: string;
  base: number;

  constructor(code: string, name: string, base: number) {
    this.code = code;
    this.name = name;
    this.base = base;
  }
}

export function buildStockSeeds(): StockSeed[] {
  const seeds: StockSeed[] = [
    new StockSeed('600519', '贵州茅台', 'SH', 1680.00, 'open', false, 32.10, 9.20, 1.0),
    new StockSeed('000001', '平安银行', 'SZ', 11.20, 'open', false, 5.40, 0.62, 0),
    new StockSeed('300750', '宁德时代', 'SZ', 186.50, 'open', false, 24.80, 4.10, 1.0),
    new StockSeed('688981', '中芯国际', 'SH', 52.30, 'open', false, -18.40, 2.80, 1.0),
    new StockSeed('600036', '招商银行', 'SH', 34.60, 'open', false, 6.10, 0.95, 1.0),
    new StockSeed('000858', '五粮液', 'SZ', 142.80, 'open', false, 18.60, 5.20, 1.0),
    new StockSeed('601318', '中国平安', 'SH', 48.90, 'open', false, 7.80, 1.05, 1.0),
    new StockSeed('002594', '比亚迪', 'SZ', 245.60, 'open', false, 21.30, 4.60, 1.0),
    new StockSeed('600030', '中信证券', 'SH', 21.40, 'open', false, 14.20, 1.30, 1.0),
    new StockSeed('000333', '美的集团', 'SZ', 68.20, 'open', false, 13.50, 3.10, 1.0),
    new StockSeed('601899', '紫金矿业', 'SH', 17.90, 'open', false, 16.40, 2.40, 1.0),
    new StockSeed('600276', '恒瑞医药', 'SH', 46.10, 'open', false, 52.30, 6.80, 1.0),
    new StockSeed('600000', '浦发银行', 'SH', 9.80, 'suspended', false, 4.90, 0.55, 0),
    new StockSeed('301999', '新锐科技', 'SZ', 38.60, 'open', true, 39.20, 5.10, 1.0)
  ];
  for (let i = 0; i < 36; i++) {
    const seq: number = i + 1;
    const code: string = `60${2000 + i}`;
    const price: number = 8 + ((i * 37) % 1200) / 10;
    const pe: number = 6 + ((i * 29) % 300) / 10;
    const pb: number = 0.8 + ((i * 13) % 70) / 10;
    seeds.push(new StockSeed(code, `示例科技${seq < 10 ? '0' : ''}${seq}`, 'SH', price, 'open', false, pe, pb, 1.0));
  }
  for (let i = 0; i < seeds.length; i++) {
    const seed: StockSeed = seeds[i];
    seed.groups.push('all');
    const onStar: boolean = seed.code.startsWith('30');
    if (onStar) {
      seed.groups.push('star');
    }
    if (seed.code.startsWith('68')) {
      seed.groups.push('kcb');
    }
    if (i % 3 === 0) {
      seed.groups.push('fin');
    }
    if (i % 4 === 0) {
      seed.groups.push('user');
    }
    // 保证每只票至少属于一个非「全部」分组（INV-1：不存在无组股票）
    if (seed.groups.length === 1) {
      seed.groups.push('user');
    }
  }
  return seeds;
}

export function buildIndexSeeds(): IndexSeed[] {
  return [
    new IndexSeed('IDX000001', '上证指数', 3218.60),
    new IndexSeed('IDX399001', '深证成指', 10142.30),
    new IndexSeed('IDX399006', '创业板指', 1938.20),
    new IndexSeed('IDX000300', '沪深300', 3762.40),
    new IndexSeed('IDX000688', '科创50', 872.50),
    new IndexSeed('IDX399005', '中小100', 6234.50),
    new IndexSeed('IDX000016', '上证50', 2650.30),
    new IndexSeed('IDX399673', '创业板50', 1988.10),
    new IndexSeed('IDX000905', '中证500', 5620.40),
    new IndexSeed('IDX000852', '中证1000', 5980.70),
    new IndexSeed('IDX399102', '创业板综', 2870.20),
    new IndexSeed('IDX000009', '上证380', 5320.90)
  ];
}

/** 分组：全部（虚拟组）+ 系统组（融/创/科）+ 用户组（FR-02.5）。 */
export function buildWatchGroups(): WatchGroup[] {
  return [
    new WatchGroup('all', 'all', 0, ''),
    new WatchGroup('fin', 'system', 1, ''),
    new WatchGroup('star', 'system', 2, ''),
    new WatchGroup('kcb', 'system', 3, ''),
    new WatchGroup('user', 'user', 4, '')
  ];
}

export function buildWatchItems(seeds: StockSeed[]): WatchItem[] {
  const items: WatchItem[] = [];
  for (let i = 0; i < seeds.length; i++) {
    items.push(new WatchItem(seeds[i].code, seeds[i].groups.slice(), 1000 + i));
  }
  return items;
}

/** 分组 → 指数条配置（IndexSet[groupId]，切组整组替换；FR-02.6）。 */
export function buildIndexSet(): Map<string, string[]> {
  const map: Map<string, string[]> = new Map<string, string[]>();
  map.set('all', ['IDX000001', 'IDX399001', 'IDX399006', 'IDX000300']);
  map.set('fin', ['IDX000001', 'IDX000300', 'IDX399001']);
  map.set('star', ['IDX399006', 'IDX000688', 'IDX000300']);
  map.set('user', ['IDX000001', 'IDX399001', 'IDX399006', 'IDX000688']);
  return map;
}
