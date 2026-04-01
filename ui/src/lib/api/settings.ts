import type { AnyRecord, JsonObject, ServiceStatusResponse } from './client';

type RequestFn = <T>(path: string, options?: RequestInit & { timeoutMs?: number; errorMode?: 'silent' | 'toast' }) => Promise<T>;

export function createSettingsApi(request: RequestFn) {
  return {
    getSettings: () => request<AnyRecord>('/settings'),
    putSettings: (settings: JsonObject) =>
      request<AnyRecord>('/settings', { method: 'PUT', body: JSON.stringify(settings) }),
    serviceInstall: () => request<ServiceStatusResponse>('/service/install', { method: 'POST' }),
    serviceUninstall: () => request<ServiceStatusResponse>('/service/uninstall', { method: 'POST' }),
    serviceStatus: () => request<ServiceStatusResponse>('/service/status'),
  };
}
