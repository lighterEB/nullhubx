import { createOrchestrationApi } from '$lib/api/orchestration';
import { createInstancesApi } from './instances';
import { createSettingsApi } from './settings';
import { createStatusApi } from './status';
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

function withQuery(
  path: string,
  params: Record<string, string | number | boolean | null | undefined>,
): string {
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
  validated_at?: string;
  validated_with?: string;
  last_validation_at?: string;
  last_validation_ok?: boolean;
  linked_instance_count?: number;
  orphaned?: boolean;
  linked_instances?: LinkedInstanceRef[];
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
  validated_with?: string;
  config?: JsonObject;
  linked_instance_count?: number;
  orphaned?: boolean;
  linked_instances?: LinkedInstanceRef[];
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
  wizard?: JsonObject & {
    steps?: WizardStepPayload[];
  };
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

export type LinkedInstanceRef = JsonObject & {
  component?: string;
  name?: string;
  route?: string;
};

export type CapabilitySurfaceSummaryState = 'implemented' | 'partial' | 'missing' | 'cli_only';
export type CapabilitySurfaceRuntimeState = 'unknown' | 'supported' | 'not_applicable' | 'planned';
export type CapabilitySurfaceUiState =
  | 'global'
  | 'instance'
  | 'global_read_only'
  | 'placeholder'
  | 'missing';

export type CapabilitySurface = JsonObject & {
  id?: string;
  category?: string;
  label?: string;
  summary_state?: CapabilitySurfaceSummaryState;
  hub_bridge_support?: boolean;
  runtime_detected_support?: CapabilitySurfaceRuntimeState;
  ui_productization_state?: CapabilitySurfaceUiState;
  route_ids?: string[];
  ui_routes?: string[];
  notes?: string;
};

export type CapabilitiesResponse = JsonObject & {
  version?: number;
  capabilities?: AnyRecord;
  capability_model?: JsonObject & {
    version?: number;
    dimensions?: string[];
    summary_states?: string[];
    runtime_detected_states?: string[];
    ui_productization_states?: string[];
  };
  surfaces?: CapabilitySurface[];
  notes?: JsonObject;
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
        ...fetchOptions,
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
  ...createStatusApi(request, STATUS_TIMEOUT_MS),
  getComponents: () => request<ComponentsResponse>('/components'),
  getWizard: (component: string) => request<WizardPayload>(`/wizard/${component}`),
  getVersions: (component: string) =>
    request<VersionOptionPayload[]>(`/wizard/${component}/versions`),
  getWizardModels: (component: string, provider: string, apiKey = '') =>
    request<AnyRecord>(`/wizard/${component}/models`, {
      method: 'POST',
      body: JSON.stringify({ provider, api_key: apiKey }),
    }),
  getFreePort: () => request<AnyRecord>('/free-port'),
  postWizard: (component: string, data: JsonObject) =>
    request<WizardSubmitResponse>(`/wizard/${component}`, {
      method: 'POST',
      body: JSON.stringify(data),
    }),
  ...createInstancesApi(request, withQuery),
  getUpdates: () => request<AnyRecord>('/updates'),
  ...createSettingsApi(request),

  getComponentManifest: (name: string) => request<AnyRecord>(`/components/${name}/manifest`),

  refreshComponents: () => request<AnyRecord>('/components/refresh', { method: 'POST' }),

  getUiModules: () => request<{ modules: Record<string, string> }>('/ui-modules'),
  getAvailableUiModules: () =>
    request<{ name: string; repo: string; component: string }[]>('/ui-modules/available'),
  installUiModule: (name: string) =>
    request<AnyRecord>(`/ui-modules/${name}/install`, { method: 'POST' }),
  uninstallUiModule: (name: string) =>
    request<AnyRecord>(`/ui-modules/${name}`, { method: 'DELETE' }),

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
    request<AnyRecord>(`/providers/${id.replace('sp_', '')}`, {
      method: 'PUT',
      body: JSON.stringify(data),
    }),
  deleteSavedProvider: (id: string) =>
    request<AnyRecord>(`/providers/${id.replace('sp_', '')}`, { method: 'DELETE' }),
  revalidateSavedProvider: (id: string) =>
    request<AnyRecord>(`/providers/${id.replace('sp_', '')}/validate`, { method: 'POST' }),

  // Saved channels
  getSavedChannels: (reveal = false) =>
    request<SavedChannelsResponse>(`/channels${reveal ? '?reveal=true' : ''}`),
  createSavedChannel: (data: { channel_type: string; account: string; config: JsonObject }) =>
    request<AnyRecord>('/channels', { method: 'POST', body: JSON.stringify(data) }),
  updateSavedChannel: (
    id: string,
    data: { name?: string; account?: string; config?: JsonObject },
  ) =>
    request<AnyRecord>(`/channels/${id.replace('sc_', '')}`, {
      method: 'PUT',
      body: JSON.stringify(data),
    }),
  deleteSavedChannel: (id: string) =>
    request<AnyRecord>(`/channels/${id.replace('sc_', '')}`, { method: 'DELETE' }),
  revalidateSavedChannel: (id: string) =>
    request<AnyRecord>(`/channels/${id.replace('sc_', '')}/validate`, { method: 'POST' }),
  ...createOrchestrationApi(request, withQuery),
};
