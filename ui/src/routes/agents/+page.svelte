<script lang="ts">
  import StatusBadge from '$lib/components/StatusBadge.svelte';
  import {
    api,
    type AgentBindingsResponse,
    type AgentProfilesResponse,
    type InstanceInfo,
  } from '$lib/api/client';
  import { instancesState, refreshStatus, statusError, statusReady } from '$lib/statusStore';
  import { t } from '$lib/i18n/index.svelte';

  type AgentRouteSummaryState =
    | 'configured'
    | 'default_only'
    | 'missing_profiles'
    | 'unavailable'
    | 'unknown';

  type FleetAgentSnapshot = {
    profilesCount: number | null;
    bindingsCount: number | null;
    defaultPrimary: string;
    profileIds: string[];
    channels: string[];
    summaryState: AgentRouteSummaryState;
    error: string;
  };

  type NullclawInstanceRow = {
    component: string;
    name: string;
    info: InstanceInfo;
  };

  let keyword = $state('');
  let loading = $state(false);
  let loadError = $state('');
  let loadedSignature = $state('');
  let requestSeq = 0;
  let fleetSnapshots = $state<Record<string, FleetAgentSnapshot>>({});

  const nullclawInstances = $derived.by(() => {
    const instances = $instancesState.nullclaw ?? {};
    return Object.entries(instances)
      .map(([name, info]) => ({
        component: 'nullclaw',
        name,
        info,
      }))
      .sort((a, b) => a.name.localeCompare(b.name));
  });

  const filteredRows = $derived.by(() => {
    const query = keyword.trim().toLowerCase();
    return nullclawInstances.filter((row) => {
      if (!query) return true;
      const snapshot = fleetSnapshots[`${row.component}/${row.name}`];
      const haystack = [
        `${row.component}/${row.name}`,
        row.info.version || '',
        snapshot?.defaultPrimary || '',
        ...(snapshot?.profileIds || []),
        ...(snapshot?.channels || []),
      ]
        .join(' ')
        .toLowerCase();
      return haystack.includes(query);
    });
  });

  const routeCounts = $derived.by(() => {
    const counts = {
      configured: 0,
      default_only: 0,
      missing_profiles: 0,
      unavailable: 0,
      unknown: 0,
    };
    for (const row of nullclawInstances) {
      const state = fleetSnapshots[`${row.component}/${row.name}`]?.summaryState || 'unknown';
      counts[state] += 1;
    }
    return counts;
  });

  function snapshotKey(row: NullclawInstanceRow): string {
    return `${row.component}/${row.name}`;
  }

  function buildSignature(rows: NullclawInstanceRow[]): string {
    return rows
      .map((row) => `${snapshotKey(row)}:${row.info.status}:${row.info.version || '-'}`)
      .join('|');
  }

  function parseProfiles(response: AgentProfilesResponse): {
    count: number;
    ids: string[];
    defaultPrimary: string;
  } {
    const profiles = Array.isArray(response?.profiles) ? response.profiles : [];
    const ids = profiles
      .map((profile) => (typeof profile?.id === 'string' ? profile.id.trim() : ''))
      .filter((value) => value.length > 0);
    const defaultPrimary =
      typeof response?.defaults?.model_primary === 'string'
        ? response.defaults.model_primary.trim()
        : '';
    return {
      count: profiles.length,
      ids,
      defaultPrimary,
    };
  }

  function parseBindings(response: AgentBindingsResponse): { count: number; channels: string[] } {
    const bindings = Array.isArray(response?.bindings) ? response.bindings : [];
    const channels = [
      ...new Set(
        bindings
          .map((binding) =>
            typeof binding?.match?.channel === 'string' ? binding.match.channel.trim() : '',
          )
          .filter((value) => value.length > 0),
      ),
    ].sort((a, b) => a.localeCompare(b));
    return {
      count: bindings.length,
      channels,
    };
  }

  function routeSummaryLabel(state: AgentRouteSummaryState): string {
    return t(`instanceDetail.agentRouteStates.${state}`);
  }

  function routeStateTone(state: AgentRouteSummaryState): 'ok' | 'warn' | 'pending' {
    switch (state) {
      case 'configured':
        return 'ok';
      case 'default_only':
      case 'missing_profiles':
        return 'warn';
      default:
        return 'pending';
    }
  }

  async function loadFleet(force = false) {
    const rows = nullclawInstances;
    const signature = buildSignature(rows);
    if (!force && signature === loadedSignature) return;

    loadedSignature = signature;
    loadError = '';

    if (rows.length === 0) {
      fleetSnapshots = {};
      loading = false;
      return;
    }

    const req = ++requestSeq;
    loading = true;

    const results = await Promise.all(
      rows.map(async (row) => {
        const key = snapshotKey(row);
        const [profilesRes, bindingsRes] = await Promise.allSettled([
          api.getAgentProfiles(row.component, row.name),
          api.getAgentBindings(row.component, row.name),
        ]);

        let profilesCount: number | null = null;
        let bindingsCount: number | null = null;
        let defaultPrimary = '';
        let profileIds: string[] = [];
        let channels: string[] = [];
        let summaryState: AgentRouteSummaryState = 'unknown';
        let error = '';

        if (profilesRes.status === 'fulfilled' && bindingsRes.status === 'fulfilled') {
          const profileSummary = parseProfiles(profilesRes.value);
          const bindingSummary = parseBindings(bindingsRes.value);
          profilesCount = profileSummary.count;
          bindingsCount = bindingSummary.count;
          defaultPrimary = profileSummary.defaultPrimary;
          profileIds = profileSummary.ids;
          channels = bindingSummary.channels;

          if (profilesCount === 0) {
            summaryState = 'missing_profiles';
          } else if (bindingsCount === 0) {
            summaryState = 'default_only';
          } else {
            summaryState = 'configured';
          }
        } else {
          summaryState = 'unavailable';
          const profileError =
            profilesRes.status === 'rejected'
              ? (profilesRes.reason as Error)?.message || t('agents.loadFailed')
              : '';
          const bindingError =
            bindingsRes.status === 'rejected'
              ? (bindingsRes.reason as Error)?.message || t('agents.loadFailed')
              : '';
          error = [profileError, bindingError].filter(Boolean).join(' · ');
        }

        return [
          key,
          {
            profilesCount,
            bindingsCount,
            defaultPrimary,
            profileIds,
            channels,
            summaryState,
            error,
          } satisfies FleetAgentSnapshot,
        ] as const;
      }),
    );

    if (req !== requestSeq) return;
    fleetSnapshots = Object.fromEntries(results);
    loading = false;
  }

  async function refreshFleet() {
    await refreshStatus();
    loadedSignature = '';
    await loadFleet(true);
  }

  $effect(() => {
    const signature = buildSignature(nullclawInstances);
    if (!signature) {
      fleetSnapshots = {};
      loadedSignature = '';
      loading = false;
      return;
    }
    void loadFleet();
  });
</script>

<svelte:head>
  <title>{t('nav.agents')} - NullHubX</title>
</svelte:head>

<div class="page-shell agents-page">
  <section class="section-shell hero-shell">
    <div class="page-hero">
      <div class="page-title-group">
        <span class="page-kicker">NullHubX</span>
        <h1 class="page-title">{t('nav.agents')}</h1>
        <p class="page-subtitle">{t('agents.subtitle')}</p>
      </div>
      <div class="page-actions">
        <button class="control-btn primary" onclick={refreshFleet} disabled={loading}>
          {loading ? t('common.loading') : t('common.refresh')}
        </button>
      </div>
    </div>

    <div class="metrics-grid">
      <article class="metric-card">
        <span class="metric-label">{t('agents.nullclawInstances')}</span>
        <strong class="metric-value">{$statusReady ? nullclawInstances.length : '—'}</strong>
        <p class="metric-meta">{t('agents.nullclawInstancesDesc')}</p>
      </article>
      <article class="metric-card">
        <span class="metric-label">{t('agents.configuredInstances')}</span>
        <strong class="metric-value">{routeCounts.configured}</strong>
        <p class="metric-meta">{t('instanceDetail.agentRouteStates.configured')}</p>
      </article>
      <article class="metric-card">
        <span class="metric-label">{t('agents.defaultFallbackInstances')}</span>
        <strong class="metric-value">{routeCounts.default_only}</strong>
        <p class="metric-meta">{t('instanceDetail.agentRouteStates.default_only')}</p>
      </article>
      <article class="metric-card">
        <span class="metric-label">{t('agents.unavailableInstances')}</span>
        <strong class="metric-value">{routeCounts.unavailable}</strong>
        <p class="metric-meta">{t('instanceDetail.agentRouteStates.unavailable')}</p>
      </article>
    </div>
  </section>

  <section class="section-shell main-shell">
    <div class="section-heading-row">
      <div class="section-heading">
        <span class="section-kicker">{t('nav.agents')}</span>
        <h2 class="section-title">{t('agents.workspaceTitle')}</h2>
        <p class="section-subtitle">{t('agents.workspaceHint')}</p>
      </div>
      <div class="toolbar">
        <input type="text" bind:value={keyword} placeholder={t('agents.searchPlaceholder')} />
      </div>
    </div>

    {#if $statusError}
      <div class="feedback-banner error-banner">
        {t('error.statusFetchFailed').replace('{error}', $statusError)}
      </div>
    {/if}

    {#if loadError}
      <div class="feedback-banner error-banner">{loadError}</div>
    {/if}

    {#if nullclawInstances.length === 0}
      <div class="empty-panel">
        <h3>{t('agents.noNullclawInstances')}</h3>
        <p>{t('agents.noNullclawInstancesHint')}</p>
        <a class="control-btn primary" href="/hub">{t('hub.installNewComponent')}</a>
      </div>
    {:else if filteredRows.length === 0}
      <div class="empty-panel">
        <h3>{t('common.noData')}</h3>
        <p>{t('agents.emptyFiltered')}</p>
      </div>
    {:else}
      <div class="fleet-grid">
        {#each filteredRows as row (`${row.component}/${row.name}`)}
          {@const key = snapshotKey(row)}
          {@const snapshot = fleetSnapshots[key]}
          <article class="fleet-card">
            <div class="fleet-card-head">
              <div>
                <div class="fleet-route">{row.component}/{row.name}</div>
                <div class="fleet-meta">
                  <span class="surface-chip">{row.info.version || '-'}</span>
                  <span class="surface-chip"
                    >{snapshot?.defaultPrimary || t('agents.defaultPrimaryMissing')}</span
                  >
                </div>
              </div>
              <StatusBadge status={row.info.status || 'stopped'} />
            </div>

            <div class="fleet-state-row">
              <span class={`table-status ${routeStateTone(snapshot?.summaryState || 'unknown')}`}>
                {routeSummaryLabel(snapshot?.summaryState || 'unknown')}
              </span>
              <a class="toolbar-link" href={`/instances/${row.component}/${row.name}`}
                >{t('agents.openInstanceWorkspace')}</a
              >
            </div>

            <div class="fleet-stats">
              <div class="fleet-stat">
                <span>{t('agents.profilesCount')}</span>
                <strong>{snapshot?.profilesCount ?? '-'}</strong>
              </div>
              <div class="fleet-stat">
                <span>{t('agents.bindingsCount')}</span>
                <strong>{snapshot?.bindingsCount ?? '-'}</strong>
              </div>
              <div class="fleet-stat">
                <span>{t('agents.runtimeStatus')}</span>
                <strong>{row.info.status || '-'}</strong>
              </div>
              <div class="fleet-stat">
                <span>{t('instanceDetail.restartCountLabel')}</span>
                <strong>{row.info.restart_count ?? 0}</strong>
              </div>
            </div>

            <div class="fleet-detail-grid">
              <div class="fleet-detail">
                <span>{t('agents.defaultPrimary')}</span>
                <strong>{snapshot?.defaultPrimary || '-'}</strong>
              </div>
              <div class="fleet-detail">
                <span>{t('agents.channelCoverage')}</span>
                <strong>{snapshot?.channels?.length ? snapshot.channels.join(', ') : '-'}</strong>
              </div>
            </div>

            <div class="fleet-profile-list">
              <span>{t('agents.profileIds')}</span>
              {#if snapshot?.profileIds?.length}
                <div class="chip-list">
                  {#each snapshot.profileIds.slice(0, 6) as profileId}
                    <span class="surface-chip">{profileId}</span>
                  {/each}
                  {#if snapshot.profileIds.length > 6}
                    <span class="surface-chip">+{snapshot.profileIds.length - 6}</span>
                  {/if}
                </div>
              {:else}
                <p class="muted-copy">{t('instanceDetail.agentRouteStates.missing_profiles')}</p>
              {/if}
            </div>

            {#if snapshot?.error}
              <div class="card-warning">{snapshot.error}</div>
            {/if}
          </article>
        {/each}
      </div>
    {/if}
  </section>
</div>

<style>
  .hero-shell {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-xl);
  }

  .main-shell {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-lg);
  }

  .toolbar {
    display: flex;
    gap: var(--spacing-lg);
    align-items: center;
    flex-wrap: wrap;
  }

  .toolbar input {
    min-width: 260px;
  }

  .feedback-banner {
    padding: var(--spacing-md) var(--spacing-lg);
    border-radius: var(--radius-lg);
    border: 1px solid rgba(244, 63, 94, 0.16);
    background: rgba(255, 241, 245, 0.82);
    color: var(--red-700);
    box-shadow: var(--shadow-sm);
  }

  .fleet-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(320px, 1fr));
    gap: var(--spacing-lg);
  }

  .fleet-card {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-md);
    padding: var(--spacing-lg);
    border-radius: var(--radius-xl);
    border: 1px solid rgba(141, 154, 178, 0.16);
    background: rgba(255, 255, 255, 0.72);
    box-shadow: var(--shadow-sm);
  }

  .fleet-card-head {
    display: flex;
    justify-content: space-between;
    gap: var(--spacing-md);
    align-items: flex-start;
  }

  .fleet-route {
    font-family: var(--font-mono);
    font-size: var(--text-base);
    font-weight: 700;
    color: var(--slate-900);
  }

  .fleet-meta {
    display: flex;
    flex-wrap: wrap;
    gap: var(--spacing-sm);
    margin-top: var(--spacing-sm);
  }

  .fleet-state-row {
    display: flex;
    justify-content: space-between;
    gap: var(--spacing-md);
    align-items: center;
    flex-wrap: wrap;
  }

  .table-status {
    display: inline-flex;
    align-items: center;
    padding: 5px 10px;
    border-radius: 999px;
    font-size: var(--text-xs);
    font-weight: 600;
    letter-spacing: 0.04em;
    border: 1px solid rgba(141, 154, 178, 0.18);
    background: rgba(255, 255, 255, 0.82);
    color: var(--slate-600);
  }

  .table-status.ok {
    background: rgba(16, 185, 129, 0.12);
    color: var(--emerald-700);
    border-color: rgba(16, 185, 129, 0.18);
  }

  .table-status.warn {
    background: rgba(245, 158, 11, 0.12);
    color: var(--amber-700);
    border-color: rgba(245, 158, 11, 0.18);
  }

  .table-status.pending {
    background: rgba(241, 245, 249, 0.9);
    color: var(--slate-600);
    border-color: rgba(141, 154, 178, 0.18);
  }

  .fleet-stats {
    display: grid;
    grid-template-columns: repeat(4, minmax(0, 1fr));
    gap: var(--spacing-sm);
  }

  .fleet-stat,
  .fleet-detail {
    display: flex;
    flex-direction: column;
    gap: 4px;
    padding: var(--spacing-sm);
    border-radius: var(--radius-lg);
    background: rgba(248, 250, 252, 0.9);
    border: 1px solid rgba(226, 232, 240, 0.9);
  }

  .fleet-stat span,
  .fleet-detail span,
  .fleet-profile-list > span {
    color: var(--slate-500);
    font-size: var(--text-xs);
    text-transform: uppercase;
    letter-spacing: 0.08em;
    font-weight: 600;
  }

  .fleet-stat strong,
  .fleet-detail strong {
    color: var(--slate-900);
    font-size: var(--text-sm);
  }

  .fleet-detail-grid {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: var(--spacing-sm);
  }

  .fleet-profile-list {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-sm);
  }

  .chip-list {
    display: flex;
    flex-wrap: wrap;
    gap: var(--spacing-sm);
  }

  .muted-copy {
    margin: 0;
    color: var(--slate-500);
    font-size: var(--text-sm);
  }

  .card-warning {
    padding: var(--spacing-sm) var(--spacing-md);
    border-radius: var(--radius-lg);
    border: 1px solid rgba(245, 158, 11, 0.18);
    background: rgba(255, 251, 235, 0.88);
    color: var(--amber-700);
    font-size: var(--text-sm);
    line-height: 1.5;
  }

  @media (max-width: 900px) {
    .fleet-stats {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }
  }

  @media (max-width: 680px) {
    .toolbar input {
      min-width: 0;
      width: 100%;
    }

    .fleet-grid,
    .fleet-stats,
    .fleet-detail-grid {
      grid-template-columns: 1fr;
    }
  }
</style>
