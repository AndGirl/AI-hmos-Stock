import { hilog } from '@kit.PerformanceAnalysisKit';
import { AnalyticsHost, AnalyticsParam, ConnectionHost, ConnectionHub } from 'commons_basic';
import {
  AccountInfo,
  AuthSession,
  MockFaults,
  OrderDraft,
  OrderResult,
  OrderSide,
  TradeAuth,
  TradeContext,
  TradeSource,
  Tradable
} from 'commons_data';
import { TradeRepository } from '../repository/TradeRepository';
import {
  clampPrice,
  commitQtyValue,
  computeCanBuy,
  defaultPrice,
  defaultQty,
  FieldError,
  LOT_SIZE,
  OrderErrorCode,
  QtyCommit,
  resolveGate,
  roundPrice,
  sanitizePriceInput,
  stepPrice,
  stepQty,
  TradeGate,
  validateOrder
} from '../repository/TradeRules';
import { formatPrice, formatQty, formatQueryTime, TradeId } from '../repository/TradeFormat';

const DOMAIN: number = 0x0001;
/** 提交后 2s 无反馈 → 结果未知（不自动重发，FR-07.8）。 */
const SUBMIT_TIMEOUT_MS: number = 2000;
/** 成功 toast 后 700ms 自动关闭回详情。 */
const CLOSE_DELAY_MS: number = 700;

/** 单容器两层（INV-T2）：只渲染 edit 或 confirm 之一。 */
export type TradeStep = 'edit' | 'confirm';

export type TradePhase = 'resolving' | 'login' | 'edit' | 'confirm' | 'closed';

export type TradeFieldErrorCode =
  '' | 'price_empty' | 'price_above' | 'price_below' | 'qty_empty' | 'qty_lot' | 'qty_over';

/** 弹窗内提示条：断线 / 非交易时段 / 资金不足（FR-07.10）。 */
export type TradeBlockCode = '' | 'offline' | 'closed' | 'fund_short' | 'no_holding';

export type TradeHintCode = '' | 'price_up' | 'price_down' | 'qty_can_buy';

export type TradeToastCode =
  '' | 'no_account' | 'suspended' | 'delisted' | 'submitting' | 'load_failed' | 'success' | 'query_done';

/** 失败原因码：网关 code 映射，未知码按风控拦截（只展示，不自造规则）。 */
export type TradeFailCode = '' | 'fund_short' | 'price_limit' | 'closed' | 'risk';

export type TradeQueryStatus = '' | 'accepted' | 'not_found';

export type TradeEditField = '' | 'price' | 'qty';

/** 调试故障注入（debug 构建）：对应 FR-07.10 的 8 业务态 + 2 过程态。 */
export type TradeFaultKind =
  'login' | 'account' | 'offline' | 'closed' | 'fund' | 'reject' | 'timeout' | 'reset';

function failCodeOf(code: string): TradeFailCode {
  if (code === 'fund_short' || code === 'price_limit' || code === 'closed' || code === 'risk') {
    return code;
  }
  return 'risk';
}

/**
 * 买入委托 VM（L3）：门禁、字段、校验、确认层、提交三态、幂等与超时计时、关闭矩阵。
 * 不含 UI 副作用（R-08）：toast/弹层由视图按 code 渲染。
 */
@ObservedV2
export class TradeVM {
  @Trace phase: TradePhase = 'closed';
  @Trace symbolText: string = '';
  @Trace codeText: string = '';
  @Trace accountText: string = '';
  @Trace accountLabels: string[] = [];
  @Trace accountIndex: number = 0;
  @Trace priceText: string = '0.00';
  @Trace qtyText: string = '0';
  @Trace limitDownText: string = '0.00';
  @Trace limitUpText: string = '0.00';
  @Trace canBuyText: string = '0';
  /** M10：可卖数量文案（卖出方向生效）。 */
  @Trace canSellText: string = '0';
  /** M10：买卖方向（默认买入；切换后上限与默认数量随之变化）。 */
  @Trace side: OrderSide = 'buy';
  @Trace holdText: string = '0';
  @Trace priceError: TradeFieldErrorCode = '';
  @Trace qtyError: TradeFieldErrorCode = '';
  @Trace blockCode: TradeBlockCode = '';
  @Trace hintCode: TradeHintCode = '';
  @Trace editing: TradeEditField = '';
  @Trace priceInput: string = '';
  @Trace qtyInput: string = '';
  @Trace toastCode: TradeToastCode = '';
  @Trace toastSeq: number = 0;
  @Trace submitting: boolean = false;
  @Trace unknown: boolean = false;
  @Trace failCode: TradeFailCode = '';
  @Trace queryStatus: TradeQueryStatus = '';
  @Trace queryOrderId: string = '';
  @Trace queryTimeText: string = '';
  @Trace querying: boolean = false;
  @Trace loggingIn: boolean = false;
  @Trace clientOrderIdText: string = '';

  code: string = '';
  private source: TradeSource = 'detail';
  private repo: TradeRepository = new TradeRepository();
  /** 弹窗打开期间实时断线（M5：ConnectionHub 驱动，无需重开弹窗）。 */
  private netOffline: boolean = false;
  private tradable: Tradable | null = null;
  private accounts: AccountInfo[] = [];
  private baseGate: TradeGate = TradeGate.Ready;
  private price: number = 0;
  private qty: number = 0;
  private canBuy: number = 0;
  private canSell: number = 0;
  private clientOrderId: string = '';
  private submitToken: number = 0;
  /** 上下文加载令牌：换标的/关闭后丢弃过期回执，避免旧价格/旧账户回填。 */
  private loadToken: number = 0;
  private submitTimer: number = -1;
  private closeTimer: number = -1;
  private openStartMs: number = 0;

  /** 打开弹窗：加载上下文 → 门禁 → 登录层 / 编辑层 / 入口拦截。 */
  attach(code: string, source: TradeSource): void {
    this.code = code;
    this.source = source;
    this.reset();
    this.loadToken++;
    const token: number = this.loadToken;
    this.phase = 'resolving';
    this.openStartMs = Date.now();
    this.repo.loadContext(code, source).then((ctx: TradeContext): void => {
      if (token !== this.loadToken) {
        return;
      }
      this.applyContext(ctx);
      hilog.info(DOMAIN, 'TradePerf', 'context code=%{public}s ms=%{public}d source=%{public}s',
        this.code, Date.now() - this.openStartMs, source);
    }).catch((err: Error): void => {
      if (token !== this.loadToken) {
        return;
      }
      hilog.info(DOMAIN, 'TradePerf', 'context_fail code=%{public}s ms=%{public}d', this.code,
        Date.now() - this.openStartMs);
      this.raiseToast('load_failed');
      this.phase = 'closed';
    });
  }

  /** 登录层：Mock 登录成功后回到原标的自动续开（DEC-07-07）。 */
  login(): void {
    if (this.loggingIn) {
      return;
    }
    this.loggingIn = true;
    this.repo.login().then((): void => {
      this.loggingIn = false;
      this.attach(this.code, this.source);
    }).catch((): void => {
      this.loggingIn = false;
      this.raiseToast('load_failed');
    });
  }

  /** 关闭入口（X / 遮罩 / 系统返回）统一走这里（FR-07.9）。 */
  tryClose(): boolean {
    if (this.submitting) {
      hilog.info(DOMAIN, 'TradeLog', 'trade_close_blocked submitting');
      this.raiseToast('submitting');
      return false;
    }
    this.closeNow();
    return true;
  }

  /** 系统返回 / 侧滑：确认层回编辑层并保留输入，编辑层关闭。 */
  back(): void {
    if (this.submitting) {
      this.raiseToast('submitting');
      return;
    }
    if (this.phase === 'confirm') {
      this.phase = 'edit';
      return;
    }
    this.closeNow();
  }

  /** 点遮罩：确认层不关闭（防误触），提交中不关闭。 */
  tapBackdrop(): void {
    if (this.submitting || this.phase === 'confirm') {
      return;
    }
    this.closeNow();
  }

  stepPrice(delta: number): void {
    if (!this.canEdit()) {
      return;
    }
    if (!this.commitPending()) {
      return;
    }
    this.price = stepPrice(this.price, delta, this.limitDown(), this.limitUp());
    this.clearErrors();
    this.hintCode = '';
    this.syncPrice();
    this.recomputeCanBuy();
    this.refreshBlock();
    this.logValue('price');
  }

  stepQty(delta: number): void {
    if (!this.canEdit()) {
      return;
    }
    if (!this.commitPending()) {
      return;
    }
    this.qty = stepQty(this.qty, delta, this.maxQty());
    this.clearErrors();
    this.hintCode = '';
    this.syncQty();
    this.logValue('qty');
  }

  beginEdit(field: TradeEditField): void {
    if (!this.canEdit() || field === '') {
      return;
    }
    this.editing = field;
    hilog.info(DOMAIN, 'TradeLog', 'trade_edit_begin field=%{public}s', field);
    if (field === 'price') {
      this.priceInput = formatPrice(this.price);
    } else {
      this.qtyInput = formatQty(this.qty);
    }
  }

  /** 手输入框：逐字符过滤到两位小数（FR-07.4），非法字符直接丢弃；一旦输入即清掉旧错误。 */
  setPriceInput(raw: string): void {
    this.priceInput = sanitizePriceInput(raw);
    if (this.priceError !== '') {
      this.priceError = '';
    }
  }

  /** 手输提交：空/非数字就地拒绝并保留原值；超区间修正到边界并说明。 */
  commitPrice(raw: string): void {
    const text: string = raw.trim();
    const value: number = text.length === 0 ? Number.NaN : Number(text);
    if (!Number.isFinite(value) || value <= 0) {
      // 保留编辑态与错误，让用户就地改；不静默回退到上一次价格（FR-07.6）。
      this.priceError = 'price_empty';
      return;
    }
    this.editing = '';
    let next: number = roundPrice(value);
    const up: number = this.limitUp();
    const down: number = this.limitDown();
    if (up > 0 && next > up) {
      next = up;
      this.hintCode = 'price_up';
    } else if (down > 0 && next < down) {
      next = down;
      this.hintCode = 'price_down';
    } else {
      this.hintCode = '';
    }
    this.price = clampPrice(next, down, up);
    this.priceError = '';
    this.syncPrice();
    this.recomputeCanBuy();
    this.refreshBlock();
    this.logValue('price');
  }

  commitQty(raw: string): void {
    const text: string = raw.trim();
    const value: number = text.length === 0 ? Number.NaN : Number(text);
    if (!Number.isFinite(value) || value <= 0) {
      // 同上：非法数量保留编辑态与错误。
      this.qtyError = 'qty_empty';
      return;
    }
    this.editing = '';
    const commit: QtyCommit = commitQtyValue(value, this.maxQty());
    this.qty = commit.value;
    this.hintCode = commit.corrected ? 'qty_can_buy' : '';
    this.qtyError = '';
    this.syncQty();
    this.logValue('qty');
  }

  switchAccount(index: number): void {
    if (index < 0 || index >= this.accounts.length || index === this.accountIndex) {
      return;
    }
    this.accountIndex = index;
    const account: AccountInfo | null = this.activeAccount();
    if (account === null) {
      return;
    }
    this.accountText = account.maskNo;
    this.holdText = formatQty(account.holdQty);
    this.recomputeCanBuy();
    this.qty = this.maxQty() >= LOT_SIZE ? Math.min(Math.max(this.qty, LOT_SIZE), this.maxQty()) : 0;
    this.syncQty();
    this.hintCode = '';
    this.clearErrors();
    this.refreshBlock();
    this.accountLabels = this.buildAccountLabels();
    hilog.info(DOMAIN, 'TradeLog', 'trade_account_switch account=%{public}s', account.id);
  }

  /** 点「买入」：单一校验出口，不通过不得进确认层（FR-07.6 / AC-71）。 */
  buy(): boolean {
    if (!this.canEdit()) {
      return false;
    }
    // 点「买入」前先落定未提交的手输值（失焦/回车之外的第三条路径）。
    // 顺序：先清旧错误 → 再落定输入；落定失败直接返回，禁止拿旧值进确认层。
    this.clearErrors();
    this.hintCode = '';
    if (!this.commitPending()) {
      hilog.info(DOMAIN, 'TradeLog', 'trade_validate_fail count=0 source=pending_input');
      return false;
    }
    const errors: FieldError[] = validateOrder(this.price, this.qty, this.limitUp(), this.limitDown(),
      this.maxQty());
    for (let i = 0; i < errors.length; i++) {
      this.applyFieldError(errors[i]);
    }
    if (errors.length > 0) {
      hilog.info(DOMAIN, 'TradeLog', 'trade_validate_fail count=%{public}d', errors.length);
      return false;
    }
    this.phase = 'confirm';
    this.failCode = '';
    this.unknown = false;
    hilog.info(DOMAIN, 'TradeLog', 'trade_confirm_view price=%{public}s qty=%{public}s',
      formatPrice(this.price), formatQty(this.qty));
    return true;
  }

  /** 确认层提交：按钮 loading、关闭入口失效、重复点击丢弃、2s 超时进入结果未知。 */
  submit(): void {
    if (this.submitting || this.unknown || this.phase !== 'confirm') {
      return;
    }
    if (this.blockCode !== '') {
      // 断线 / 非交易时段 / 资金不足：确认层同样不得提交（FR-07.10 / CC-7.6）。
      hilog.info(DOMAIN, 'TradeLog', 'trade_submit_blocked block=%{public}s', this.blockCode);
      return;
    }
    const account: AccountInfo | null = this.activeAccount();
    if (account === null) {
      this.raiseToast('no_account');
      return;
    }
    if (this.clientOrderId.length === 0) {
      this.clientOrderId = TradeId.next();
    }
    this.clientOrderIdText = this.clientOrderId;
    this.submitting = true;
    this.failCode = '';
    this.queryStatus = '';
    this.queryOrderId = '';
    this.queryTimeText = '';
    this.submitToken++;
    const token: number = this.submitToken;
    // 提交前再收口一次精度：价格两位小数、数量整股（FR-07.4 / FR-07.5）。
    const draft: OrderDraft = new OrderDraft(this.code, account.id, roundPrice(this.price),
      Math.round(this.qty), this.clientOrderId, this.side);
    hilog.info(DOMAIN, 'TradeLog', 'trade_submit clientOrderId=%{public}s', this.clientOrderId);
    this.track('submit', [new AnalyticsParam('code', this.code)]);
    this.submitTimer = setTimeout((): void => {
      if (token !== this.submitToken || !this.submitting) {
        return;
      }
      // 超时：结果未知，不自动重发，主按钮禁用并给「查询委托」。
      this.submitting = false;
      this.unknown = true;
      hilog.info(DOMAIN, 'TradePerf', 'submit_timeout clientOrderId=%{public}s', this.clientOrderId);
      hilog.info(DOMAIN, 'TradeLog', 'trade_result_unknown clientOrderId=%{public}s',
        this.clientOrderId);
      this.track('result_unknown', [new AnalyticsParam('code', this.code)]);
    }, SUBMIT_TIMEOUT_MS);
    this.repo.submit(draft).then((result: OrderResult): void => {
      if (token !== this.submitToken) {
        return;
      }
      this.clearSubmitTimer();
      if (this.unknown) {
        // 已判超时：迟到的回执不改变状态，只供「查询委托」核对。
        return;
      }
      this.submitting = false;
      if (result.status === 'accepted') {
        this.onAccepted(result);
      } else {
        this.failCode = failCodeOf(result.code);
        hilog.info(DOMAIN, 'TradeLog', 'trade_result_fail code=%{public}s', result.code);
        this.track('result_fail', [new AnalyticsParam('reason', result.code)]);
      }
    }).catch((): void => {
      if (token !== this.submitToken) {
        return;
      }
      this.clearSubmitTimer();
      if (this.unknown) {
        return;
      }
      this.submitting = false;
      this.failCode = 'risk';
    });
  }

  /** 结果未知时查询委托（不做委托列表，FR-07.8）。 */
  query(): void {
    if (this.querying || this.clientOrderId.length === 0) {
      return;
    }
    this.querying = true;
    this.repo.query(this.clientOrderId).then((result: OrderResult): void => {
      this.querying = false;
      this.queryStatus = result.status === 'accepted' ? 'accepted' : 'not_found';
      this.queryOrderId = result.orderId;
      this.queryTimeText = formatQueryTime(result.ts);
      hilog.info(DOMAIN, 'TradeLog', 'trade_query status=%{public}s', this.queryStatus);
      this.track('trade_query', [new AnalyticsParam('status', this.queryStatus)]);
    }).catch((): void => {
      this.querying = false;
      this.queryStatus = 'not_found';
    });
  }

  /** 关闭 / 页面销毁：释放计时器（FR-07.14：不残留定时器）。 */
  dispose(): void {
    this.clearSubmitTimer();
    this.clearCloseTimer();
    this.submitToken++;
    this.loadToken++;
  }

  /**
   * 调试故障注入（仅 debug 面板调用）：改开关后重新加载上下文，用于逐态验收。
   * 真实实现里这些状态由账户中心 / 行情连接 / 交易网关给出。
   */
  applyMockFault(kind: TradeFaultKind): void {
    MockFaults.tradeNoAccount = kind === 'account';
    MockFaults.tradeOffline = kind === 'offline';
    // 断线同时驱动全局 ConnectionHub，弹窗内的提示条走实时路径（M5-1）。
    const hub: ConnectionHub = ConnectionHost.getService();
    if (kind === 'offline') {
      MockFaults.netFault = 'offline';
      hub.force('offline');
    } else if (kind === 'reset') {
      MockFaults.netFault = 'none';
      hub.reset();
    }
    MockFaults.tradeClosed = kind === 'closed';
    MockFaults.tradeFundShort = kind === 'fund';
    MockFaults.tradeReject = kind === 'reject';
    MockFaults.tradeTimeout = kind === 'timeout';
    if (kind === 'reset') {
      MockFaults.reset();
      TradeAuth.reset();
    } else {
      TradeAuth.loggedIn = kind !== 'login';
    }
    hilog.info(DOMAIN, 'TradeLog', 'trade_fault kind=%{public}s', kind);
    this.attach(this.code, this.source);
  }

  private reset(): void {
    this.dispose();
    this.priceError = '';
    this.qtyError = '';
    this.blockCode = '';
    this.hintCode = '';
    // M10：每次打开弹窗都从「买入」开始（上次的卖出方向不残留）。
    this.side = 'buy';
    this.editing = '';
    this.priceInput = '';
    this.qtyInput = '';
    this.submitting = false;
    this.unknown = false;
    this.failCode = '';
    this.queryStatus = '';
    this.queryOrderId = '';
    this.queryTimeText = '';
    this.querying = false;
    this.loggingIn = false;
    this.accountIndex = 0;
    this.accountLabels = [];
    this.clientOrderId = '';
    this.tradable = null;
    this.accounts = [];
  }

  private applyContext(ctx: TradeContext): void {
    this.tradable = ctx.tradable;
    this.accounts = ctx.accounts;
    this.accountIndex = 0;
    this.symbolText = ctx.tradable.name;
    this.codeText = ctx.tradable.code;
    this.limitDownText = formatPrice(ctx.tradable.limitDown);
    this.limitUpText = formatPrice(ctx.tradable.limitUp);
    const account: AccountInfo | null = this.activeAccount();
    if (account !== null) {
      this.accountText = account.maskNo;
      this.holdText = formatQty(account.holdQty);
    }
    this.price = defaultPrice(ctx.tradable.last, ctx.tradable.prevClose, ctx.tradable.limitDown,
      ctx.tradable.limitUp);
    this.syncPrice();
    this.recomputeCanBuy();
    this.qty = defaultQty(this.maxQty());
    this.syncQty();
    this.accountLabels = this.buildAccountLabels();
    this.clientOrderIdText = '';
    this.baseGate = resolveGate(new AuthSession(ctx.loggedIn), account, ctx.tradable, ctx.online);
    if (this.baseGate === TradeGate.NeedLogin) {
      this.phase = 'login';
      return;
    }
    if (this.baseGate === TradeGate.NoAccount) {
      this.raiseToast('no_account');
      this.phase = 'closed';
      return;
    }
    if (this.baseGate === TradeGate.Suspended) {
      this.raiseToast('suspended');
      this.phase = 'closed';
      return;
    }
    if (this.baseGate === TradeGate.Delisted) {
      this.raiseToast('delisted');
      this.phase = 'closed';
      return;
    }
    this.refreshBlock();
    this.phase = 'edit';
    // 幂等键：进入弹窗（登录成功后进入编辑层）生成一次，流程内复用。
    this.clientOrderId = TradeId.next();
    this.clientOrderIdText = this.clientOrderId;
    hilog.info(DOMAIN, 'TradeLog', 'trade_open code=%{public}s account=%{public}s canBuy=%{public}d',
      this.code, account !== null ? account.id : '', this.canBuy);
    // 合规：只上报 code 与来源，账号/资金/数量不进埋点。
    this.track('modal_open', [new AnalyticsParam('kind', 'trade'),
      new AnalyticsParam('source', this.source)]);
  }

  private onAccepted(result: OrderResult): void {
    this.failCode = '';
    this.queryOrderId = result.orderId;
    this.queryTimeText = formatQueryTime(result.ts);
    this.queryStatus = 'accepted';
    this.raiseToast('success');
    hilog.info(DOMAIN, 'TradePerf', 'submit_ok clientOrderId=%{public}s orderId=%{public}s',
      result.clientOrderId, result.orderId);
    hilog.info(DOMAIN, 'TradeLog', 'trade_result_success orderId=%{public}s', result.orderId);
    this.track('result_success', [new AnalyticsParam('code', this.code)]);
    // 成功后 700ms 自动关闭回详情（不可拦截）。
    this.clearCloseTimer();
    this.closeTimer = setTimeout((): void => {
      this.phase = 'closed';
    }, CLOSE_DELAY_MS);
    // 成功后作废幂等键，下次打开重新生成。
    this.clientOrderId = '';
  }

  private closeNow(): void {
    this.dispose();
    this.phase = 'closed';
  }

  private canEdit(): boolean {
    return this.phase === 'edit' && !this.submitting;
  }

  /**
   * 手输未失焦时直接点步进/买入：先按输入框内容提交，避免读旧值。
   * 返回 false 表示输入非法，调用方必须中止本次操作。
   */
  private commitPending(): boolean {
    if (this.editing === 'price') {
      this.commitPrice(this.priceInput);
      return this.priceError === '';
    }
    if (this.editing === 'qty') {
      this.commitQty(this.qtyInput);
      return this.qtyError === '';
    }
    return true;
  }

  private activeAccount(): AccountInfo | null {
    if (this.accountIndex < 0 || this.accountIndex >= this.accounts.length) {
      return null;
    }
    return this.accounts[this.accountIndex];
  }

  private limitUp(): number {
    return this.tradable === null ? 0 : this.tradable.limitUp;
  }

  private limitDown(): number {
    return this.tradable === null ? 0 : this.tradable.limitDown;
  }

  private recomputeCanBuy(): void {
    const account: AccountInfo | null = this.activeAccount();
    this.canBuy = account === null ? 0 : computeCanBuy(account.available, this.price);
    this.canBuyText = formatQty(this.canBuy);
    // M10：卖出上限 = 可卖数量向下取整到手（不按资金算）。
    this.canSell = account === null ? 0 : Math.floor(account.sellableQty / LOT_SIZE) * LOT_SIZE;
    this.canSellText = formatQty(this.canSell);
  }

  /** 当前方向下的数量上限（买 = 可买；卖 = 可卖）。 */
  private maxQty(): number {
    return this.side === 'sell' ? this.canSell : this.canBuy;
  }

  /** 切换买卖方向（M10）：重算上限与默认数量，价格保持不变。 */
  setSide(side: OrderSide): void {
    if (this.side === side || this.submitting) {
      return;
    }
    this.side = side;
    this.recomputeCanBuy();
    this.qty = defaultQty(this.maxQty());
    this.qtyText = formatQty(this.qty);
    this.qtyInput = this.qtyText;
    this.clearErrors();
    this.refreshBlock();
    hilog.info(DOMAIN, 'TradeLog', 'trade_side side=%{public}s can=%{public}d', side, this.maxQty());
  }

  /** 提示条优先级：断线 → 交易时段 → 资金（与门禁顺序一致，FR-07.10）。 */
  private track(event: string, params: AnalyticsParam[]): void {
    AnalyticsHost.get().track(event, params);
  }

  private refreshBlock(): void {
    if (this.netOffline || this.baseGate === TradeGate.Offline) {
      this.blockCode = 'offline';
      return;
    }
    if (this.baseGate === TradeGate.ClosedSession) {
      this.blockCode = 'closed';
      return;
    }
    if (this.side === 'sell') {
      if (this.canSell < LOT_SIZE) {
        this.blockCode = 'no_holding';
        return;
      }
      this.blockCode = '';
      return;
    }
    if (this.canBuy < LOT_SIZE) {
      this.blockCode = 'fund_short';
      return;
    }
    this.blockCode = '';
  }

  private applyFieldError(error: FieldError): void {
    const code: OrderErrorCode = error.code;
    let mapped: TradeFieldErrorCode = '';
    if (code === 'price_empty' || code === 'price_above' || code === 'price_below') {
      mapped = code;
    } else if (code === 'qty_empty' || code === 'qty_lot' || code === 'qty_over') {
      mapped = code;
    }
    if (error.field === 'price') {
      this.priceError = mapped;
    } else {
      this.qtyError = mapped;
    }
  }

  /** 连接状态实时同步（M5-1）：断线即提示条 + 按钮禁用，恢复后自动解除。 */
  applyNetState(offline: boolean): void {
    if (this.netOffline === offline) {
      return;
    }
    this.netOffline = offline;
    this.refreshBlock();
    hilog.info(DOMAIN, 'TradeLog', 'trade_net offline=%{public}s', offline ? 'true' : 'false');
  }

  private clearErrors(): void {
    this.priceError = '';
    this.qtyError = '';
  }

  private syncPrice(): void {
    this.priceText = formatPrice(this.price);
  }

  private syncQty(): void {
    this.qtyText = formatQty(this.qty);
  }

  private buildAccountLabels(): string[] {
    const labels: string[] = [];
    for (let i = 0; i < this.accounts.length; i++) {
      const account: AccountInfo = this.accounts[i];
      const canBuy: number = computeCanBuy(account.available, this.price);
      labels.push(account.maskNo + '  ' + formatQty(canBuy));
    }
    return labels;
  }

  private raiseToast(code: TradeToastCode): void {
    this.toastCode = code;
    this.toastSeq++;
  }

  private logValue(field: string): void {
    hilog.info(DOMAIN, 'TradeLog', 'trade_value_change field=%{public}s price=%{public}s qty=%{public}s',
      field, formatPrice(this.price), formatQty(this.qty));
  }

  private clearSubmitTimer(): void {
    if (this.submitTimer !== -1) {
      clearTimeout(this.submitTimer);
      this.submitTimer = -1;
    }
  }

  private clearCloseTimer(): void {
    if (this.closeTimer !== -1) {
      clearTimeout(this.closeTimer);
      this.closeTimer = -1;
    }
  }
}
