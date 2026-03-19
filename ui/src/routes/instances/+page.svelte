<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import InstanceCard from "$lib/components/InstanceCard.svelte";
  import { status, statusError, instanceCount, runningCount, subscribeStatus, refreshStatus } from "$lib/statusStore";
  import { t } from "$lib/i18n/index.svelte";

  let unsubscribe: (() => void) | null = null;
  let selectedComponent = $state("all");
  let keyword = $state("");

  onMount(() => {
    unsubscribe = subscribeStatus();
  });

  onDestroy(() => {
    unsubscribe?.();
  });

  const componentStats = $derived.by(() => {
    const groups = $status?.instances || {};
    const rows = Object.entries(groups).map(([component, instances]) => {
      const instMap = instances as Record<string, any>;
      const total = Object.keys(instMap).length;
      const running = Object.values(instMap).filter((inst: any) =>
        ["running", "starting", "restarting"].includes(inst?.status || "stopped"),
      ).length;
      return { component, total, running };
    });
    rows.sort((a, b) => a.component.localeCompare(b.component));
    return rows;
  });

  const filteredInstances = $derived.by(() => {
    const rows: Array<{ component: string; name: string; info: any }> = [];
    const groups = $status?.instances || {};
    const query = keyword.trim().toLowerCase();

    for (const [component, instances] of Object.entries(groups)) {
      if (selectedComponent !== "all" && component !== selectedComponent) continue;
      for (const [name, info] of Object.entries(instances as Record<string, any>)) {
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
</script>

<svelte:head>
  <title>{t("instances.title")} - NullHubX</title>
</svelte:head>

<div class="workspace">
  <aside class="sidebar">
    <header class="sidebar-header">
      <h2>{t("instances.title")}</h2>
      <p>{t("instances.subtitle")}</p>
    </header>

    <button class:selected={selectedComponent === "all"} onclick={() => (selectedComponent = "all")}>
      {t("instances.allComponents")}
      <span>{$instanceCount}</span>
    </button>

    {#each componentStats as row}
      <button class:selected={selectedComponent === row.component} onclick={() => (selectedComponent = row.component)}>
        {row.component}
        <span>{row.running}/{row.total}</span>
      </button>
    {/each}

    <a class="install-link" href="/hub">+ {t("hub.installNewComponent")}</a>
  </aside>

  <section class="main">
    <header class="main-header">
      <div>
        <h1>{t("instances.instanceList")}</h1>
        <p>{$instanceCount} {t("hub.instances")}，{$runningCount} {t("statusBar.running")}</p>
      </div>
      <div class="toolbar">
        <input
          type="text"
          placeholder={t("instances.searchPlaceholder")}
          bind:value={keyword}
        />
        <button onclick={refreshStatus}>{t("common.refresh")}</button>
      </div>
    </header>

    {#if $statusError}
      <div class="error-banner">{t("error.statusFetchFailed").replace("{error}", $statusError)}</div>
    {/if}

    {#if filteredInstances.length === 0}
      <div class="empty-state">
        <h3>{t("common.noData")}</h3>
        <p>{t("instances.emptyState")}</p>
      </div>
    {:else}
      <div class="instance-grid">
        {#each filteredInstances as row, i}
          <div class="card-wrapper" style="animation-delay: {i * 50}ms">
            <InstanceCard
              component={row.component}
              name={row.name}
              version={row.info.version}
              status={row.info.status || "stopped"}
              autoStart={row.info.auto_start}
              port={row.info.port || 0}
              onAction={refreshStatus}
            />
          </div>
        {/each}
      </div>
    {/if}
  </section>
</div>

<style>
  .workspace {
    display: grid;
    grid-template-columns: 260px minmax(0, 1fr);
    min-height: calc(100vh - var(--topbar-height) - var(--statusbar-height));
  }

  .sidebar {
    border-right: 1px solid var(--slate-200);
    padding: var(--spacing-xl);
    background: linear-gradient(180deg, #fcfdff 0%, #f8fafc 100%);
    display: flex;
    flex-direction: column;
    gap: var(--spacing-sm);
  }

  .sidebar-header {
    margin-bottom: var(--spacing-md);
  }

  .sidebar-header h2 {
    margin: 0;
    font-family: var(--font-mono);
    font-size: var(--text-lg);
    color: var(--slate-900);
  }

  .sidebar-header p {
    margin: var(--spacing-xs) 0 0 0;
    color: var(--slate-500);
    font-size: var(--text-sm);
  }

  .sidebar button {
    display: flex;
    justify-content: space-between;
    align-items: center;
    border: 1px solid var(--slate-200);
    background: white;
    color: var(--slate-700);
    border-radius: var(--radius-md);
    padding: 0.6rem 0.7rem;
    cursor: pointer;
    transition: all var(--transition-fast);
    font-size: var(--text-sm);
  }

  .sidebar button span {
    font-family: var(--font-mono);
    color: var(--slate-500);
    font-size: var(--text-xs);
  }

  .sidebar button:hover {
    border-color: var(--indigo-300);
    color: var(--indigo-700);
  }

  .sidebar button.selected {
    border-color: var(--indigo-500);
    background: var(--indigo-50);
    color: var(--indigo-700);
  }

  .install-link {
    margin-top: var(--spacing-md);
    padding: 0.6rem 0.7rem;
    border-radius: var(--radius-md);
    text-decoration: none;
    border: 1px dashed var(--indigo-300);
    color: var(--indigo-700);
    font-weight: 600;
    font-size: var(--text-sm);
    text-align: center;
  }

  .main {
    padding: var(--spacing-3xl);
  }

  .main-header {
    display: flex;
    justify-content: space-between;
    align-items: flex-end;
    gap: var(--spacing-lg);
    margin-bottom: var(--spacing-xl);
  }

  .main-header h1 {
    margin: 0;
    font-family: var(--font-mono);
    font-size: var(--text-2xl);
    color: var(--slate-900);
  }

  .main-header p {
    margin: var(--spacing-xs) 0 0 0;
    color: var(--slate-500);
  }

  .toolbar {
    display: flex;
    gap: var(--spacing-sm);
  }

  .toolbar input {
    width: 240px;
    border: 1px solid var(--slate-300);
    border-radius: var(--radius-md);
    padding: 0.55rem 0.7rem;
  }

  .toolbar button {
    border: 1px solid var(--indigo-500);
    background: var(--indigo-600);
    color: white;
    border-radius: var(--radius-md);
    padding: 0.55rem 0.9rem;
    cursor: pointer;
  }

  .error-banner {
    margin-bottom: var(--spacing-lg);
    padding: 0.75rem 1rem;
    border: 1px solid var(--red-200);
    background: var(--red-50);
    border-radius: var(--radius-md);
    color: var(--red-700);
  }

  .instance-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
    gap: var(--spacing-lg);
  }

  .card-wrapper {
    opacity: 0;
    animation: fadeUp 0.4s ease forwards;
  }

  .empty-state {
    border: 1px dashed var(--slate-300);
    border-radius: var(--radius-lg);
    padding: var(--spacing-4xl);
    text-align: center;
    color: var(--slate-500);
    background: #f8fafc;
  }

  .empty-state h3 {
    margin: 0;
    color: var(--slate-700);
  }

  .empty-state p {
    margin: var(--spacing-sm) 0 0 0;
  }

  @keyframes fadeUp {
    from {
      opacity: 0;
      transform: translateY(16px);
    }
    to {
      opacity: 1;
      transform: translateY(0);
    }
  }

  @media (max-width: 980px) {
    .workspace {
      grid-template-columns: 1fr;
    }

    .sidebar {
      border-right: none;
      border-bottom: 1px solid var(--slate-200);
    }

    .main {
      padding: var(--spacing-xl);
    }

    .toolbar input {
      width: 180px;
    }
  }

  @media (max-width: 680px) {
    .main-header {
      flex-direction: column;
      align-items: stretch;
    }

    .toolbar {
      width: 100%;
    }

    .toolbar input,
    .toolbar button {
      flex: 1;
    }
  }
</style>
