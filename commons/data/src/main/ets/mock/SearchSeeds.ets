import { Market, TradeStatus } from '../model/QuoteModels';
import { SearchEntry } from '../model/SearchModels';
import { buildIndexSeeds, buildStockSeeds, IndexSeed, StockSeed } from './MarketSeeds';

/**
 * 搜索主数据（M6-1）：股票 ≥60 / 指数 12 / 板块 20，含停牌 / 新股 / 负市盈率样本。
 * 拼音走静态表（D16：不引三方库，控制包体），全拼与首字母均为大写。
 * 股票来源 = 自选种子 50 只（保证「搜索 → 加自选 → 列表」同源）+ 追加 30 只（其中含「茅台镇」样本，供 AC-88 断言 L2 优先于 L3）。
 */

/** 追加股票（不在自选种子里，用于验证「可添加」与板块样本）。 */
export class ExtraStockSeed {
  code: string;
  name: string;
  market: Market;
  pinyin: string;
  initials: string;
  sector: string;
  status: TradeStatus;
  isNew: boolean;

  constructor(code: string, name: string, market: Market, pinyin: string, initials: string,
    sector: string, status: TradeStatus, isNew: boolean) {
    this.code = code;
    this.name = name;
    this.market = market;
    this.pinyin = pinyin;
    this.initials = initials;
    this.sector = sector;
    this.status = status;
    this.isNew = isNew;
  }
}

export function buildExtraStockSeeds(): ExtraStockSeed[] {
  return buildExtraStocks();
}

function buildExtraStocks(): ExtraStockSeed[] {
  return [
    new ExtraStockSeed('600888', '茅台镇酒业', 'SH', 'MAOTAIZHENJIUYE', 'MTZJY', '白酒', 'open', false),
    new ExtraStockSeed('600809', '山西汾酒', 'SH', 'SHANXIFENJIU', 'SXFJ', '白酒', 'open', false),
    new ExtraStockSeed('000568', '泸州老窖', 'SZ', 'LUZHOULAOJIAO', 'LZLJ', '白酒', 'open', false),
    new ExtraStockSeed('600887', '伊利股份', 'SH', 'YILIGUFEN', 'YLGF', '食品饮料', 'open', false),
    new ExtraStockSeed('601398', '工商银行', 'SH', 'GONGSHANGYINHANG', 'GSYH', '银行', 'open', false),
    new ExtraStockSeed('601288', '农业银行', 'SH', 'NONGYEYINHANG', 'NYYH', '银行', 'open', false),
    new ExtraStockSeed('601988', '中国银行', 'SH', 'ZHONGGUOYINHANG', 'ZGYH', '银行', 'open', false),
    new ExtraStockSeed('000002', '万科A', 'SZ', 'WANKEA', 'WKA', '房地产', 'open', false),
    new ExtraStockSeed('600048', '保利发展', 'SH', 'BAOLIFAZHAN', 'BLFZ', '房地产', 'open', false),
    new ExtraStockSeed('601601', '中国太保', 'SH', 'ZHONGGUOTAIBAO', 'ZGTB', '保险', 'open', false),
    new ExtraStockSeed('601628', '中国人寿', 'SH', 'ZHONGGUORENSHOU', 'ZGRS', '保险', 'open', false),
    new ExtraStockSeed('688111', '金山办公', 'SH', 'JINSHANBANGONG', 'JSBG', '计算机', 'open', false),
    new ExtraStockSeed('002415', '海康威视', 'SZ', 'HAIKANGWEISHI', 'HKWS', '计算机', 'open', false),
    new ExtraStockSeed('000725', '京东方A', 'SZ', 'JINGDONGFANGA', 'JDFA', '半导体', 'open', false),
    new ExtraStockSeed('600031', '三一重工', 'SH', 'SANYIZHONGGONG', 'SYZG', '汽车', 'open', false),
    new ExtraStockSeed('601766', '中国中车', 'SH', 'ZHONGGUOZHONGCHE', 'ZGZC', '国防军工', 'open', false),
    new ExtraStockSeed('600900', '长江电力', 'SH', 'CHANGJIANGDIANLI', 'CJDL', '电力设备', 'open', false),
    new ExtraStockSeed('601088', '中国神华', 'SH', 'ZHONGGUOSHENHUA', 'ZGSH', '煤炭', 'open', false),
    new ExtraStockSeed('600019', '宝钢股份', 'SH', 'BAOGANGGUFEN', 'BGGF', '钢铁', 'open', false),
    new ExtraStockSeed('601600', '中国铝业', 'SH', 'ZHONGGUOLVYE', 'ZGLY', '有色金属', 'open', false),
    new ExtraStockSeed('600104', '上汽集团', 'SH', 'SHANGQIJITUAN', 'SQJT', '汽车', 'open', false),
    new ExtraStockSeed('000651', '格力电器', 'SZ', 'GELIDIANQI', 'GLDQ', '家用电器', 'open', false),
    new ExtraStockSeed('600050', '中国联通', 'SH', 'ZHONGGUOLIANTONG', 'ZGLT', '通信', 'open', false),
    new ExtraStockSeed('300059', '东方财富', 'SZ', 'DONGFANGCAIFU', 'DFCF', '证券', 'open', false),
    new ExtraStockSeed('601888', '中国中免', 'SH', 'ZHONGGUOZHONGMIAN', 'ZGZM', '食品饮料', 'open', false),
    new ExtraStockSeed('603259', '药明康德', 'SH', 'YAOMINGKANGDE', 'YMKD', '医药', 'open', false),
    new ExtraStockSeed('600585', '海螺水泥', 'SH', 'HAILUOSHUINI', 'HLSN', '化工', 'open', false),
    new ExtraStockSeed('601012', '隆基绿能', 'SH', 'LONGJILVNENG', 'LJLN', '新能源', 'open', false),
    new ExtraStockSeed('002714', '牧原股份', 'SZ', 'MUYUANGUFEN', 'MYGF', '食品饮料', 'open', false),
    new ExtraStockSeed('600690', '海尔智家', 'SH', 'HAIERZHIJIA', 'HEZJ', '家用电器', 'open', false)
  ];
}

/** 自选种子内的 14 只具名股票拼音表；其余「示例科技NN」按下标推导。 */
function buildNamedPinyin(): Map<string, string[]> {
  const map: Map<string, string[]> = new Map<string, string[]>();
  map.set('600519', ['GUIZHOUMAOTAI', 'GZMT']);
  map.set('000001', ['PINGANYINHANG', 'PAYH']);
  map.set('300750', ['NINGDESHIDAI', 'NDSD']);
  map.set('688981', ['ZHONGXINGUOJI', 'ZXGJ']);
  map.set('600036', ['ZHAOSHANGYINHANG', 'ZSYH']);
  map.set('000858', ['WULIANGYE', 'WLY']);
  map.set('601318', ['ZHONGGUOPINGAN', 'ZGPA']);
  map.set('002594', ['BIYADI', 'BYD']);
  map.set('600030', ['ZHONGXINZHENGQUAN', 'ZXZQ']);
  map.set('000333', ['MEIDEJITUAN', 'MDJT']);
  map.set('601899', ['ZIJINKUANGYE', 'ZJKY']);
  map.set('600276', ['HENGRUIYIYAO', 'HRYY']);
  map.set('600000', ['PUFANYINHANG', 'PFYH']);
  map.set('301999', ['XINRUIKEJI', 'XRKJ']);
  return map;
}

function stockSectorOf(code: string): string {
  if (code === '600519' || code === '000858') {
    return '白酒';
  }
  if (code === '000001' || code === '600036' || code === '600000') {
    return '银行';
  }
  return '示例板块';
}

function entryOfStock(seed: StockSeed, pinyin: string, initials: string, sector: string): SearchEntry {
  return {
    code: seed.code,
    name: seed.name,
    kind: 'stock',
    market: seed.market,
    status: seed.status,
    isNew: seed.isNew,
    pinyin: pinyin,
    initials: initials,
    sector: sector,
    tags: [],
    staticPrice: 0,
    staticPct: 0
  };
}

function buildStockEntries(): SearchEntry[] {
  const entries: SearchEntry[] = [];
  const named: Map<string, string[]> = buildNamedPinyin();
  const seeds: StockSeed[] = buildStockSeeds();
  for (let i = 0; i < seeds.length; i++) {
    const seed: StockSeed = seeds[i];
    let pinyin: string = '';
    let initials: string = '';
    const hit: string[] | undefined = named.get(seed.code);
    if (hit !== undefined) {
      pinyin = hit[0];
      initials = hit[1];
    } else {
      const seq: string = seed.name.substring(4);
      pinyin = `SHILIKEJI${seq}`;
      initials = 'SLKJ';
    }
    entries.push(entryOfStock(seed, pinyin, initials, stockSectorOf(seed.code)));
  }
  const extra: ExtraStockSeed[] = buildExtraStocks();
  for (let i = 0; i < extra.length; i++) {
    const seed: ExtraStockSeed = extra[i];
    const asStock: StockSeed = new StockSeed(seed.code, seed.name, seed.market, 10, seed.status,
      seed.isNew, 10, 1, 1);
    entries.push(entryOfStock(asStock, seed.pinyin, seed.initials, seed.sector));
  }
  return entries;
}

function buildIndexEntries(): SearchEntry[] {
  const entries: SearchEntry[] = [];
  const seeds: IndexSeed[] = buildIndexSeeds();
  for (let i = 0; i < seeds.length; i++) {
    const seed: IndexSeed = seeds[i];
    entries.push({
      code: seed.code,
      name: seed.name,
      kind: 'index',
      market: 'SH',
      status: 'open',
      isNew: false,
      pinyin: indexPinyinOf(seed.code),
      initials: indexInitialsOf(seed.code),
      sector: '',
      tags: [],
      staticPrice: seed.base,
      staticPct: 0
    });
  }
  return entries;
}

function indexPinyinOf(code: string): string {
  if (code === 'IDX000001') {
    return 'SHANGZHENGZHISHU';
  }
  if (code === 'IDX399001') {
    return 'SHENZHENGCHENGZHI';
  }
  if (code === 'IDX399006') {
    return 'CHUANGYEBANZHI';
  }
  if (code === 'IDX000300') {
    return 'HUSHEN300';
  }
  if (code === 'IDX000688') {
    return 'KECHUANG50';
  }
  if (code === 'IDX399005') {
    return 'ZHONGXIAO100';
  }
  if (code === 'IDX000016') {
    return 'SHANGZHENG50';
  }
  if (code === 'IDX399673') {
    return 'CHUANGYEBAN50';
  }
  if (code === 'IDX000905') {
    return 'ZHONGZHENG500';
  }
  if (code === 'IDX000852') {
    return 'ZHONGZHENG1000';
  }
  if (code === 'IDX399102') {
    return 'CHUANGYEBANZONG';
  }
  return 'SHANGZHENG380';
}

function indexInitialsOf(code: string): string {
  if (code === 'IDX000001') {
    return 'SZZS';
  }
  if (code === 'IDX399001') {
    return 'SZCZ';
  }
  if (code === 'IDX399006') {
    return 'CYBZ';
  }
  if (code === 'IDX000300') {
    return 'HS300';
  }
  if (code === 'IDX000688') {
    return 'KC50';
  }
  if (code === 'IDX399005') {
    return 'ZX100';
  }
  if (code === 'IDX000016') {
    return 'SZ50';
  }
  if (code === 'IDX399673') {
    return 'CYB50';
  }
  if (code === 'IDX000905') {
    return 'ZZ500';
  }
  if (code === 'IDX000852') {
    return 'ZZ1000';
  }
  if (code === 'IDX399102') {
    return 'CYBZONG';
  }
  return 'SZ380';
}

class SectorSeed {
  code: string;
  name: string;
  pinyin: string;
  initials: string;
  pct: number;

  constructor(code: string, name: string, pinyin: string, initials: string, pct: number) {
    this.code = code;
    this.name = name;
    this.pinyin = pinyin;
    this.initials = initials;
    this.pct = pct;
  }
}

function buildSectorEntries(): SearchEntry[] {
  const seeds: SectorSeed[] = [
    new SectorSeed('BK0001', '白酒', 'BAIJIU', 'BJ', 1.62),
    new SectorSeed('BK0002', '银行', 'YINHANG', 'YH', 0.35),
    new SectorSeed('BK0003', '半导体', 'BANDAOTI', 'BDT', 2.18),
    new SectorSeed('BK0004', '新能源', 'XINNENGYUAN', 'XNY', 1.05),
    new SectorSeed('BK0005', '证券', 'ZHENGQUAN', 'ZQ', -0.42),
    new SectorSeed('BK0006', '保险', 'BAOXIAN', 'BX', 0.58),
    new SectorSeed('BK0007', '医药', 'YIYAO', 'YY', -1.23),
    new SectorSeed('BK0008', '房地产', 'FANGDICHAN', 'FDC', 0.16),
    new SectorSeed('BK0009', '煤炭', 'MEITAN', 'MT', 0.92),
    new SectorSeed('BK0010', '钢铁', 'GANGTIE', 'GT', -0.35),
    new SectorSeed('BK0011', '有色金属', 'YOUSEJINSHU', 'YSJS', 1.44),
    new SectorSeed('BK0012', '汽车', 'QICHE', 'QC', 0.71),
    new SectorSeed('BK0013', '国防军工', 'GUOFANGJUNGONG', 'GFJG', -0.88),
    new SectorSeed('BK0014', '计算机', 'JISUANJI', 'JSJ', 1.96),
    new SectorSeed('BK0015', '通信', 'TONGXIN', 'TX', 0.63),
    new SectorSeed('BK0016', '传媒', 'CHUANMEI', 'CM', -0.54),
    new SectorSeed('BK0017', '食品饮料', 'SHIPINYINLIAO', 'SPYL', 0.84),
    new SectorSeed('BK0018', '家用电器', 'JIAYONGDIANQI', 'JYDQ', 0.27),
    new SectorSeed('BK0019', '化工', 'HUAGONG', 'HG', -0.19),
    new SectorSeed('BK0020', '电力设备', 'DIANLISHEBEI', 'DLSB', 1.12)
  ];
  const entries: SearchEntry[] = [];
  for (let i = 0; i < seeds.length; i++) {
    const seed: SectorSeed = seeds[i];
    entries.push({
      code: seed.code,
      name: seed.name,
      kind: 'sector',
      market: 'SH',
      status: 'open',
      isNew: false,
      pinyin: seed.pinyin,
      initials: seed.initials,
      sector: seed.name,
      tags: [],
      staticPrice: 0,
      staticPct: seed.pct
    });
  }
  return entries;
}

/** 全量搜索主数据（股票 + 指数 + 板块），按 code 去重。 */
export function buildSearchEntries(): SearchEntry[] {
  const entries: SearchEntry[] = buildStockEntries();
  const seen: Set<string> = new Set<string>();
  for (let i = 0; i < entries.length; i++) {
    seen.add(entries[i].code);
  }
  const indices: SearchEntry[] = buildIndexEntries();
  for (let i = 0; i < indices.length; i++) {
    if (!seen.has(indices[i].code)) {
      seen.add(indices[i].code);
      entries.push(indices[i]);
    }
  }
  const sectors: SearchEntry[] = buildSectorEntries();
  for (let i = 0; i < sectors.length; i++) {
    if (!seen.has(sectors[i].code)) {
      seen.add(sectors[i].code);
      entries.push(sectors[i]);
    }
  }
  return entries;
}

/** 热搜词（G-1 两列 × 5 行；前三名加角标）。失败时视图整块隐藏（AC-90）。 */
export function buildHotWords(): string[] {
  return ['贵州茅台', '宁德时代', '中芯国际', '比亚迪', '平安银行',
    '白酒', '半导体', '新能源', '上证指数', '招商银行'];
}
