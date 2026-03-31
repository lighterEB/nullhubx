<script lang="ts">
  import InstanceCard from "$lib/components/InstanceCard.svelte";
  import StatusBadge from "$lib/components/StatusBadge.svelte";
  import { instancesState, statusError, statusReady, instanceCount, runningCount, refreshStatus } from "$lib/statusStore";
  import { t } from "$lib/i18n/index.svelte";
  import type { InstanceInfo, InstancesPayload } from "$lib/api/client";

  let selectedComponent = $state("all");
  let keyword = $state("");
  let previewTarget = $state("");

  const componentStats = $derived.by(() => {
    const groups: InstancesPayload = $instancesState;
    const rows = Object.entries(groups).map(([component, instances]) => {
      const total = Object.keys(instances).length;
      const running = Object.values(instances).filter((inst: InstanceInfo) =>
        ["running", "starting", "restarting"].includes(inst.status || "stopped"),
      ).length;
      return { component, total, running };
    });
    rows.sort((a, b) => a.component.localeCompare(b.component));
    return rows;
  });

  const filteredInstances = $derived.by(() => {
    const rows: Array<{ component: string; name: string; info: InstanceInfo }> = [];
    const groups: InstancesPayload = $instancesState;
    const query = keyword.trim().toLowerCase();

    for (const [component, instances] of Object.entries(groups)) {
      if (selectedComponent !== "all" && component !== selectedComponent) continue;
      for (const [name, info] of Object.entries(instances) as Array<[string, InstanceInfo]>) {
        if (query.length > 0) {
          const hay = `${component}/${name}`.toLowerCase();
          if (!hay.includes(query)) continue;
        }
        rows.push({ component, name, info });
      }
    }

    rows.sort((a, b) => `${a.component}/${a.name}`.localeCompare(`${b.component}/${b.name}`));
    return rows;
  });

  const filteredCount = $derived(filteredInstances.length);
  const selectedComponentLabel = $derived(
    selectedComponent === "all" ? t("instances.allComponents") : selectedComponent,
  );
  const previewInstance = $derived.by(() => {
    if (filteredInstances.length === 0) return null;
    return (
      filteredInstances.find((row) => `${row.component}/${row.name}` === previewTarget) ||
      filteredInstances[0]
    );
  });

  $effect(() => {
    if (filteredInstances.length === 0) {
      previewTarget = "";
      return;
    }

    if (!filteredInstances.some((row) => `${row.component}/${row.name}` === previewTarget)) {
      previewTarget = `${filteredInstances[0].component}/${filteredInstances[0].name}`;
    }
  });

  function setPreview(component: string, name: string) {
    previewTarget = `${component}/${name}`;
  }
</script>

<svelte:head>
  <title>{t("instances.title")} - NullHubX</title>
</svelte:head>

<div class="page-shell instances-page">
  <section class="section-shell hero-shell">
    <div class="page-hero">
      <div class="page-title-group">
        <span class="page-kicker">NullHubX</span>
        <h1 class="page-title">{t("instances.title")}</h1>
        <p class="page-subtitle">{t("instances.subtitle")}</p>
      </div>
      <div class="page-actions">
        <button class="control-btn primary" onclick={refreshStatus}>{t("common.refresh")}</button>
        <a class="control-btn secondary" href="/hub">{t("hub.installNewComponent")}</a>
      </div>
    </div>

    <div class="metrics-grid">
      <article class="metric-card">
        <span class="metric-label">{t("instances.allComponents")}</span>
        <strong class="metric-value">{$statusReady ? componentStats.length : "—"}</strong>
        <p class="metric-meta">{t("overview.componentCount")}</p>
      </article>
      <article class="metric-card">
        <span class="metric-label">{t("overview.instanceTotal")}</span>
        <strong class="metric-value">{$statusReady ? $instanceCount : "—"}</strong>
        <p class="metric-meta">{t("instances.instanceList")}</p>
      </article>
      <article class="metric-card">
        <span class="metric-label">{t("overview.runningInstances")}</span>
        <strong class="metric-value">{$statusReady ? $runningCount : "—"}</strong>
        <p class="metric-meta">{t("statusBar.operational")}</p>
      </article>
      <article class="metric-card">
        <span class="metric-label">{t("common.search")}</span>
        <strong class="metric-value">{$statusReady ? filteredCount : "—"}</strong>
        <p class="metric-meta">{selectedComponentLabel}</p>
      </article>
    </div>
  </section>

  <div class="workspace-grid">
    <aside class="section-shell sidebar-panel">
      <div class="section-heading">
        <span class="section-kicker">{t("instances.title")}</span>
        <h2 class="section-title">{t("instances.allComponents")}</h2>
        <p class="section-subtitle">{t("instances.subtitle")}</p>
      </div>

      <div class="filter-list">
        <button class="filter-chip" class:selected={selectedComponent === "all"} onclick={() => (selectedComponent = "all")}>
          <span>{t("instances.allComponents")}</span>
          <strong>{$statusReady ? $instanceCount : "—"}</strong>
        </button>

        {#each componentStats as row (row.component)}
          <button
            class="filter-chip"
            class:selected={selectedComponent === row.component}
            onclick={() => (selectedComponent = row.component)}
          >
            <span>{row.component}</span>
            <strong>{row.running}/{row.total}</strong>
          </button>
        {/each}
      </div>
    </aside>

    <section class="section-shell main-panel">
      <div class="section-heading-row">
        <div class="section-heading">
          <span class="section-kicker">{selectedComponentLabel}</span>
          <h2 class="section-title">{t("instances.instanceList")}</h2>
          <p class="section-subtitle">
            {#if $statusReady}
              {$instanceCount} {t("hub.instances")}，{$runningCount} {t("statusBar.running")}
            {:else}
              {t("common.loading")}
            {/if}
          </p>
        </div>
        <div class="toolbar">
          <input
            type="text"
            placeholder={t("instances.searchPlaceholder")}
            bind:value={keyword}
          />
          <button class="control-btn secondary toolbar-btn" onclick={refreshStatus}>{t("common.refresh")}</button>
        </div>
      </div>

      {#if $statusError}
        <div class="error-banner">{t("error.statusFetchFailed").replace("{error}", $statusError)}</div>
      {/if}

      {#if !$statusReady && !$statusError}
        <div class="instance-grid" aria-hidden="true">
          {#each Array(4) as _, index}
            <div class="instance-skeleton" style={`--skeleton-delay:${index * 40}ms`}></div>
          {/each}
        </div>
      {:else if filteredInstances.length === 0}
        <div class="empty-panel workspace-empty">
          <h3>{t("common.noData")}</h3>
          <p>{t("instances.emptyState")}</p>
        </div>
      {:else}
        <div class="instance-grid">
          {#each filteredInstances as row (`${row.component}/${row.name}`)}
            <div
              class="card-wrapper"
              class:is-preview={previewInstance && `${row.component}/${row.name}` === `${previewInstance.component}/${previewInstance.name}`}
              role="group"
              aria-label={`${row.component}/${row.name}`}
              onmouseenter={() => setPreview(row.component, row.name)}
              onfocusin={() => setPreview(row.component, row.name)}
            >
              <InstanceCard
                component={row.component}
                name={row.name}
                version={row.info.version}
                status={row.info.status || "stopped"}
                port={row.info.port || 0}
                onAction={refreshStatus}
              />
            </div>
          {/each}
        </div>
      {/if}
    </section>

    <aside class="section-shell preview-panel">
      <div class="section-heading">
        <span class="section-kicker">{t("instanceDetail.tabs.overview")}</span>
        <h2 class="section-title">{t("instanceDetail.title")}</h2>
        <p class="section-subtitle">{t("instanceDetail.subtitle")}</p>
      </div>

      {#if previewInstance}
        <div class="preview-card">
          <div class="preview-header">
            <div>
              <div class="preview-route">{previewInstance.component}/{previewInstance.name}</div>
              <div class="preview-meta">
                <span class="surface-chip">{previewInstance.component}</span>
                <span class="surface-chip">{previewInstance.info.version || "-"}</span>
              </div>
            </div>
            <StatusBadge status={previewInstance.info.status || "stopped"} />
          </div>

          <div class="preview-stats">
            <div class="preview-stat">
              <span>{t("instanceDetail.portLabel")}</span>
              <strong>{previewInstance.info.port || "-"}</strong>
            </div>
            <div class="preview-stat">
              <span>{t("instanceDetail.versionLabel")}</span>
              <strong>{previewInstance.info.version || "-"}</strong>
            </div>
            <div class="preview-stat">
              <span>{t("instanceDetail.statusLabel")}</span>
              <strong>{previewInstance.info.status || "stopped"}</strong>
            </div>
          </div>

          <div class="preview-actions">
            <a class="control-btn primary" href={`/instances/${previewInstance.component}/${previewInstance.name}`}>
              {t("instanceDetail.tabs.overview")}
            </a>
          </div>
        </div>
      {:else}
        <p class="empty-panel">{t("instances.emptyState")}</p>
      {/if}
    </aside>
  </div>
</div>

<style>
  .hero-shell {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-xl);
  }

  .instance-skeleton {
    min-height: 248px;
    border-radius: var(--radius-xl);
    border: 1px solid rgba(148, 163, 184, 0.14);
    background:
      linear-gradient(
        90deg,
        rgba(226, 232, 240, 0.48) 0%,
        rgba(248, 250, 252, 0.94) 48%,
        rgba(226, 232, 240, 0.48) 100%
      );
    background-size: 220% 100%;
    animation: instanceSkeleton 1.3s ease-in-out infinite;
    animation-delay: var(--skeleton-delay, 0ms);
  }

  @keyframes instanceSkeleton {
    0% { background-position: 100% 0; }
    100% { background-position: -100% 0; }
  }

  .workspace-grid {
    display: grid;
    grid-template-columns: 260px minmax(0, 1fr) 320px;
    gap: var(--spacing-lg);
    align-items: start;
  }

  .sidebar-panel {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-lg);
    position: sticky;
    top: calc(var(--topbar-height) + 20px);
  }

  .filter-list {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-sm);
  }

  .filter-chip {
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: var(--spacing-md);
    width: 100%;
    padding: 0.75rem 0.9rem;
    border-radius: var(--radius-lg);
    border: 1px solid rgba(141, 154, 178, 0.18);
    background: rgba(255, 255, 255, 0.72);
    color: var(--slate-700);
    transition:
      color var(--transition-fast),
      background-color var(--transition-fast),
      border-color var(--transition-fast),
      box-shadow var(--transition-fast),
      transform var(--transition-fast);
  }

  .filter-chip:hover {
    border-color: rgba(34, 211, 238, 0.24);
    color: var(--slate-900);
    transform: translateY(-1px);
  }

  .filter-chip span {
    font-size: var(--text-sm);
    text-align: left;
  }

  .filter-chip strong {
    font-family: var(--font-mono);
    font-size: var(--text-xs);
    color: var(--slate-500);
  }

  .filter-chip.selected {
    border-color: rgba(34, 211, 238, 0.22);
    background: linear-gradient(135deg, rgba(15, 23, 42, 0.95), rgba(24, 34, 56, 0.92));
    color: var(--shell-text);
    box-shadow: var(--glow-cyan);
  }

  .filter-chip.selected strong {
    color: var(--cyan-300);
  }

  .main-panel,
  .preview-panel {
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
    width: min(260px, 100%);
  }

  .toolbar-btn {
    min-width: 108px;
  }

  .error-banner {
    padding: 0.85rem 1rem;
    border: 1px solid rgba(244, 63, 94, 0.16);
    background: rgba(255, 241, 245, 0.82);
    border-radius: var(--radius-lg);
    color: var(--red-700);
  }

  .instance-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
    gap: var(--spacing-lg);
  }

  .card-wrapper {
    display: block;
  }

  .card-wrapper.is-preview :global(.instance-card) {
    border-color: rgba(34, 211, 238, 0.28);
    box-shadow: var(--shadow-md), 0 0 0 1px rgba(34, 211, 238, 0.1);
  }

  .workspace-empty {
    padding: var(--spacing-4xl);
    text-align: center;
  }

  .workspace-empty h3 {
    margin: 0;
    color: var(--slate-800);
  }

  .workspace-empty p {
    margin: var(--spacing-sm) 0 0 0;
  }

  .preview-panel {
    position: sticky;
    top: calc(var(--topbar-height) + 20px);
  }

  .preview-card {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-lg);
    padding: var(--spacing-lg);
    border-radius: var(--radius-lg);
    border: 1px solid rgba(34, 211, 238, 0.18);
    background: linear-gradient(180deg, rgba(15, 23, 42, 0.96), rgba(18, 28, 48, 0.94));
    color: var(--shell-text);
    box-shadow: var(--glow-cyan);
    overflow: hidden;
  }

  .preview-header {
    display: flex;
    justify-content: space-between;
    gap: var(--spacing-md);
    align-items: flex-start;
    min-width: 0;
  }

  .preview-header > div:first-child {
    min-width: 0;
  }

  .preview-route {
    font-family: var(--font-mono);
    font-size: var(--text-sm);
    line-height: 1.6;
    word-break: break-word;
  }

  .preview-meta {
    display: flex;
    flex-wrap: wrap;
    gap: var(--spacing-xs);
    margin-top: var(--spacing-sm);
  }

  .preview-meta :global(.surface-chip) {
    background: rgba(255, 255, 255, 0.1);
    color: var(--shell-text);
    border-color: rgba(255, 255, 255, 0.16);
  }

  .preview-stats {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: var(--spacing-sm);
  }

  .preview-stat {
    padding: 0.8rem;
    border-radius: var(--radius-md);
    border: 1px solid rgba(116, 136, 173, 0.22);
    background: rgba(255, 255, 255, 0.06);
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .preview-stat span {
    font-size: var(--text-xs);
    color: var(--shell-text-dim);
    letter-spacing: 0.06em;
    text-transform: uppercase;
  }

  .preview-stat strong {
    font-family: var(--font-mono);
    font-size: var(--text-sm);
    color: var(--shell-text);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .preview-actions {
    display: flex;
  }

  .preview-actions .control-btn {
    width: 100%;
  }

  @media (max-width: 980px) {
    .workspace-grid {
      grid-template-columns: 1fr;
    }

    .sidebar-panel,
    .preview-panel {
      position: static;
    }
  }

  @media (max-width: 680px) {
    .toolbar {
      width: 100%;
    }

    .toolbar input,
    .toolbar-btn {
      width: 100%;
    }

    .preview-stats {
      grid-template-columns: 1fr;
    }
  }
</style>
