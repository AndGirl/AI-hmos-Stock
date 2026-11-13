/**
 * 占位文案常量表（唯一来源，DEC-10-02 / ADR-08）。
 * 每条都是完整的 i18n 字符串，页面与 toast 只引用，禁止硬编码或运行时拼接。
 * 单测校验：均以「下阶段开放」结尾；不含「敬请期待 / 即将上线 / 暂未开放 / Coming / ~ / ! / ！」；
 * 不含版本号片段（v1.x / 一期 / 二期）。
 */
export class ComingSoonText {
  static readonly HOME: ResourceStr = $r('app.string.coming_soon_home');
  static readonly NEWS: ResourceStr = $r('app.string.coming_soon_news');
}
