import type { AnyRecord, CapabilitiesResponse, GlobalStatus } from './client';

type RequestFn = <T>(
  path: string,
  options?: RequestInit & { timeoutMs?: number; errorMode?: 'silent' | 'toast' },
) => Promise<T>;

export function createStatusApi(request: RequestFn, statusTimeoutMs: number) {
  return {
    getStatus: () => request<GlobalStatus>('/status', { timeoutMs: statusTimeoutMs }),
    getGlobalUsage: (window: '24h' | '7d' | '30d' | 'all' = '24h') =>
      request<AnyRecord>(`/usage?window=${window}`),
    getCapabilities: () => request<CapabilitiesResponse>('/meta/capabilities'),
  };
}
