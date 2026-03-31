<script lang="ts">
  import { status, statusError, statusReady, instanceCount, runningCount, refreshStatus } from "$lib/statusStore";
  import { t } from "$lib/i18n/index.svelte";
  import StatusBadge from "$lib/components/StatusBadge.svelte";
  import type { InstanceInfo, InstancesPayload } from "$lib/api/client";
  const managementEntryCount = 5;

  const componentCount = $derived(Object.keys($status?.instances || {}).length);

  const recentInstances = $derived.by(() => {
    const rows: Array<{ component: string; name: string; status: string; version: string }> = [];
    const groups: InstancesPayload = $status?.instances || {};
    for (const [component, instances] of Object.entries(groups)) {
      for (const [name, info] of Object.entries(instances) as Array<[string, InstanceInfo]>) {
        rows.push({
          component,
          name,
          status: info?.status || "stopped",
          version: info?.version || "-",
        });
      }
    }
    rows.sort((a, b) => `${a.component}/${a.name}`.localeCompare(`${b.component}/${b.name}`));
    return rows.slice(0, 10);
  });
</script>

<svelte:head>
  <title>{t('nav.overview')} - NullHubX</title>
</svelte:head>

<div class="page-shell overview-page">
  <section class="section-shell hero-shell">
    <div class="page-hero">
      <div class="page-title-group">
        <span class="page-kicker">NullHubX</span>
        <h1 class="page-title">{t('overview.title')}</h1>
        <p class="page-subtitle">{t('overview.subtitle')}</p>
      </div>
      <div class="page-actions">
        <button class="control-btn primary" onclick={refreshStatus}>{t('overview.refreshStatus')}</button>
      </div>
    </div>

    <div class="metrics-grid">
      <article class="metric-card">
        <span class="metric-label">{t('overview.componentCount')}</span>
        <strong class="metric-value">{$statusReady ? componentCount : "—"}</strong>
        <p class="metric-meta">{t('hub.title')}</p>
      </article>
      <article class="metric-card">
        <span class="metric-label">{t('overview.instanceTotal')}</span>
        <strong class="metric-value">{$statusReady ? $instanceCount : "—"}</strong>
        <p class="metric-meta">{t('instances.title')}</p>
      </article>
      <article class="metric-card">
        <span class="metric-label">{t('overview.runningInstances')}</span>
        <strong class="metric-value">{$statusReady ? $runningCount : "—"}</strong>
        <p class="metric-meta">{t('statusBar.operational')}</p>
      </article>
      <article class="metric-card">
        <span class="metric-label">{t('overview.managementEntries')}</span>
        <strong class="metric-value">{managementEntryCount}</strong>
        <p class="metric-meta">{t('nav.settings')} / {t('nav.resources')}</p>
      </article>
    </div>
  </section>

  {#if $statusError}
    <div class="feedback-banner error-banner">{t('error.statusFetchFailed').replace('{error}', $statusError)}</div>
  {/if}

  <section class="section-shell">
    <div class="section-heading-row">
      <div class="section-heading">
        <span class="section-kicker">NullHubX</span>
        <h2 class="section-title">{t('overview.managementEntries')}</h2>
      </div>
      <span class="surface-chip">{managementEntryCount}</span>
    </div>

    <div class="entry-grid">
      <a class="entry-card" href="/instances">
        <span class="entry-icon">◎</span>
        <div class="entry-copy">
          <span class="surface-chip entry-path">/instances</span>
          <h3>{t('instances.title')}</h3>
          <p>{t('instances.subtitle')}</p>
        </div>
        <span class="entry-cta">→</span>
      </a>
      <a class="entry-card" href="/connections">
        <span class="entry-icon">⌘</span>
        <div class="entry-copy">
          <span class="surface-chip entry-path">/connections</span>
          <h3>{t('connections.title')}</h3>
          <p>{t('connections.subtitle')}</p>
        </div>
        <span class="entry-cta">→</span>
      </a>
      <a class="entry-card" href="/orchestration">
        <span class="entry-icon">◇</span>
        <div class="entry-copy">
          <span class="surface-chip entry-path">/orchestration</span>
          <h3>{t('orchestration.title')}</h3>
          <p>{t('orchestration.subtitle')}</p>
        </div>
        <span class="entry-cta">→</span>
      </a>
      <a class="entry-card" href="/hub">
        <span class="entry-icon">⬡</span>
        <div class="entry-copy">
          <span class="surface-chip entry-path">/hub</span>
          <h3>{t('hub.title')}</h3>
          <p>{t('hub.subtitle')}</p>
        </div>
        <span class="entry-cta">→</span>
      </a>
    </div>
  </section>

  <section class="section-shell">
    <div class="section-heading-row">
      <div class="section-heading">
        <span class="section-kicker">{t('nav.instances')}</span>
        <h2 class="section-title">{t('overview.recentInstances')}</h2>
      </div>
      <a class="control-btn secondary recent-link" href="/instances">{t('overview.enterInstances')}</a>
    </div>

    {#if !$statusReady && !$statusError}
      <div class="list-skeleton" aria-hidden="true">
        {#each Array(4) as _, index}
          <div class="skeleton-row" style={`--skeleton-delay:${index * 40}ms`}></div>
        {/each}
      </div>
    {:else if recentInstances.length === 0}
      <p class="empty-panel">{t('overview.emptyState')}</p>
    {:else}
      <ul class="recent-list">
        {#each recentInstances as row}
          <li class="recent-row">
            <div class="recent-main">
              <a href={`/instances/${row.component}/${row.name}`}>{row.component}/{row.name}</a>
              <span class="recent-component">{row.component}</span>
            </div>
            <div class="recent-meta">
              <StatusBadge status={row.status} />
              <span class="surface-chip recent-version">{row.version}</span>
            </div>
          </li>
        {/each}
      </ul>
    {/if}
  </section>
</div>

<style>
  .hero-shell {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-xl);
  }

  .feedback-banner {
    padding: var(--spacing-md) var(--spacing-lg);
    border-radius: var(--radius-lg);
    border: 1px solid rgba(244, 63, 94, 0.16);
    background: rgba(255, 241, 245, 0.82);
    color: var(--red-700);
    box-shadow: var(--shadow-sm);
  }

  .list-skeleton {
    display: grid;
    gap: var(--spacing-sm);
  }

  .skeleton-row {
    height: 68px;
    border-radius: var(--radius-lg);
    border: 1px solid rgba(148, 163, 184, 0.14);
    background:
      linear-gradient(
        90deg,
        rgba(226, 232, 240, 0.52) 0%,
        rgba(248, 250, 252, 0.94) 48%,
        rgba(226, 232, 240, 0.52) 100%
      );
    background-size: 220% 100%;
    animation: overviewSkeleton 1.3s ease-in-out infinite;
    animation-delay: var(--skeleton-delay, 0ms);
  }

  @keyframes overviewSkeleton {
    0% { background-position: 100% 0; }
    100% { background-position: -100% 0; }
  }

  .entry-grid {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: var(--spacing-md);
  }

  .entry-card {
    display: grid;
    grid-template-columns: auto 1fr auto;
    gap: var(--spacing-lg);
    align-items: flex-start;
    padding: var(--spacing-lg);
    border-radius: var(--radius-lg);
    border: 1px solid rgba(141, 154, 178, 0.18);
    background: linear-gradient(180deg, rgba(255, 255, 255, 0.76), rgba(242, 248, 255, 0.7));
    text-decoration: none;
    color: inherit;
    transition: all var(--transition-base);
  }

  .entry-card:hover {
    transform: translateY(-2px);
    border-color: rgba(34, 211, 238, 0.26);
    box-shadow: var(--shadow-md), 0 0 0 1px rgba(34, 211, 238, 0.08);
  }

  .entry-icon {
    width: 44px;
    height: 44px;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    border-radius: var(--radius-md);
    background: linear-gradient(135deg, rgba(15, 23, 42, 0.96), rgba(24, 34, 56, 0.94));
    color: var(--shell-text);
    box-shadow: var(--glow-cyan);
    font-size: var(--text-lg);
  }

  .entry-copy {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-sm);
    min-width: 0;
  }

  .entry-path {
    width: fit-content;
  }

  .entry-copy h3 {
    margin: 0;
    color: var(--slate-900);
    font-size: var(--text-lg);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .entry-copy p {
    margin: 0;
    color: var(--slate-600);
    font-size: var(--text-sm);
    line-height: 1.6;
    display: -webkit-box;
    -webkit-line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
  }

  .entry-cta {
    align-self: center;
    color: var(--cyan-600);
    font-family: var(--font-mono);
    font-size: var(--text-lg);
    font-weight: 600;
  }

  .recent-link {
    width: fit-content;
  }

  .recent-list {
    list-style: none;
    display: flex;
    flex-direction: column;
    gap: var(--spacing-sm);
    margin: 0;
    padding: 0;
  }

  .recent-row {
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: var(--spacing-lg);
    padding: 0.9rem 1rem;
    border-radius: var(--radius-lg);
    border: 1px solid rgba(141, 154, 178, 0.16);
    background: rgba(255, 255, 255, 0.64);
  }

  .recent-main {
    display: flex;
    flex-direction: column;
    gap: 4px;
    min-width: 0;
  }

  .recent-main a {
    color: var(--slate-900);
    font-family: var(--font-mono);
    font-size: var(--text-sm);
    text-decoration: none;
    word-break: break-all;
  }

  .recent-main a:hover {
    color: var(--cyan-600);
  }

  .recent-component {
    color: var(--slate-500);
    font-size: var(--text-xs);
    letter-spacing: 0.04em;
    text-transform: uppercase;
  }

  .recent-meta {
    display: flex;
    align-items: center;
    justify-content: flex-end;
    gap: var(--spacing-sm);
    flex-wrap: wrap;
  }

  .recent-version {
    min-width: 72px;
    justify-content: center;
  }

  @media (max-width: 960px) {
    .entry-grid {
      grid-template-columns: 1fr;
    }
  }

  @media (max-width: 680px) {
    .recent-row {
      flex-direction: column;
      align-items: stretch;
    }

    .recent-meta {
      justify-content: flex-start;
    }
  }
</style>
