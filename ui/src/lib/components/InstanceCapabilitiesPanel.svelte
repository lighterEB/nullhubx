<script lang="ts">
  import { api } from '$lib/api/client';
  import { t } from '$lib/i18n/index.svelte';
  import { describeInstanceCliError, isInstanceCliError } from '$lib/instanceCli';

  type ChannelCapability = {
    key?: string;
    label?: string;
    enabled_in_build?: boolean;
    configured?: boolean;
    configured_count?: number;
  };

  type MemoryEngineCapability = {
    name?: string;
    enabled_in_build?: boolean;
    configured?: boolean;
  };

  type ToolCapability = {
    runtime_loaded?: string[];
    estimated_enabled_from_config?: string[];
    optional_enabled_by_config?: string[];
    optional_disabled_by_config?: string[];
  };

  type CapabilityPayload = {
    version?: string;
    active_memory_backend?: string;
    channels?: ChannelCapability[];
    memory_engines?: MemoryEngineCapability[];
    tools?: ToolCapability;
  };

  let {
    component,
    name,
    active = false,
  } = $props<{
    component: string;
    name: string;
    active?: boolean;
  }>();

  let payload = $state<CapabilityPayload | null>(null);
  let loading = $state(false);
  let error = $state<string | null>(null);
  let loadedKey = $state('');
  let requestSeq = 0;

  const instanceKey = $derived(`${component}/${name}`);
  const channelCapabilities = $derived(Array.isArray(payload?.channels) ? payload.channels : []);
  const memoryCapabilities = $derived(
    Array.isArray(payload?.memory_engines) ? payload.memory_engines : [],
  );
  const runtimeTools = $derived(
    Array.isArray(payload?.tools?.runtime_loaded) ? payload.tools.runtime_loaded : [],
  );
  const optionalEnabled = $derived(
    Array.isArray(payload?.tools?.optional_enabled_by_config)
      ? payload.tools.optional_enabled_by_config
      : [],
  );
  const optionalDisabled = $derived(
    Array.isArray(payload?.tools?.optional_disabled_by_config)
      ? payload.tools.optional_disabled_by_config
      : [],
  );

  async function loadCapabilities(force = false) {
    if (!active || !component || !name) return;
    const contextKey = instanceKey;
    const nextKey = `${contextKey}:capabilities`;
    if (!force && loadedKey === nextKey) return;

    const req = ++requestSeq;
    loading = true;
    error = null;
    try {
      const result = await api.getRuntimeCapabilities(component, name);
      if (req !== requestSeq || contextKey !== instanceKey || !active) return;
      if (isInstanceCliError(result)) {
        payload = null;
        error = describeInstanceCliError(result, t('capabilitiesPanel.unavailable'));
      } else {
        payload = (result || null) as CapabilityPayload | null;
        error = null;
      }
      loadedKey = nextKey;
    } catch (err) {
      if (req !== requestSeq || contextKey !== instanceKey || !active) return;
      payload = null;
      error = (err as Error).message || t('capabilitiesPanel.loadFailed');
    } finally {
      if (req === requestSeq && contextKey === instanceKey) {
        loading = false;
      }
    }
  }

  function refreshCapabilities() {
    loadedKey = '';
    void loadCapabilities(true);
  }

  function boolLabel(value: boolean | undefined): string {
    if (value === true) return t('common.enabled');
    if (value === false) return t('common.disabled');
    return '-';
  }

  $effect(() => {
    if (!active || !component || !name) return;
    if (loadedKey === `${instanceKey}:capabilities`) return;
    payload = null;
    error = null;
    void loadCapabilities(true);
  });
</script>

<div class="capabilities-panel">
  <div class="panel-toolbar">
    <div>
      <h2>{t('capabilitiesPanel.title')}</h2>
      <p>{t('capabilitiesPanel.subtitle')}</p>
    </div>
    <button class="toolbar-btn" onclick={refreshCapabilities} disabled={loading}>
      {t('capabilitiesPanel.refresh')}
    </button>
  </div>

  {#if error}
    <div class="panel-state warning">{error}</div>
  {:else if loading && !payload}
    <div class="panel-state">{t('capabilitiesPanel.loading')}</div>
  {:else if payload}
    <div class="stats-grid">
      <div class="stat-card">
        <span>{t('capabilitiesPanel.runtimeVersion')}</span>
        <strong>{payload.version || '-'}</strong>
      </div>
      <div class="stat-card">
        <span>{t('capabilitiesPanel.activeMemoryBackend')}</span>
        <strong>{payload.active_memory_backend || '-'}</strong>
      </div>
      <div class="stat-card">
        <span>{t('capabilitiesPanel.channelsCount')}</span>
        <strong>{channelCapabilities.length}</strong>
      </div>
      <div class="stat-card">
        <span>{t('capabilitiesPanel.runtimeTools')}</span>
        <strong>{runtimeTools.length}</strong>
      </div>
    </div>

    <section class="capability-section">
      <div class="section-head">
        <h3>{t('capabilitiesPanel.channelsTitle')}</h3>
      </div>
      {#if channelCapabilities.length === 0}
        <div class="panel-state">{t('common.noData')}</div>
      {:else}
        <div class="table-shell">
          <table class="data-table">
            <thead>
              <tr>
                <th>{t('capabilitiesPanel.channel')}</th>
                <th>{t('capabilitiesPanel.buildEnabled')}</th>
                <th>{t('capabilitiesPanel.configured')}</th>
                <th>{t('capabilitiesPanel.configuredCount')}</th>
              </tr>
            </thead>
            <tbody>
              {#each channelCapabilities as channel}
                <tr>
                  <td>{channel.label || channel.key || '-'}</td>
                  <td>{boolLabel(channel.enabled_in_build)}</td>
                  <td>{boolLabel(channel.configured)}</td>
                  <td>{channel.configured_count ?? 0}</td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      {/if}
    </section>

    <section class="capability-section">
      <div class="section-head">
        <h3>{t('capabilitiesPanel.memoryTitle')}</h3>
      </div>
      {#if memoryCapabilities.length === 0}
        <div class="panel-state">{t('common.noData')}</div>
      {:else}
        <div class="table-shell">
          <table class="data-table">
            <thead>
              <tr>
                <th>{t('capabilitiesPanel.memoryEngine')}</th>
                <th>{t('capabilitiesPanel.buildEnabled')}</th>
                <th>{t('capabilitiesPanel.configured')}</th>
              </tr>
            </thead>
            <tbody>
              {#each memoryCapabilities as engine}
                <tr>
                  <td>{engine.name || '-'}</td>
                  <td>{boolLabel(engine.enabled_in_build)}</td>
                  <td>{boolLabel(engine.configured)}</td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      {/if}
    </section>

    <section class="capability-section">
      <div class="section-head">
        <h3>{t('capabilitiesPanel.toolsTitle')}</h3>
      </div>
      <div class="tool-groups">
        <div class="tool-card">
          <span>{t('capabilitiesPanel.runtimeLoadedTools')}</span>
          <div class="chip-list">
            {#if runtimeTools.length > 0}
              {#each runtimeTools as tool}
                <span class="surface-chip">{tool}</span>
              {/each}
            {:else}
              <span class="surface-chip">-</span>
            {/if}
          </div>
        </div>
        <div class="tool-card">
          <span>{t('capabilitiesPanel.optionalEnabledTools')}</span>
          <div class="chip-list">
            {#if optionalEnabled.length > 0}
              {#each optionalEnabled as tool}
                <span class="surface-chip">{tool}</span>
              {/each}
            {:else}
              <span class="surface-chip">-</span>
            {/if}
          </div>
        </div>
        <div class="tool-card">
          <span>{t('capabilitiesPanel.optionalDisabledTools')}</span>
          <div class="chip-list">
            {#if optionalDisabled.length > 0}
              {#each optionalDisabled as tool}
                <span class="surface-chip">{tool}</span>
              {/each}
            {:else}
              <span class="surface-chip">-</span>
            {/if}
          </div>
        </div>
      </div>
    </section>
  {:else}
    <div class="panel-state">{t('common.noData')}</div>
  {/if}
</div>

<style>
  .capabilities-panel {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-lg);
  }

  .panel-toolbar,
  .section-head {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
    gap: var(--spacing-md);
  }

  .panel-toolbar h2,
  .section-head h3 {
    margin: 0;
  }

  .panel-toolbar p {
    margin: 4px 0 0;
    color: var(--slate-500);
    font-size: var(--text-sm);
    line-height: 1.6;
  }

  .toolbar-btn {
    min-height: 38px;
    padding: 0.55rem 0.9rem;
    border-radius: var(--radius-lg);
    border: 1px solid rgba(141, 154, 178, 0.18);
    background: rgba(255, 255, 255, 0.82);
    color: var(--slate-700);
  }

  .panel-state {
    padding: var(--spacing-lg);
    border-radius: var(--radius-lg);
    border: 1px solid rgba(141, 154, 178, 0.18);
    background: rgba(255, 255, 255, 0.72);
    color: var(--slate-600);
  }

  .panel-state.warning {
    border-color: rgba(245, 158, 11, 0.18);
    background: rgba(255, 251, 235, 0.82);
    color: var(--amber-700);
  }

  .stats-grid {
    display: grid;
    grid-template-columns: repeat(4, minmax(0, 1fr));
    gap: var(--spacing-md);
  }

  .stat-card,
  .tool-card {
    display: flex;
    flex-direction: column;
    gap: 6px;
    padding: var(--spacing-md);
    border-radius: var(--radius-lg);
    border: 1px solid rgba(141, 154, 178, 0.16);
    background: rgba(255, 255, 255, 0.68);
  }

  .stat-card span,
  .tool-card span {
    color: var(--slate-500);
    font-size: var(--text-xs);
    text-transform: uppercase;
    letter-spacing: 0.08em;
    font-weight: 600;
  }

  .stat-card strong {
    color: var(--slate-900);
    font-size: var(--text-lg);
  }

  .capability-section {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-md);
  }

  .tool-groups {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: var(--spacing-md);
  }

  .chip-list {
    display: flex;
    flex-wrap: wrap;
    gap: var(--spacing-sm);
  }

  @media (max-width: 900px) {
    .stats-grid,
    .tool-groups {
      grid-template-columns: 1fr;
    }
  }
</style>
