<script lang="ts">
  import { onMount } from "svelte";
  import { api } from "$lib/api/client";
  import { t } from "$lib/i18n/index.svelte";

  let loading = $state(true);
  let error = $state("");
  let workflows = $state<any[]>([]);
  let runs = $state<any[]>([]);

  function hasNullBoiler(instancesPayload: any): boolean {
    const instances = instancesPayload?.instances?.nullboiler;
    return !!instances && Object.keys(instances).length > 0;
  }

  async function load() {
    loading = true;
    error = "";
    try {
      const instancesPayload = await api.getInstances().catch(() => null);
      if (!hasNullBoiler(instancesPayload)) {
        workflows = [];
        runs = [];
        error = t("orchestration.unavailableHint");
        return;
      }

      const wf = await api.listWorkflows();
      const run = await api.listRuns();
      workflows = wf || [];
      runs = run || [];
    } catch (e) {
      error = e instanceof Error ? e.message : t("error.loadFailed");
      workflows = [];
      runs = [];
    } finally {
      loading = false;
    }
  }

  onMount(() => {
    void load();
  });
</script>

<svelte:head>
  <title>{t("orchestration.title")} - NullHubX</title>
</svelte:head>

<div class="page">
  <header class="page-header">
    <div>
      <h1>{t("orchestration.title")}</h1>
      <p>{t("orchestration.subtitle")}</p>
    </div>
    <button class="refresh-btn" onclick={load} disabled={loading}>
      {loading ? t("orchestration.refreshing") : t("orchestration.refresh")}
    </button>
  </header>

  {#if error}
    <div class="warning-card">
      <h3>{t("orchestration.unavailable")}</h3>
      <p>{error}</p>
      <p class="hint">{t("orchestration.hint")}</p>
    </div>
  {:else}
    <div class="stats-grid">
      <div class="stat-card">
        <span>{t("orchestration.workflowCount")}</span>
        <strong>{workflows.length}</strong>
      </div>
      <div class="stat-card">
        <span>{t("orchestration.runCount")}</span>
        <strong>{runs.length}</strong>
      </div>
    </div>

    <section class="card">
      <div class="card-title-row">
        <h2>{t("orchestration.workflows")}</h2>
      </div>
      {#if workflows.length === 0}
        <p class="empty">{t("common.noData")}</p>
      {:else}
        <ul class="list">
          {#each workflows.slice(0, 10) as wf}
            <li>
              <strong>{wf.name || wf.id}</strong>
              <span>{wf.id}</span>
            </li>
          {/each}
        </ul>
      {/if}
    </section>

    <section class="card">
      <div class="card-title-row">
        <h2>{t("orchestration.runs")}</h2>
      </div>
      {#if runs.length === 0}
        <p class="empty">{t("common.noData")}</p>
      {:else}
        <ul class="list">
          {#each runs.slice(0, 12) as run}
            <li>
              <strong>{run.id}</strong>
              <span>{run.status || t("status.unknown")}</span>
            </li>
          {/each}
        </ul>
      {/if}
    </section>
  {/if}
</div>

<style>
  .page {
    max-width: 1160px;
    margin: 0 auto;
    padding: var(--spacing-3xl);
    display: flex;
    flex-direction: column;
    gap: var(--spacing-xl);
  }

  .page-header {
    display: flex;
    justify-content: space-between;
    align-items: flex-end;
    gap: var(--spacing-lg);
  }

  h1 {
    margin: 0;
    font-family: var(--font-mono);
    font-size: var(--text-2xl);
    color: var(--slate-900);
  }

  .page-header p {
    margin: var(--spacing-xs) 0 0 0;
    color: var(--slate-500);
  }

  .refresh-btn {
    border: 1px solid var(--indigo-500);
    background: var(--indigo-600);
    color: white;
    border-radius: var(--radius-md);
    padding: 0.55rem 0.9rem;
    cursor: pointer;
  }

  .refresh-btn:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  .warning-card {
    border: 1px solid var(--amber-300);
    background: #fffbeb;
    border-radius: var(--radius-lg);
    padding: var(--spacing-xl);
  }

  .warning-card h3 {
    margin: 0;
    color: #92400e;
    font-size: var(--text-lg);
  }

  .warning-card p {
    margin: var(--spacing-sm) 0 0 0;
    color: #78350f;
  }

  .warning-card .hint {
    color: #b45309;
    font-size: var(--text-sm);
  }

  .stats-grid {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: var(--spacing-md);
  }

  .stat-card {
    border: 1px solid var(--slate-200);
    border-radius: var(--radius-lg);
    background: white;
    padding: var(--spacing-lg);
  }

  .stat-card span {
    color: var(--slate-500);
    font-size: var(--text-sm);
  }

  .stat-card strong {
    display: block;
    margin-top: var(--spacing-xs);
    font-size: 1.7rem;
    color: var(--slate-900);
  }

  .card {
    border: 1px solid var(--slate-200);
    border-radius: var(--radius-lg);
    background: white;
    padding: var(--spacing-xl);
  }

  h2 {
    margin: 0 0 var(--spacing-md) 0;
    color: var(--slate-800);
    font-size: var(--text-lg);
  }

  .empty {
    margin: 0;
    color: var(--slate-500);
    padding: var(--spacing-md);
    background: var(--slate-50);
    border-radius: var(--radius-md);
  }

  .list {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: var(--spacing-sm);
  }

  .list li {
    display: flex;
    justify-content: space-between;
    align-items: center;
    border: 1px solid var(--slate-200);
    border-radius: var(--radius-md);
    padding: 0.55rem 0.7rem;
  }

  .list strong {
    color: var(--slate-800);
    font-size: var(--text-sm);
  }

  .list span {
    color: var(--slate-500);
    font-family: var(--font-mono);
    font-size: var(--text-xs);
  }

  @media (max-width: 780px) {
    .page {
      padding: var(--spacing-xl);
    }

    .page-header {
      flex-direction: column;
      align-items: stretch;
    }

    .stats-grid {
      grid-template-columns: 1fr;
    }
  }
</style>
