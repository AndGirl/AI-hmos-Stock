/**
 * 原型用模拟数据（V0.2 验证 11 列冻结横滑）
 * 字段均为展示字符串；正式实现由 MockQuoteProvider 提供数值。
 */

export interface WatchRow {
  code: string;
  name: string;
  tag: string;
  last: string;
  chg: string;
  pct: string;
  volume: string;
  current: string;
  amount: string;
  amplitude: string;
  turnover: string;
  pe: string;
  pb: string;
  dir: number; // 1 涨 / -1 跌 / 0 平或空值
}

export const MOCK_ROWS: WatchRow[] = [
  { code: '603103', name: '某某科技', tag: '融', last: '20.01', chg: '+0.17', pct: '+0.86%', volume: '310511', current: '1232', amount: '12.5亿', amplitude: '3.21%', turnover: '0.39%', pe: '95.32', pb: '8.21', dir: 1 },
  { code: '000001', name: '平安银行', tag: '', last: '11.24', chg: '+0.14', pct: '+1.26%', volume: '887421', current: '905', amount: '9.9亿', amplitude: '2.10%', turnover: '0.51%', pe: '4.87', pb: '0.52', dir: 1 },
  { code: '600519', name: '贵州茅台', tag: '融', last: '1685.00', chg: '-5.00', pct: '-0.30%', volume: '30176', current: '88', amount: '50.8亿', amplitude: '1.42%', turnover: '0.24%', pe: '22.15', pb: '7.90', dir: -1 },
  { code: '300750', name: '宁德时代', tag: '创', last: '188.60', chg: '+2.40', pct: '+1.29%', volume: '19593', current: '3461', amount: '36.9亿', amplitude: '2.88%', turnover: '0.47%', pe: '19.42', pb: '3.88', dir: 1 },
  { code: '002594', name: '比亚迪', tag: '融', last: '256.80', chg: '0.00', pct: '0.00%', volume: '7071', current: '4890', amount: '18.1亿', amplitude: '1.05%', turnover: '0.61%', pe: '28.33', pb: '4.02', dir: 0 },
  { code: '601318', name: '中国平安', tag: '融', last: '52.43', chg: '-0.37', pct: '-0.70%', volume: '445120', current: '2130', amount: '23.3亿', amplitude: '1.33%', turnover: '0.27%', pe: '8.11', pb: '0.94', dir: -1 },
  { code: '600036', name: '招商银行', tag: '', last: '38.90', chg: '+0.52', pct: '+1.35%', volume: '312004', current: '1502', amount: '12.1亿', amplitude: '1.88%', turnover: '0.15%', pe: '6.72', pb: '0.89', dir: 1 },
  { code: '000858', name: '五粮液', tag: '融', last: '142.10', chg: '-1.20', pct: '-0.84%', volume: '88 412', current: '640', amount: '12.6亿', amplitude: '1.70%', turnover: '0.23%', pe: '16.04', pb: '3.55', dir: -1 },
  { code: '601899', name: '紫金矿业', tag: '', last: '18.66', chg: '+0.44', pct: '+2.42%', volume: '1203345', current: '7810', amount: '22.2亿', amplitude: '3.12%', turnover: '0.58%', pe: '15.28', pb: '3.11', dir: 1 },
  { code: '688981', name: '中芯国际', tag: '科', last: '96.30', chg: '+3.10', pct: '+3.33%', volume: '203344', current: '990', amount: '19.4亿', amplitude: '4.02%', turnover: '1.02%', pe: '112.60', pb: '4.88', dir: 1 },
  { code: '000651', name: '格力电器', tag: '融', last: '45.02', chg: '-0.18', pct: '-0.40%', volume: '150233', current: '770', amount: '6.8亿', amplitude: '0.97%', turnover: '0.25%', pe: '8.44', pb: '2.01', dir: -1 },
  { code: '600030', name: '中信证券', tag: '融', last: '28.77', chg: '+0.66', pct: '+2.35%', volume: '915420', current: '4320', amount: '26.1亿', amplitude: '3.05%', turnover: '0.78%', pe: '17.92', pb: '1.44', dir: 1 },
  { code: '300059', name: '东方财富', tag: '创', last: '22.18', chg: '--', pct: '--', volume: '--', current: '--', amount: '--', amplitude: '--', turnover: '--', pe: '--', pb: '--', dir: 0 },
  { code: '601012', name: '隆基绿能', tag: '', last: '17.55', chg: '-0.09', pct: '-0.51%', volume: '402118', current: '2210', amount: '7.1亿', amplitude: '1.24%', turnover: '0.53%', pe: '25.40', pb: '1.98', dir: -1 },
  { code: '600887', name: '伊利股份', tag: '融', last: '29.84', chg: '+0.21', pct: '+0.71%', volume: '120998', current: '880', amount: '3.6亿', amplitude: '1.12%', turnover: '0.19%', pe: '18.75', pb: '3.02', dir: 1 },
  { code: '002415', name: '海康威视', tag: '融', last: '33.06', chg: '+0.15', pct: '+0.46%', volume: '210455', current: '1320', amount: '6.9亿', amplitude: '1.45%', turnover: '0.23%', pe: '21.08', pb: '3.44', dir: 1 }
];
