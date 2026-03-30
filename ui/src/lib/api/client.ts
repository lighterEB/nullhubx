import { createOrchestrationApi } from '$lib/api/orchestration';
import { formatTimeoutError, getNetworkFailedMessage } from './errorMessages';
import { toast } from '$lib/toastStore.svelte';

const BASE = '/api';
const REQUEST_TIMEOUT_MS = 30000;
const STATUS_TIMEOUT_MS = 8000;

type RequestOptions = RequestInit & {
  timeoutMs?: number;
  errorMode?: 'silent' | 'toast';
};

function maybeToast(message: string, errorMode: RequestOptions['errorMode']) {
  if (errorMode === 'toast') {
    toast.error(message);
  }
}

function withQuery(path: string, params: Record<string, string | number | boolean | null | undefined>): string {
  const search = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (value === null || value === undefined || value === '') continue;
    search.set(key, String(value));
  }
  const query = search.toString();
  return query ? `${path}?${query}` : path;
}

export { encodePathSegment } from '$lib/orchestration/routes';

export type LogSource = 'instance' | 'nullhubx';
export type JsonPrimitive = string | number | boolean | null;
export type JsonValue = JsonPrimitive | JsonObject | JsonValue[];
export type JsonObject = { [key: string]: JsonValue | undefined };

export type ComponentSummary = JsonObject & {
  name: string;
  display_name?: string;
  description?: string;
  alpha?: boolean;
  installed?: boolean;
  standalone?: boolean;
  instance_count?: number;
};

export type ComponentsResponse = JsonObject & {
  components?: ComponentSummary[];
};

export type SavedProvider = JsonObject & {
  id?: string;
  name?: string;
  provider?: string;
  api_key?: string;
  model?: string;
  last_validation_ok?: boolean;
  last_validation_at?: string;
};

export type SavedProvidersResponse = JsonObject & {
  providers?: SavedProvider[];
};

export type SavedChannel = JsonObject & {
  id?: string;
  name?: string;
  channel_type?: string;
  account?: string;
  validated_at?: string;
  config?: JsonObject;
};

export type SavedChannelsResponse = JsonObject & {
  channels?: SavedChannel[];
};

export type WizardOptionPayload = JsonObject & {
  value: string;
  label?: string;
  recommended?: boolean;
};

export type WizardStepPayload = JsonObject & {
  id: string;
  title?: string;
  description?: string;
  type?: string;
  options?: WizardOptionPayload[];
  default_value?: string;
  advanced?: boolean;
  group?: string;
};

export type WizardPayload = JsonObject & {
  error?: string;
  steps?: WizardStepPayload[];
  wizard?: (JsonObject & {
    steps?: WizardStepPayload[];
  });
};

type InstanceStartOptions = {
  launch_mode?: string;
  verbose?: boolean;
};

export interface InstanceInfo {
  component: string;
  name: string;
  status: 'stopped' | 'starting' | 'running' | 'failed' | 'restarting' | 'stopping';
  pid?: number | null;
  port?: number;
  version?: string;
  auto_start?: boolean;
  launch_mode?: string;
  uptime_seconds?: number | null;
  restart_count?: number;
  health_consecutive_failures?: number;
}

export type InstancesPayload = Record<string, Record<string, InstanceInfo>>;
export type InstancesResponse = JsonObject & {
  instances?: InstancesPayload;
};

export interface GlobalStatus {
  uptime_seconds?: number;
  instances?: InstancesPayload;
  version?: string;
}

export type VersionOptionPayload = JsonObject & {
  value: string;
  label?: string;
  recommended?: boolean;
};

export type WizardSubmitResponse = JsonObject & {
  message?: string;
  status?: string;
};

export type AgentProfileDefaultsPayload = JsonObject & {
  model_primary?: string;
};

export type AgentFieldPolicyPayload = JsonObject & {
  standard_fields?: string[];
  defaults_fields?: string[];
  unknown_fields?: string;
  write_mode?: string;
};

export type AgentMutationResponse = JsonObject & {
  contract_version?: number;
  ownership?: string;
  resource?: string;
  status?: string;
  apply_state?: string;
  runtime_effect?: string;
  unknown_fields?: string;
  profiles_count?: number;
  bindings_count?: number;
};

export type AgentProfilePayload = JsonObject & {
  id?: string;
  provider?: string;
  model?: string;
  system_prompt?: string;
  temperature?: number | null;
  max_depth?: number | null;
};

export type AgentProfilesResponse = JsonObject & {
  contract_version?: number;
  ownership?: string;
  resource?: string;
  field_policy?: AgentFieldPolicyPayload;
  defaults?: AgentProfileDefaultsPayload;
  profiles?: AgentProfilePayload[];
};

export type AgentBindingPeerPayload = JsonObject & {
  kind?: string;
  id?: string;
};

export type AgentBindingMatchPayload = JsonObject & {
  channel?: string;
  account_id?: string;
  peer?: AgentBindingPeerPayload;
};

export type AgentBindingPayload = JsonObject & {
  agent_id?: string;
  match?: AgentBindingMatchPayload;
};

export type AgentBindingsResponse = JsonObject & {
  contract_version?: number;
  ownership?: string;
  resource?: string;
  field_policy?: AgentFieldPolicyPayload;
  bindings?: AgentBindingPayload[];
};

export type HistorySessionPayload = JsonObject & {
  session_id?: string;
  message_count?: number;
  first_message_at?: string;
  last_message_at?: string;
};

export type HistoryMessagePayload = JsonObject & {
  role?: string;
  content?: string;
  created_at?: string;
};

export type HistoryResponse = JsonObject & {
  sessions?: HistorySessionPayload[];
  messages?: HistoryMessagePayload[];
  total?: number;
  offset?: number;
};

export type LogsResponse = JsonObject & {
  lines?: string[];
};

export type ServiceStatusResponse = JsonObject & {
  status?: string;
  message?: string;
  registered?: boolean;
  running?: boolean;
  service_type?: string;
  unit_path?: string;
};

export type ValidationResultPayload = JsonObject & {
  provider?: string;
  channel?: string;
  account?: string;
  account_id?: string;
  live_ok?: boolean;
  saved_ok?: boolean;
  reason?: string;
  error?: string;
};

export type ProvidersValidationResponse = JsonObject & {
  results?: ValidationResultPayload[];
  saved_providers_warning?: string;
};

export type ChannelsValidationResponse = JsonObject & {
  results?: ValidationResultPayload[];
  saved_channels_warning?: string;
};

export type AnyRecord = JsonObject;

async function request<T>(path: string, options?: RequestOptions): Promise<T> {
  const timeoutMs = options?.timeoutMs ?? REQUEST_TIMEOUT_MS;
  const errorMode = options?.errorMode ?? 'silent';
  const { timeoutMs: _timeoutMs, errorMode: _errorMode, ...fetchOptions } = options ?? {};
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), timeoutMs);
  let res: Response;

  try {
    try {
      res = await fetch(`${BASE}${path}`, {
        headers: { 'Content-Type': 'application/json' },
        signal: controller.signal,
        ...fetchOptions
      });
    } catch (err) {
      if (err instanceof Error && err.name === 'AbortError') {
        const msg = formatTimeoutError(timeoutMs, path);
        maybeToast(msg, errorMode);
        throw new Error(msg);
      }
      const msg = getNetworkFailedMessage();
      maybeToast(msg, errorMode);
      throw new Error(msg);
    }

    if (!res.ok) {
      const body = await res.json().catch(() => null);
      const errMsg =
        typeof body?.message === 'string'
          ? body.message
          : typeof body?.error === 'string'
            ? body.error
            : body?.error?.message || `HTTP ${res.status}`;
      // Let the caller handle UI logic, but dispatch a toast alert by default.
      if (res.status !== 404 && res.status !== 401) {
        maybeToast(errMsg, errorMode);
      }
      throw new Error(errMsg);
    }
    if (res.status === 204) return undefined as T;
    const text = await res.text();
    if (!text) return undefined as T;
    return JSON.parse(text);
  } finally {
    clearTimeout(timeout);
  }
}

export const api = {
  getStatus: () => request<GlobalStatus>('/status', { timeoutMs: STATUS_TIMEOUT_MS }),
  getGlobalUsage: (window: '24h' | '7d' | '30d' | 'all' = '24h') =>
    request<AnyRecord>(`/usage?window=${window}`),
  getComponents: () => request<ComponentsResponse>('/components'),
  getInstances: () => request<InstancesResponse>('/instances'),
  getInstance: (c: string, n: string) => request<AnyRecord>(`/instances/${c}/${n}`),
  getWizard: (component: string) => request<WizardPayload>(`/wizard/${component}`),
  getVersions: (component: string) => request<VersionOptionPayload[]>(`/wizard/${component}/versions`),
  getWizardModels: (component: string, provider: string, apiKey = '') =>
    request<AnyRecord>(`/wizard/${component}/models`, {
      method: 'POST',
      body: JSON.stringify({ provider, api_key: apiKey }),
    }),
  getFreePort: () => request<AnyRecord>('/free-port'),
  postWizard: (component: string, data: JsonObject) =>
    request<WizardSubmitResponse>(`/wizard/${component}`, { method: 'POST', body: JSON.stringify(data) }),
  startInstance: (c: string, n: string, modeOrOptions?: string | InstanceStartOptions) =>
    request<AnyRecord>(`/instances/${c}/${n}/start`, {
      method: 'POST',
      body:
        typeof modeOrOptions === 'string'
          ? JSON.stringify({ launch_mode: modeOrOptions })
          : modeOrOptions
            ? JSON.stringify(modeOrOptions)
            : undefined
    }),
  stopInstance: (c: string, n: string) =>
    request<AnyRecord>(`/instances/${c}/${n}/stop`, { method: 'POST' }),
  restartInstance: (c: string, n: string, options?: InstanceStartOptions) =>
    request<AnyRecord>(`/instances/${c}/${n}/restart`, {
      method: 'POST',
      body: options ? JSON.stringify(options) : undefined
    }),
  deleteInstance: (c: string, n: string) =>
    request<AnyRecord>(`/instances/${c}/${n}`, { method: 'DELETE' }),
  getConfig: (c: string, n: string) => request<AnyRecord>(`/instances/${c}/${n}/config`),
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
  putConfig: (c: string, n: string, config: JsonObject) =>
    request<AnyRecord>(`/instances/${c}/${n}/config`, { method: 'PUT', body: JSON.stringify(config) }),
  getLogs: (c: string, n: string, lines = 100, source: LogSource = 'instance') =>
    request<LogsResponse>(withQuery(`/instances/${c}/${n}/logs`, { lines, source })),
  clearLogs: (c: string, n: string, source: LogSource = 'instance') =>
    request<AnyRecord>(withQuery(`/instances/${c}/${n}/logs`, { source }), { method: 'DELETE' }),
  getUpdates: () => request<AnyRecord>('/updates'),
  getSettings: () => request<AnyRecord>('/settings'),
  putSettings: (settings: JsonObject) =>
    request<AnyRecord>('/settings', { method: 'PUT', body: JSON.stringify(settings) }),

  patchConfig: (c: string, n: string, config: JsonObject) =>
    request<AnyRecord>(`/instances/${c}/${n}/config`, { method: 'PATCH', body: JSON.stringify(config) }),

  patchInstance: (c: string, n: string, settings: JsonObject) =>
    request<AnyRecord>(`/instances/${c}/${n}`, { method: 'PATCH', body: JSON.stringify(settings) }),

  getComponentManifest: (name: string) => request<AnyRecord>(`/components/${name}/manifest`),

  refreshComponents: () => request<AnyRecord>('/components/refresh', { method: 'POST' }),

  applyUpdate: (c: string, n: string) =>
    request<AnyRecord>(`/instances/${c}/${n}/update`, { method: 'POST' }),

  serviceInstall: () => request<ServiceStatusResponse>('/service/install', { method: 'POST' }),

  serviceUninstall: () => request<ServiceStatusResponse>('/service/uninstall', { method: 'POST' }),

  serviceStatus: () => request<ServiceStatusResponse>('/service/status'),

  importInstance: (component: string) =>
    request<AnyRecord>(`/instances/${component}/import`, { method: 'POST' }),

  getUiModules: () => request<{ modules: Record<string, string> }>('/ui-modules'),
  getAvailableUiModules: () => request<{ name: string; repo: string; component: string }[]>('/ui-modules/available'),
  installUiModule: (name: string) => request<AnyRecord>(`/ui-modules/${name}/install`, { method: 'POST' }),
  uninstallUiModule: (name: string) => request<AnyRecord>(`/ui-modules/${name}`, { method: 'DELETE' }),

  validateProviders: (component: string, providers: JsonObject[]) =>
    request<ProvidersValidationResponse>(`/wizard/${component}/validate-providers`, {
      method: 'POST',
      body: JSON.stringify({ providers }),
    }),

  validateChannels: (component: string, channels: Record<string, JsonObject>) =>
    request<ChannelsValidationResponse>(`/wizard/${component}/validate-channels`, {
      method: 'POST',
      body: JSON.stringify({ channels }),
    }),

  // Saved providers
  getSavedProviders: (reveal = false) =>
    request<SavedProvidersResponse>(`/providers${reveal ? '?reveal=true' : ''}`),
  createSavedProvider: (data: { provider: string; api_key: string; model?: string }) =>
    request<AnyRecord>('/providers', { method: 'POST', body: JSON.stringify(data) }),
  updateSavedProvider: (id: string, data: { name?: string; api_key?: string; model?: string }) =>
    request<AnyRecord>(`/providers/${id.replace('sp_', '')}`, { method: 'PUT', body: JSON.stringify(data) }),
  deleteSavedProvider: (id: string) =>
    request<AnyRecord>(`/providers/${id.replace('sp_', '')}`, { method: 'DELETE' }),
  revalidateSavedProvider: (id: string) =>
    request<AnyRecord>(`/providers/${id.replace('sp_', '')}/validate`, { method: 'POST' }),

  // Saved channels
  getSavedChannels: (reveal = false) =>
    request<SavedChannelsResponse>(`/channels${reveal ? '?reveal=true' : ''}`),
  createSavedChannel: (data: { channel_type: string; account: string; config: JsonObject }) =>
    request<AnyRecord>('/channels', { method: 'POST', body: JSON.stringify(data) }),
  updateSavedChannel: (id: string, data: { name?: string; account?: string; config?: JsonObject }) =>
    request<AnyRecord>(`/channels/${id.replace('sc_', '')}`, { method: 'PUT', body: JSON.stringify(data) }),
  deleteSavedChannel: (id: string) =>
    request<AnyRecord>(`/channels/${id.replace('sc_', '')}`, { method: 'DELETE' }),
  revalidateSavedChannel: (id: string) =>
    request<AnyRecord>(`/channels/${id.replace('sc_', '')}/validate`, { method: 'POST' }),
  ...createOrchestrationApi(request, withQuery),
};
