import zhCN from './zh-CN';
import enUS from './en-US';

export type Locale = 'zh-CN' | 'en-US';
export type Dictionary = typeof zhCN;

const dictionaries: Record<Locale, Dictionary> = {
  'zh-CN': zhCN,
  'en-US': enUS
};

// 使用 Svelte 5 的 rune 让全局语言状态具备响应性
let currentLocale = $state<Locale>('zh-CN');

export const i18n = {
  get locale() {
    return currentLocale;
  },
  set locale(value: Locale) {
    currentLocale = value;
  },
  get dict() {
    return dictionaries[currentLocale];
  }
};

/**
 * 获取翻译文本，支持点分隔路径，例如 'nav.overview'
 */
export function t(key: string): string {
  const keys = key.split('.');
  // 读取 i18n.dict 会自动收集 Svelte 5 的依赖
  let current: any = i18n.dict;

  for (const k of keys) {
    if (current === undefined || current === null) break;
    current = current[k];
  }

  if (typeof current === 'string') {
    return current;
  }

  // 找不到翻译时回退到原始 key
  return key;
}