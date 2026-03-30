/**
 * API 错误消息格式化
 * 
 * 由于 API 客户端是底层库，不能直接依赖 i18n 模块（会形成循环依赖）
 * 使用简单的模板替换来支持多语言
 */

export type ErrorTemplate = {
  timeout: (seconds: number, path: string) => string;
  requestFailed: string;
  networkFailed: string;
};

// 默认使用英文模板（作为 fallback）
let currentTemplates: ErrorTemplate = {
  timeout: (seconds, path) => `Request timeout (${seconds}s): ${path}`,
  requestFailed: 'Request Failed',
  networkFailed: 'Network request failed',
};

// 中文模板
const zhTemplates: ErrorTemplate = {
  timeout: (seconds, path) => `请求超时（${seconds}s）：${path}`,
  requestFailed: '请求失败',
  networkFailed: '网络请求失败',
};

// 英文模板
const enTemplates: ErrorTemplate = {
  timeout: (seconds, path) => `Request timeout (${seconds}s): ${path}`,
  requestFailed: 'Request Failed',
  networkFailed: 'Network request failed',
};

/**
 * 设置错误消息语言
 * 在应用初始化时调用
 */
export function setErrorLocale(locale: 'zh-CN' | 'en-US'): void {
  currentTemplates = locale === 'zh-CN' ? zhTemplates : enTemplates;
}

/**
 * 格式化超时错误消息
 */
export function formatTimeoutError(timeoutMs: number, path: string): string {
  const seconds = Math.ceil(timeoutMs / 1000);
  return currentTemplates.timeout(seconds, path);
}

/**
 * 获取通用请求失败消息
 */
export function getRequestFailedMessage(): string {
  return currentTemplates.requestFailed;
}

/**
 * 获取网络请求失败消息
 */
export function getNetworkFailedMessage(): string {
  return currentTemplates.networkFailed;
}
