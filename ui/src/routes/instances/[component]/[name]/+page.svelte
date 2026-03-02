<script lang="ts">
  import { page } from '$app/stores';
  import { onMount } from 'svelte';
  import StatusBadge from '$lib/components/StatusBadge.svelte';
  import LogViewer from '$lib/components/LogViewer.svelte';
  import ConfigEditor from '$lib/components/ConfigEditor.svelte';
  import ChatPanel from '$lib/components/ChatPanel.svelte';
  import { api } from '$lib/api/client';

  let component = $derived($page.params.component);
  let name = $derived($page.params.name);
  let instance = $state<any>(null);
  let config = $state<any>(null);
  let uiModules = $state<Record<string, string>>({});
  let activeTab = $state('overview');
  let loading = $state(false);

  let modelName = $derived(extractModel(config));
  let webPort = $derived(extractWebPort(config));
  let providerStatus = $derived(extractProviderStatus(config));
  let chatModuleName = $derived(uiModules['nullclaw-chat-ui'] ? 'nullclaw-chat-ui' : '');
  let chatModuleVersion = $derived(uiModules['nullclaw-chat-ui'] || '');
  let chatReady = $derived(
    instance?.status === 'running' &&
    (instance?.launch_mode || 'gateway') === 'gateway' &&
    chatModuleName !== '' &&
    webPort != null &&
    providerStatus.configured
  );

  function extractModel(cfg: any): string | null {
    if (!cfg) return null;
    try {
      if (cfg.channels?.gateway?.model) return cfg.channels.gateway.model;
      if (cfg.model) return cfg.model;
      if (cfg.channels?.web?.model) return cfg.channels.web.model;
    } catch { /* ignore */ }
    return null;
  }

  function extractProviderStatus(cfg: any): { provider: string; model: string; configured: boolean } {
    const none = { provider: '', model: '', configured: false };
    if (!cfg) return none;
    try {
      const primary = cfg.agents?.defaults?.model?.primary || '';
      if (!primary) return none;
      const parts = primary.split('/');
      const provider = parts.length > 1 ? parts[0] : primary;
      const model = parts.length > 1 ? parts.slice(1).join('/') : primary;
      const providers = cfg.models?.providers || {};
      // Check if the specific provider has an api_key
      if (providers[provider]?.api_key) {
        return { provider, model, configured: true };
      }
      // Check if any provider has an api_key set
      for (const [name, prov] of Object.entries(providers)) {
        if ((prov as any)?.api_key) {
          return { provider: name, model, configured: true };
        }
      }
      return { provider, model, configured: false };
    } catch { return none; }
  }

  function extractWebPort(cfg: any): number | null {
    if (!cfg) return null;
    try {
      if (cfg.channels?.web?.accounts?.default?.port) return cfg.channels.web.accounts.default.port;
      if (cfg.channels?.web?.port) return cfg.channels.web.port;
      if (cfg.web_port) return cfg.web_port;
    } catch { /* ignore */ }
    return null;
  }

  function formatUptime(seconds: number | undefined): string {
    if (!seconds && seconds !== 0) return '-';
    if (seconds < 60) return `${seconds}s`;
    const m = Math.floor(seconds / 60);
    if (m < 60) return `${m}m ${seconds % 60}s`;
    const h = Math.floor(m / 60);
    if (h < 24) return `${h}h ${m % 60}m`;
    const d = Math.floor(h / 24);
    return `${d}d ${h % 24}h`;
  }

  async function refresh() {
    try {
      const status = await api.getStatus();
      const instances = status.instances || {};
      if (instances[component] && instances[component][name]) {
        instance = instances[component][name];
      }
    } catch (e) {
      console.error(e);
    }
    // Fetch config (best-effort)
    try {
      config = await api.getConfig(component, name);
    } catch { /* config may not exist yet */ }
    // Fetch installed UI modules (best-effort)
    try {
      const res = await api.getUiModules();
      uiModules = res.modules || {};
    } catch { /* ignore */ }
  }

  onMount(() => {
    refresh();
    const interval = setInterval(refresh, 3000);
    return () => clearInterval(interval);
  });

  async function start() {
    loading = true;
    instance = { ...instance, status: 'starting' };
    try {
      await api.startInstance(component, name);
      await refresh();
    } catch { instance = { ...instance, status: 'stopped' }; }
    finally { loading = false; }
  }
  async function stop() {
    loading = true;
    instance = { ...instance, status: 'stopping' };
    try {
      await api.stopInstance(component, name);
      await refresh();
    } catch { instance = { ...instance, status: 'running' }; }
    finally { loading = false; }
  }
  async function restart() {
    loading = true;
    instance = { ...instance, status: 'restarting' };
    try {
      await api.restartInstance(component, name);
      await refresh();
    } catch {}
    finally { loading = false; }
  }
  async function remove() {
    if (confirm('Are you sure you want to delete this instance?')) {
      loading = true;
      try {
        await api.deleteInstance(component, name);
        window.location.href = '/';
      } catch (e) {
        console.error(e);
      } finally {
        loading = false;
      }
    }
  }
  async function setMode(mode: string) {
    await api.patchInstance(component, name, { launch_mode: mode });
    await refresh();
  }
  async function toggleAutoStart() {
    await api.patchInstance(component, name, { auto_start: !instance?.auto_start });
    await refresh();
  }
</script>

<div class="instance-detail">
  <div class="detail-header">
    <div>
      <h1>{name}</h1>
      <span class="component-tag">{component}</span>
    </div>
    <div class="actions">
      <button class="btn" onclick={start} disabled={loading}>Start</button>
      <button class="btn" onclick={stop} disabled={loading}>Stop</button>
      <button class="btn" onclick={restart} disabled={loading}>Restart</button>
      <button class="btn danger" onclick={remove} disabled={loading}>Delete</button>
    </div>
  </div>

  <div class="tabs">
    <button class:active={activeTab === 'overview'} onclick={() => activeTab = 'overview'}>Overview</button>
    <button class:active={activeTab === 'config'} onclick={() => activeTab = 'config'}>Config</button>
    <button class:active={activeTab === 'logs'} onclick={() => activeTab = 'logs'}>Logs</button>
    {#if (instance?.launch_mode || 'gateway') === 'gateway' && instance?.status === 'running' && chatModuleName}
      <button
        class:active={activeTab === 'chat'}
        class:disabled-tab={!chatReady}
        onclick={() => activeTab = 'chat'}
      >Chat{#if !providerStatus.configured}<span class="tab-warn">!</span>{/if}</button>
    {/if}
  </div>

  <div class="tab-content">
    {#if activeTab === 'overview'}
      <div class="overview-grid">
        <div class="info-card">
          <span class="label">Status</span>
          <StatusBadge status={instance?.status || 'stopped'} />
        </div>
        <div class="info-card">
          <span class="label">Version</span>
          <span>{instance?.version || '-'}</span>
        </div>
        <div class="info-card">
          <span class="label">Launch Mode</span>
          <div class="mode-selector">
            <button
              class="mode-btn"
              class:active={(instance?.launch_mode || 'gateway') === 'gateway'}
              onclick={() => setMode('gateway')}
            >Gateway</button>
            <button
              class="mode-btn"
              class:active={instance?.launch_mode === 'agent'}
              onclick={() => setMode('agent')}
            >Agent</button>
          </div>
        </div>
        <div class="info-card">
          <span class="label">Auto Start</span>
          <button
            class="toggle-btn"
            class:on={instance?.auto_start}
            onclick={toggleAutoStart}
          >
            <span class="toggle-track"><span class="toggle-thumb"></span></span>
            {instance?.auto_start ? 'On' : 'Off'}
          </button>
        </div>
        {#if instance?.pid}
          <div class="info-card">
            <span class="label">PID</span>
            <span class="mono">{instance.pid}</span>
          </div>
        {/if}
        {#if instance?.status === 'running' && instance?.uptime_seconds != null}
          <div class="info-card">
            <span class="label">Uptime</span>
            <span>{formatUptime(instance.uptime_seconds)}</span>
          </div>
        {/if}
        {#if instance?.port}
          <div class="info-card">
            <span class="label">Port</span>
            <span class="mono">{instance.port}</span>
          </div>
        {/if}
        {#if instance?.restart_count}
          <div class="info-card">
            <span class="label">Restart Count</span>
            <span>{instance.restart_count}</span>
          </div>
        {/if}
        {#if providerStatus.provider}
          <div class="info-card" class:card-warn={!providerStatus.configured}>
            <span class="label">Provider</span>
            <div class="provider-status">
              <span class="status-dot" class:ok={providerStatus.configured} class:err={!providerStatus.configured}></span>
              <span>{providerStatus.provider}</span>
            </div>
            {#if !providerStatus.configured}
              <span class="provider-hint">No API key</span>
            {/if}
          </div>
        {/if}
        {#if providerStatus.model}
          <div class="info-card">
            <span class="label">Model</span>
            <span>{providerStatus.model}</span>
          </div>
        {/if}
        {#if webPort}
          <div class="info-card">
            <span class="label">Web Channel Port</span>
            <span class="mono">{webPort}</span>
          </div>
        {/if}
      </div>
    {:else if activeTab === 'config'}
      <ConfigEditor {component} {name} />
    {:else if activeTab === 'logs'}
      <LogViewer {component} {name} />
    {:else if activeTab === 'chat'}
      {#if !providerStatus.configured}
        <div class="chat-blocked">
          <div class="chat-blocked-icon">!</div>
          <div class="chat-blocked-title">LLM Provider Not Configured</div>
          <div class="chat-blocked-desc">
            No API key found for provider <code>{providerStatus.provider || 'unknown'}</code>.
            Set up a provider API key in the <button class="link-btn" onclick={() => activeTab = 'config'}>Config</button> tab to use chat.
          </div>
          {#if providerStatus.model}
            <div class="chat-blocked-model">Model: <code>{providerStatus.provider}/{providerStatus.model}</code></div>
          {/if}
        </div>
      {:else if !webPort}
        <div class="chat-unavailable">Web channel not configured for this instance.</div>
      {:else}
        <ChatPanel port={webPort} moduleName={chatModuleName} moduleVersion={chatModuleVersion} />
      {/if}
    {/if}
  </div>
</div>

<style>
  .instance-detail {
    padding: 2rem;
    max-width: 1200px;
    margin: 0 auto;
  }
  .detail-header {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    margin-bottom: 1.5rem;
  }
  .detail-header h1 {
    font-size: 1.75rem;
    font-weight: 600;
    margin-bottom: 0.375rem;
  }
  .component-tag {
    padding: 0.125rem 0.5rem;
    background: var(--bg-tertiary);
    border-radius: var(--radius-sm);
    font-family: var(--font-mono);
    font-size: 0.75rem;
    color: var(--text-secondary);
  }
  .actions {
    display: flex;
    gap: 0.5rem;
  }
  .btn {
    padding: 0.375rem 0.75rem;
    border: 1px solid var(--border);
    border-radius: var(--radius-sm);
    background: var(--bg-tertiary);
    color: var(--text-primary);
    font-size: 0.8125rem;
    cursor: pointer;
    transition: background 0.15s, border-color 0.15s;
  }
  .btn:hover {
    background: var(--bg-hover);
    border-color: var(--accent);
  }
  .btn.danger {
    color: var(--error);
    border-color: color-mix(in srgb, var(--error) 30%, transparent);
  }
  .btn.danger:hover {
    background: color-mix(in srgb, var(--error) 15%, transparent);
    border-color: var(--error);
  }
  .tabs {
    display: flex;
    gap: 0;
    border-bottom: 1px solid var(--border);
    margin-bottom: 1.5rem;
  }
  .tabs button {
    padding: 0.625rem 1.25rem;
    background: none;
    border: none;
    border-bottom: 2px solid transparent;
    color: var(--text-secondary);
    font-size: 0.875rem;
    cursor: pointer;
    transition: color 0.15s, border-color 0.15s;
  }
  .tabs button:hover {
    color: var(--text-primary);
  }
  .tabs button.active {
    color: var(--accent);
    border-bottom-color: var(--accent);
  }
  .tab-content {
    min-height: 400px;
  }
  .overview-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(200px, 1fr));
    gap: 1rem;
  }
  .info-card {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
    padding: 1.25rem;
    background: var(--bg-secondary);
    border: 1px solid var(--border);
    border-radius: var(--radius);
  }
  .label {
    font-size: 0.75rem;
    color: var(--text-muted);
    text-transform: uppercase;
    letter-spacing: 0.05em;
    font-weight: 500;
  }
  .mode-selector {
    display: flex;
    gap: 0.25rem;
  }
  .mode-btn {
    padding: 0.25rem 0.625rem;
    border: 1px solid var(--border);
    border-radius: var(--radius-sm);
    background: var(--bg-tertiary);
    color: var(--text-secondary);
    font-size: 0.8125rem;
    cursor: pointer;
    transition: background 0.15s, border-color 0.15s, color 0.15s;
  }
  .mode-btn:hover {
    background: var(--bg-hover);
    border-color: var(--accent);
  }
  .mode-btn.active {
    background: color-mix(in srgb, var(--accent) 15%, transparent);
    border-color: var(--accent);
    color: var(--accent);
  }
  .toggle-btn {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    background: none;
    border: none;
    color: var(--text-secondary);
    font-size: 0.875rem;
    cursor: pointer;
    padding: 0;
  }
  .toggle-track {
    position: relative;
    width: 32px;
    height: 18px;
    background: var(--bg-tertiary);
    border: 1px solid var(--border);
    border-radius: 9px;
    transition: background 0.2s, border-color 0.2s;
  }
  .toggle-thumb {
    position: absolute;
    top: 2px;
    left: 2px;
    width: 12px;
    height: 12px;
    background: var(--text-muted);
    border-radius: 50%;
    transition: transform 0.2s, background 0.2s;
  }
  .toggle-btn.on .toggle-track {
    background: color-mix(in srgb, var(--accent) 20%, transparent);
    border-color: var(--accent);
  }
  .toggle-btn.on .toggle-thumb {
    transform: translateX(14px);
    background: var(--accent);
  }
  .mono {
    font-family: var(--font-mono);
  }
  .chat-unavailable {
    color: var(--text-muted);
    text-align: center;
    padding: 3rem;
    font-size: 0.875rem;
  }
  .tab-warn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 14px;
    height: 14px;
    border-radius: 50%;
    background: color-mix(in srgb, var(--warning, #f59e0b) 20%, transparent);
    color: var(--warning, #f59e0b);
    font-size: 0.625rem;
    font-weight: 700;
    margin-left: 0.375rem;
    vertical-align: middle;
  }
  .disabled-tab {
    opacity: 0.7;
  }
  .chat-blocked {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    padding: 3rem 2rem;
    gap: 0.75rem;
    text-align: center;
  }
  .chat-blocked-icon {
    width: 48px;
    height: 48px;
    border-radius: 50%;
    background: color-mix(in srgb, var(--warning, #f59e0b) 15%, transparent);
    color: var(--warning, #f59e0b);
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 1.5rem;
    font-weight: 700;
  }
  .chat-blocked-title {
    font-size: 1.125rem;
    font-weight: 600;
    color: var(--text-primary);
  }
  .chat-blocked-desc {
    color: var(--text-secondary);
    font-size: 0.875rem;
    max-width: 400px;
    line-height: 1.5;
  }
  .chat-blocked-desc code {
    padding: 0.125rem 0.375rem;
    background: var(--bg-tertiary);
    border-radius: var(--radius-sm);
    font-family: var(--font-mono);
    font-size: 0.8125rem;
  }
  .chat-blocked-model {
    color: var(--text-muted);
    font-size: 0.8125rem;
  }
  .chat-blocked-model code {
    padding: 0.125rem 0.375rem;
    background: var(--bg-tertiary);
    border-radius: var(--radius-sm);
    font-family: var(--font-mono);
    font-size: 0.75rem;
  }
  .link-btn {
    background: none;
    border: none;
    color: var(--accent);
    cursor: pointer;
    font-size: inherit;
    text-decoration: underline;
    padding: 0;
  }
  .link-btn:hover {
    opacity: 0.8;
  }
  .card-warn {
    border-color: color-mix(in srgb, var(--warning, #f59e0b) 40%, transparent);
  }
  .provider-status {
    display: flex;
    align-items: center;
    gap: 0.375rem;
  }
  .status-dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
  }
  .status-dot.ok {
    background: var(--success, #22c55e);
  }
  .status-dot.err {
    background: var(--warning, #f59e0b);
  }
  .provider-hint {
    font-size: 0.75rem;
    color: var(--warning, #f59e0b);
  }
</style>
