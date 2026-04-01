import type { AgentBindingsResponse, AgentMutationResponse, AgentProfilesResponse, AnyRecord, HistoryResponse, InstancesResponse, JsonObject, LogSource, LogsResponse } from './client';

type RequestFn = <T>(path: string, options?: RequestInit & { timeoutMs?: number; errorMode?: 'silent' | 'toast' }) => Promise<T>;
type WithQueryFn = (path: string, params: Record<string, string | number | boolean | null | undefined>) => string;

type InstanceStartOptions = {
  launch_mode?: string;
  verbose?: boolean;
};

export function createInstancesApi(request: RequestFn, withQuery: WithQueryFn) {
  return {
    getInstances: () => request<InstancesResponse>('/instances'),
    getInstance: (c: string, n: string) => request<AnyRecord>(`/instances/${c}/${n}`),
    startInstance: (c: string, n: string, modeOrOptions?: string | InstanceStartOptions) =>
      request<AnyRecord>(`/instances/${c}/${n}/start`, {
        method: 'POST',
        body:
          typeof modeOrOptions === 'string'
            ? JSON.stringify({ launch_mode: modeOrOptions })
            : modeOrOptions
              ? JSON.stringify(modeOrOptions)
              : undefined,
      }),
    stopInstance: (c: string, n: string) =>
      request<AnyRecord>(`/instances/${c}/${n}/stop`, { method: 'POST' }),
    restartInstance: (c: string, n: string, options?: InstanceStartOptions) =>
      request<AnyRecord>(`/instances/${c}/${n}/restart`, {
        method: 'POST',
        body: options ? JSON.stringify(options) : undefined,
      }),
    deleteInstance: (c: string, n: string) =>
      request<AnyRecord>(`/instances/${c}/${n}`, { method: 'DELETE' }),
    patchInstance: (c: string, n: string, settings: JsonObject) =>
      request<AnyRecord>(`/instances/${c}/${n}`, { method: 'PATCH', body: JSON.stringify(settings) }),
    getConfig: (c: string, n: string) => request<AnyRecord>(`/instances/${c}/${n}/config`),
    putConfig: (c: string, n: string, config: JsonObject) =>
      request<AnyRecord>(`/instances/${c}/${n}/config`, { method: 'PUT', body: JSON.stringify(config) }),
    patchConfig: (c: string, n: string, config: JsonObject) =>
      request<AnyRecord>(`/instances/${c}/${n}/config`, { method: 'PATCH', body: JSON.stringify(config) }),
    getAgentProfiles: (c: string, n: string) =>
      request<AgentProfilesResponse>(`/instances/${c}/${n}/agents/profiles`),
    putAgentProfiles: (c: string, n: string, payload: JsonObject) =>
      request<AgentMutationResponse>(`/instances/${c}/${n}/agents/profiles`, {
        method: 'PUT',
        body: JSON.stringify(payload),
      }),
    getAgentBindings: (c: string, n: string) =>
      request<AgentBindingsResponse>(`/instances/${c}/${n}/agents/bindings`),
    putAgentBindings: (c: string, n: string, payload: JsonObject) =>
      request<AgentMutationResponse>(`/instances/${c}/${n}/agents/bindings`, {
        method: 'PUT',
        body: JSON.stringify(payload),
      }),
    getProviderHealth: (c: string, n: string) =>
      request<AnyRecord>(`/instances/${c}/${n}/provider-health`),
    getUsage: (c: string, n: string, window: '24h' | '7d' | '30d' | 'all' = '24h') =>
      request<AnyRecord>(`/instances/${c}/${n}/usage?window=${window}`),
    getHistory: (c: string, n: string, params?: { sessionId?: string; limit?: number; offset?: number }) =>
      request<HistoryResponse>(
        withQuery(`/instances/${c}/${n}/history`, {
          session_id: params?.sessionId,
          limit: params?.limit,
          offset: params?.offset,
        }),
      ),
    getOnboarding: (c: string, n: string) =>
      request<AnyRecord>(`/instances/${c}/${n}/onboarding`),
    getMemory: (
      c: string,
      n: string,
      params?: { stats?: boolean; key?: string; query?: string; category?: string; limit?: number },
    ) =>
      request<AnyRecord>(
        withQuery(`/instances/${c}/${n}/memory`, {
          stats: params?.stats ? 1 : undefined,
          key: params?.key,
          query: params?.query,
          category: params?.category,
          limit: params?.limit,
        }),
      ),
    getSkills: (c: string, n: string, name?: string) =>
      request<AnyRecord>(withQuery(`/instances/${c}/${n}/skills`, { name })),
    getSkillCatalog: (c: string, n: string) =>
      request<AnyRecord>(withQuery(`/instances/${c}/${n}/skills`, { catalog: 1 })),
    installBundledSkill: (c: string, n: string, bundled: string) =>
      request<AnyRecord>(`/instances/${c}/${n}/skills`, {
        method: 'POST',
        body: JSON.stringify({ bundled }),
      }),
    installSkillFromClawhub: (c: string, n: string, clawhub_slug: string) =>
      request<AnyRecord>(`/instances/${c}/${n}/skills`, {
        method: 'POST',
        body: JSON.stringify({ clawhub_slug }),
      }),
    installSkillFromSource: (c: string, n: string, source: string) =>
      request<AnyRecord>(`/instances/${c}/${n}/skills`, {
        method: 'POST',
        body: JSON.stringify({ source }),
      }),
    removeSkill: (c: string, n: string, skillName: string) =>
      request<AnyRecord>(withQuery(`/instances/${c}/${n}/skills`, { name: skillName }), {
        method: 'DELETE',
      }),
    getIntegration: (c: string, n: string) =>
      request<AnyRecord>(`/instances/${c}/${n}/integration`),
    linkIntegration: (c: string, n: string, payload: JsonObject) =>
      request<AnyRecord>(`/instances/${c}/${n}/integration`, {
        method: 'POST',
        body: JSON.stringify(payload),
      }),
    getLogs: (c: string, n: string, lines = 100, source: LogSource = 'instance') =>
      request<LogsResponse>(withQuery(`/instances/${c}/${n}/logs`, { lines, source })),
    clearLogs: (c: string, n: string, source: LogSource = 'instance') =>
      request<AnyRecord>(withQuery(`/instances/${c}/${n}/logs`, { source }), { method: 'DELETE' }),
    applyUpdate: (c: string, n: string) =>
      request<AnyRecord>(`/instances/${c}/${n}/update`, { method: 'POST' }),
    importInstance: (component: string) =>
      request<AnyRecord>(`/instances/${component}/import`, { method: 'POST' }),
  };
}
