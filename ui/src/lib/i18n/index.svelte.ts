import zhCN from './zh-CN';
import enUS from './en-US';
import { setErrorLocale } from '$lib/api/errorMessages';

export type Locale = 'zh-CN' | 'en-US';
export type Dictionary = Record<string, unknown>;

const dictionaries: Record<Locale, Dictionary> = {
  'zh-CN': zhCN,
  'en-US': enUS
};

function detectInitialLocale(): Locale {
  if (typeof window === 'undefined') return 'zh-CN';
  const saved = window.localStorage.getItem('nullhubx-locale');
  return saved === 'en-US' || saved === 'zh-CN' ? saved : 'zh-CN';
}

function syncDocumentLocale(locale: Locale): void {
  if (typeof document === 'undefined') return;
  document.documentElement.lang = locale;
}

// 使用 Svelte 5 的 rune 让全局语言状态具备响应性
const initialLocale = detectInitialLocale();
let currentLocale = $state<Locale>(initialLocale);
setErrorLocale(initialLocale);
syncDocumentLocale(initialLocale);

export const i18n = {
  get locale() {
    return currentLocale;
  },
  set locale(value: Locale) {
    currentLocale = value;
    // 同步更新 API 错误消息语言
    setErrorLocale(value);
    syncDocumentLocale(value);
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
