<script lang="ts">
  import { onMount } from "svelte";
  import { api, type InstancesResponse, type JsonObject } from "$lib/api/client";
  import GraphViewer from "$lib/components/orchestration/GraphViewer.svelte";
  import { t } from "$lib/i18n/index.svelte";

  type WorkflowEdge = { from: string; to: string; condition?: string };
  type WorkflowItem = JsonObject & {
    id?: string;
    name?: string;
    nodes?: Record<string, JsonObject>;
    edges?: WorkflowEdge[];
    updated_at?: string;
    created_at?: string;
  };

  type RunItem = JsonObject & {
    id?: string;
    status?: string;
    updated_at?: string;
    created_at?: string;
    workflow_id?: string;
    workflow?: JsonObject;
    steps?: JsonObject[];
  };

  let loading = $state(true);
  let error = $state("");
  let workflows = $state<WorkflowItem[]>([]);
  let runs = $state<RunItem[]>([]);

  function hasNullBoiler(instancesPayload: InstancesResponse | null): boolean {
    const instances = instancesPayload?.instances?.nullboiler;
    return !!instances && Object.keys(instances).length > 0;
  }

  function parseTimestamp(value: unknown): number {
    if (typeof value === "number") {
      return value > 1e12 ? value : value * 1000;
    }
    if (typeof value === "string" && value.trim()) {
      const parsed = Date.parse(value);
      return Number.isFinite(parsed) ? parsed : 0;
    }
    return 0;
  }

  function sortByRecent<T extends { updated_at?: unknown; created_at?: unknown }>(items: T[]): T[] {
    return [...items].sort((a, b) => {
      const aTime = parseTimestamp(a.updated_at) || parseTimestamp(a.created_at);
      const bTime = parseTimestamp(b.updated_at) || parseTimestamp(b.created_at);
      return bTime - aTime;
    });
  }

  function workflowNodes(workflow: WorkflowItem): Record<string, JsonObject> {
    return workflow.nodes && typeof workflow.nodes === "object" && !Array.isArray(workflow.nodes)
      ? workflow.nodes
      : {};
  }

  function workflowEdges(workflow: WorkflowItem): WorkflowEdge[] {
    return Array.isArray(workflow.edges)
      ? workflow.edges.filter((edge): edge is WorkflowEdge =>
        !!edge &&
        typeof edge === "object" &&
        typeof edge.from === "string" &&
        typeof edge.to === "string",
      )
      : [];
  }

  function formatDateLabel(value: unknown): string {
    const parsed = parseTimestamp(value);
    if (!parsed) return "--";
    return new Intl.DateTimeFormat(undefined, {
      month: "short",
      day: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    }).format(new Date(parsed));
  }

  function normalizeStatus(status: unknown): string {
    return typeof status === "string" && status.trim().length > 0 ? status.trim().toLowerCase() : "unknown";
  }

  function statusLabel(status: unknown): string {
    const normalized = normalizeStatus(status);
    switch (normalized) {
      case "pending":
      case "running":
      case "stopped":
      case "starting":
      case "stopping":
      case "completed":
      case "interrupted":
      case "cancelled":
      case "failed":
      case "restarting":
      case "unknown":
        return t(`status.${normalized}`);
      default:
        return normalized;
    }
  }

  function isActiveStatus(status: unknown): boolean {
    return ["pending", "running", "starting", "restarting"].includes(normalizeStatus(status));
  }

  function isFailedStatus(status: unknown): boolean {
    return ["failed", "interrupted", "cancelled"].includes(normalizeStatus(status));
  }

  function workflowNodeCount(workflow: WorkflowItem): number {
    return Object.keys(workflowNodes(workflow)).length;
  }

  function workflowEdgeCount(workflow: WorkflowItem): number {
    return workflowEdges(workflow).length;
  }

  function runWorkflowLabel(run: RunItem): string {
    if (run.workflow && typeof run.workflow === "object" && !Array.isArray(run.workflow)) {
      const workflow = run.workflow as JsonObject;
      const name = workflow.name;
      if (typeof name === "string" && name.trim()) return name;
      const id = workflow.id;
      if (typeof id === "string" && id.trim()) return id;
    }
    if (typeof run.workflow_id === "string" && run.workflow_id.trim()) return run.workflow_id;
    return t("orchestration.workflows");
  }

  function runStepCount(run: RunItem): number {
    return Array.isArray(run.steps) ? run.steps.length : 0;
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

      const [workflowItems, runItems] = await Promise.all([
        api.listWorkflows(),
        api.listRuns(),
      ]);
      workflows = Array.isArray(workflowItems) ? workflowItems as WorkflowItem[] : [];
      runs = Array.isArray(runItems) ? runItems as RunItem[] : [];
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

  const sortedWorkflows = $derived(sortByRecent(workflows));
  const sortedRuns = $derived(sortByRecent(runs));
  const activeRunCount = $derived(sortedRuns.filter((run) => isActiveStatus(run.status)).length);
  const failedRunCount = $derived(sortedRuns.filter((run) => isFailedStatus(run.status)).length);
  const recentRuns = $derived(sortedRuns.slice(0, 8));
  const workflowLibrary = $derived(sortedWorkflows.slice(0, 6));
  const featuredWorkflow = $derived.by(() => {
    const workflow = sortedWorkflows[0];
    if (!workflow) return null;
    return {
      id: workflow.id || workflow.name || "-",
      name: workflow.name || workflow.id || "-",
      nodes: workflowNodes(workflow),
      edges: workflowEdges(workflow),
      updatedAt: workflow.updated_at || workflow.created_at,
    };
  });
</script>

<svelte:head>
  <title>{t("orchestration.title")} - NullHubX</title>
</svelte:head>

<div class="page-shell orchestration-page">
  <section class="section-shell orchestration-hero">
    <div class="page-hero">
      <div class="page-title-group">
        <span class="page-kicker">NullBoiler / NullTickets</span>
        <h1 class="page-title">{t("orchestration.title")}</h1>
        <p class="page-subtitle">{t("orchestration.subtitle")}</p>
      </div>
      <div class="page-actions">
        <button class="control-btn secondary" onclick={load} disabled={loading}>
          {loading ? t("orchestration.refreshing") : t("orchestration.refresh")}
        </button>
      </div>
    </div>

    <div class="metrics-grid">
      <article class="metric-card">
        <span class="metric-label">{t("orchestration.workflowCount")}</span>
        <strong class="metric-value">{sortedWorkflows.length}</strong>
        <p class="metric-meta">{t("orchestration.latestWorkflowsDesc")}</p>
      </article>
      <article class="metric-card">
        <span class="metric-label">{t("orchestration.runCount")}</span>
        <strong class="metric-value">{sortedRuns.length}</strong>
        <p class="metric-meta">{t("orchestration.recentRunsDesc")}</p>
      </article>
      <article class="metric-card">
        <span class="metric-label">{t("orchestration.activeRuns")}</span>
        <strong class="metric-value">{activeRunCount}</strong>
        <p class="metric-meta">{t("status.running")}</p>
      </article>
      <article class="metric-card">
        <span class="metric-label">{t("orchestration.failedRuns")}</span>
        <strong class="metric-value">{failedRunCount}</strong>
        <p class="metric-meta">{t("status.failed")}</p>
      </article>
    </div>
  </section>

  {#if error}
    <section class="section-shell unavailable-shell">
      <div class="section-heading">
        <span class="section-kicker">{t("orchestration.unavailable")}</span>
        <h2 class="section-title">{t("orchestration.title")}</h2>
        <p class="section-subtitle">{error}</p>
      </div>
      <p class="unavailable-hint">{t("orchestration.hint")}</p>
    </section>
  {:else}
    <div class="orchestration-grid">
      <section class="section-shell cyber-shell graph-panel">
        <div class="section-heading-row">
          <div class="section-heading">
            <span class="section-kicker">{t("orchestration.graphPreview")}</span>
            <h2 class="section-title">{t("orchestration.workflows")}</h2>
            <p class="section-subtitle">{t("orchestration.graphPreviewDesc")}</p>
          </div>
        </div>

        {#if featuredWorkflow}
          <div class="workflow-spotlight">
            <div class="workflow-topline">
              <div>
                <strong class="workflow-name">{featuredWorkflow.name}</strong>
                <p class="workflow-id">{featuredWorkflow.id}</p>
              </div>
              <div class="workflow-chips">
                <span class="cyber-chip">{Object.keys(featuredWorkflow.nodes).length} {t("orchestration.nodes")}</span>
                <span class="cyber-chip">{featuredWorkflow.edges.length} {t("orchestration.edges")}</span>
                <span class="cyber-chip">{formatDateLabel(featuredWorkflow.updatedAt)}</span>
              </div>
            </div>

            <div class="graph-stage">
              <GraphViewer workflow={{ nodes: featuredWorkflow.nodes, edges: featuredWorkflow.edges }} nodeStatus={{}} />
            </div>
          </div>
        {:else}
          <div class="empty-panel orchestration-empty">{t("orchestration.workflowEmpty")}</div>
        {/if}
      </section>

      <section class="section-shell cyber-shell run-panel">
        <div class="section-heading-row">
          <div class="section-heading">
            <span class="section-kicker">{t("orchestration.recentRuns")}</span>
            <h2 class="section-title">{t("orchestration.runs")}</h2>
            <p class="section-subtitle">{t("orchestration.recentRunsDesc")}</p>
          </div>
        </div>

        {#if recentRuns.length === 0}
          <div class="empty-panel orchestration-empty">{t("orchestration.runsEmpty")}</div>
        {:else}
          <div class="run-timeline">
            {#each recentRuns as run}
              <article class="run-card" class:active={isActiveStatus(run.status)} class:failed={isFailedStatus(run.status)}>
                <div class="run-rail">
                  <span class="run-dot"></span>
                </div>
                <div class="run-body">
                  <div class="run-header">
                    <strong>{run.id || "-"}</strong>
                    <span class="run-status">{statusLabel(run.status)}</span>
                  </div>
                  <p class="run-workflow">{runWorkflowLabel(run)}</p>
                  <div class="run-meta">
                    <span>{t("orchestration.lastUpdated")} {formatDateLabel(run.updated_at || run.created_at)}</span>
                    <span>{runStepCount(run)} {t("orchestration.steps")}</span>
                  </div>
                </div>
              </article>
            {/each}
          </div>
        {/if}
      </section>
    </div>

    <section class="section-shell cyber-shell workflow-library-shell">
      <div class="section-heading-row">
        <div class="section-heading">
          <span class="section-kicker">{t("orchestration.latestWorkflows")}</span>
          <h2 class="section-title">{t("orchestration.workflows")}</h2>
          <p class="section-subtitle">{t("orchestration.latestWorkflowsDesc")}</p>
        </div>
      </div>

      {#if workflowLibrary.length === 0}
        <div class="empty-panel orchestration-empty">{t("orchestration.workflowEmpty")}</div>
      {:else}
        <div class="workflow-list">
          {#each workflowLibrary as workflow}
            <article class="workflow-card">
              <div class="workflow-card-head">
                <strong>{workflow.name || workflow.id || "-"}</strong>
                <span class="workflow-card-id">{workflow.id || "-"}</span>
              </div>
              <p class="workflow-card-time">{t("orchestration.lastUpdated")} {formatDateLabel(workflow.updated_at || workflow.created_at)}</p>
              <div class="workflow-card-stats">
                <div class="workflow-stat">
                  <span>{t("orchestration.nodes")}</span>
                  <strong>{workflowNodeCount(workflow)}</strong>
                </div>
                <div class="workflow-stat">
                  <span>{t("orchestration.edges")}</span>
                  <strong>{workflowEdgeCount(workflow)}</strong>
                </div>
              </div>
            </article>
          {/each}
        </div>
      {/if}
    </section>
  {/if}
</div>

<style>
  .orchestration-page {
    gap: var(--spacing-xl);
  }

  .orchestration-hero {
    background:
      linear-gradient(135deg, rgba(9, 15, 28, 0.98), rgba(10, 18, 34, 0.96), rgba(14, 45, 74, 0.92)),
      radial-gradient(circle at top right, rgba(34, 211, 238, 0.2), transparent 34%);
    border-color: rgba(34, 211, 238, 0.14);
    box-shadow:
      inset 0 1px 0 rgba(255, 255, 255, 0.04),
      0 30px 80px rgba(2, 8, 23, 0.34);
  }

  .orchestration-hero .page-title {
    color: var(--shell-text);
  }

  .orchestration-hero .page-subtitle {
    color: rgba(191, 219, 254, 0.78);
  }

  .orchestration-hero .metric-card {
    border-color: rgba(96, 165, 250, 0.14);
    background: linear-gradient(180deg, rgba(11, 19, 34, 0.86), rgba(14, 24, 42, 0.76));
    box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.03);
  }

  .orchestration-hero .metric-label,
  .orchestration-hero .metric-meta {
    color: rgba(191, 219, 254, 0.68);
  }

  .orchestration-hero .metric-value {
    color: var(--shell-text);
  }

  .orchestration-grid {
    display: grid;
    grid-template-columns: minmax(0, 1.4fr) minmax(320px, 0.9fr);
    gap: var(--spacing-lg);
  }

  .cyber-shell {
    background:
      linear-gradient(180deg, rgba(8, 13, 24, 0.96), rgba(11, 18, 32, 0.92)),
      radial-gradient(circle at top right, rgba(34, 211, 238, 0.08), transparent 38%);
    border-color: rgba(96, 165, 250, 0.14);
    box-shadow:
      inset 0 1px 0 rgba(255, 255, 255, 0.03),
      0 20px 54px rgba(2, 8, 23, 0.26);
  }

  .cyber-shell .section-title {
    color: var(--shell-text);
  }

  .cyber-shell .section-subtitle {
    color: rgba(191, 219, 254, 0.72);
  }

  .workflow-spotlight,
  .run-timeline {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-md);
  }

  .workflow-topline {
    display: flex;
    justify-content: space-between;
    gap: var(--spacing-lg);
    align-items: flex-start;
    flex-wrap: wrap;
  }

  .workflow-name {
    display: block;
    color: var(--shell-text);
    font-size: 1.05rem;
  }

  .workflow-id {
    margin: 0.35rem 0 0;
    color: rgba(191, 219, 254, 0.68);
    font-family: var(--font-mono);
    font-size: 0.76rem;
  }

  .workflow-chips {
    display: flex;
    flex-wrap: wrap;
    justify-content: flex-end;
    gap: 0.45rem;
  }

  .cyber-chip {
    display: inline-flex;
    align-items: center;
    padding: 0.35rem 0.6rem;
    border-radius: 999px;
    border: 1px solid rgba(34, 211, 238, 0.18);
    background: rgba(12, 20, 35, 0.82);
    color: rgba(165, 243, 252, 0.88);
    font-family: var(--font-mono);
    font-size: 0.7rem;
    letter-spacing: 0.06em;
    text-transform: uppercase;
  }

  .graph-stage {
    min-height: 420px;
  }

  .run-timeline {
    position: relative;
  }

  .run-card {
    display: grid;
    grid-template-columns: 20px minmax(0, 1fr);
    gap: 0.9rem;
    padding: 0.9rem 1rem;
    border-radius: var(--radius-lg);
    border: 1px solid rgba(96, 165, 250, 0.12);
    background: rgba(12, 20, 35, 0.78);
    transition:
      transform var(--transition-fast),
      border-color var(--transition-fast),
      box-shadow var(--transition-fast);
  }

  .run-card:hover {
    transform: translateY(-1px);
    border-color: rgba(34, 211, 238, 0.2);
    box-shadow: 0 18px 40px rgba(2, 8, 23, 0.28);
  }

  .run-card.active {
    border-color: rgba(34, 211, 238, 0.22);
  }

  .run-card.failed {
    border-color: rgba(244, 63, 94, 0.22);
  }

  .run-rail {
    position: relative;
    display: flex;
    justify-content: center;
  }

  .run-rail::before {
    content: "";
    position: absolute;
    top: 0.2rem;
    bottom: -1.1rem;
    width: 2px;
    background: linear-gradient(180deg, rgba(34, 211, 238, 0.26), rgba(59, 130, 246, 0));
  }

  .run-card:last-child .run-rail::before {
    display: none;
  }

  .run-dot {
    position: relative;
    z-index: 1;
    width: 10px;
    height: 10px;
    margin-top: 0.25rem;
    border-radius: 999px;
    background: var(--cyan-300);
    box-shadow: 0 0 0 4px rgba(34, 211, 238, 0.14);
  }

  .run-card.failed .run-dot {
    background: #fb7185;
    box-shadow: 0 0 0 4px rgba(244, 63, 94, 0.14);
  }

  .run-body {
    display: flex;
    flex-direction: column;
    gap: 0.45rem;
    min-width: 0;
  }

  .run-header {
    display: flex;
    justify-content: space-between;
    gap: var(--spacing-md);
    align-items: center;
  }

  .run-header strong {
    color: var(--shell-text);
    font-family: var(--font-mono);
    font-size: 0.82rem;
    overflow-wrap: anywhere;
  }

  .run-status {
    padding: 0.3rem 0.55rem;
    border-radius: 999px;
    border: 1px solid rgba(34, 211, 238, 0.16);
    background: rgba(15, 23, 42, 0.76);
    color: rgba(165, 243, 252, 0.86);
    font-family: var(--font-mono);
    font-size: 0.68rem;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    white-space: nowrap;
  }

  .run-card.failed .run-status {
    border-color: rgba(244, 63, 94, 0.2);
    color: #fda4af;
  }

  .run-workflow,
  .workflow-card-time,
  .unavailable-hint {
    margin: 0;
    color: rgba(191, 219, 254, 0.74);
    font-size: var(--text-sm);
    line-height: 1.65;
  }

  .run-meta {
    display: flex;
    flex-wrap: wrap;
    gap: 0.4rem 0.9rem;
    color: rgba(148, 163, 184, 0.88);
    font-size: 0.74rem;
    font-family: var(--font-mono);
  }

  .workflow-list {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
    gap: var(--spacing-md);
  }

  .workflow-card {
    display: flex;
    flex-direction: column;
    gap: 0.85rem;
    padding: 1rem;
    border-radius: var(--radius-lg);
    border: 1px solid rgba(96, 165, 250, 0.12);
    background: rgba(12, 20, 35, 0.78);
  }

  .workflow-card-head {
    display: flex;
    flex-direction: column;
    gap: 0.35rem;
  }

  .workflow-card-head strong {
    color: var(--shell-text);
    font-size: 0.95rem;
  }

  .workflow-card-id {
    color: rgba(148, 163, 184, 0.86);
    font-family: var(--font-mono);
    font-size: 0.72rem;
    overflow-wrap: anywhere;
  }

  .workflow-card-stats {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 0.75rem;
  }

  .workflow-stat {
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
    padding: 0.75rem 0.85rem;
    border-radius: var(--radius-md);
    border: 1px solid rgba(96, 165, 250, 0.12);
    background: rgba(8, 13, 24, 0.74);
  }

  .workflow-stat span {
    color: rgba(191, 219, 254, 0.7);
    font-size: 0.72rem;
    text-transform: uppercase;
    letter-spacing: 0.08em;
  }

  .workflow-stat strong {
    color: var(--shell-text);
    font-size: 1rem;
  }

  .orchestration-empty {
    background: rgba(12, 20, 35, 0.68);
    border-color: rgba(96, 165, 250, 0.16);
    color: rgba(191, 219, 254, 0.74);
  }

  .unavailable-shell {
    border-color: rgba(245, 158, 11, 0.2);
    background: linear-gradient(180deg, rgba(255, 251, 235, 0.9), rgba(255, 247, 237, 0.84));
  }

  @media (max-width: 1040px) {
    .orchestration-grid {
      grid-template-columns: 1fr;
    }
  }

  @media (max-width: 760px) {
    .workflow-topline,
    .run-header {
      flex-direction: column;
      align-items: flex-start;
    }

    .workflow-chips {
      justify-content: flex-start;
    }

    .graph-stage {
      min-height: 320px;
    }
  }
</style>
