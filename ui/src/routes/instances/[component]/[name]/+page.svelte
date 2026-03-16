<script lang="ts">
  import { page } from "$app/stores";
  import { api } from "$lib/api/client";
  import ConfigEditor from "$lib/components/ConfigEditor.svelte";
  import LogViewer from "$lib/components/LogViewer.svelte";
  import InstanceHistoryPanel from "$lib/components/InstanceHistoryPanel.svelte";
  import InstanceMemoryPanel from "$lib/components/InstanceMemoryPanel.svelte";
  import InstanceSkillsPanel from "$lib/components/InstanceSkillsPanel.svelte";

  type TabKey = "overview" | "config" | "logs" | "history" | "memory" | "skills";

  let component = $derived($page.params.component);
  let name = $derived($page.params.name);

  let activeTab = $state<TabKey>("overview");
  let busyAction = $state<"start" | "stop" | "restart" | "update" | null>(null);

  let instanceStatus = $state<any>(null);
  let providerHealth = $state<any>(null);
  let onboarding = $state<any>(null);
  let loadError = $state("");

  const tabs: { key: TabKey; label: string }[] = [
    { key: "overview", label: "Overview" },
    { key: "config", label: "Config" },
    { key: "logs", label: "Logs" },
    { key: "history", label: "History" },
    { key: "memory", label: "Memory" },
    { key: "skills", label: "Skills" },
  ];

  const statusText = $derived(instanceStatus?.status || "unknown");
  const running = $derived(statusText === "running" || statusText === "starting" || statusText === "restarting");

  function normalizeError(err: unknown): string {
    return err instanceof Error ? err.message : "Request failed";
  }

  async function loadSummary() {
    loadError = "";
    try {
      const status = await api.getStatus();
      const inst = status?.instances?.[component]?.[name] || null;
      instanceStatus = inst;

      if (!inst) {
        providerHealth = null;
        onboarding = null;
        return;
      }

      const [healthRes, onboardingRes] = await Promise.allSettled([
        api.getProviderHealth(component, name),
        api.getOnboarding(component, name),
      ]);

      providerHealth = healthRes.status === "fulfilled" ? healthRes.value : null;
      onboarding = onboardingRes.status === "fulfilled" ? onboardingRes.value : null;
    } catch (err) {
      instanceStatus = null;
      providerHealth = null;
      onboarding = null;
      loadError = normalizeError(err);
    }
  }

  async function runAction(action: "start" | "stop" | "restart" | "update") {
    busyAction = action;
    try {
      if (action === "start") await api.startInstance(component, name);
      if (action === "stop") await api.stopInstance(component, name);
      if (action === "restart") await api.restartInstance(component, name);
      if (action === "update") await api.applyUpdate(component, name);
      await loadSummary();
    } catch (err) {
      loadError = normalizeError(err);
    } finally {
      busyAction = null;
    }
  }

  $effect(() => {
    component;
    name;
    activeTab = "overview";
    void loadSummary();
  });
</script>

<svelte:head>
  <title>{component}/{name} - NullHubX</title>
</svelte:head>

<div class="page">
  <header class="page-header">
    <div>
      <a class="back-link" href="/">← Back to Dashboard</a>
      <h1>{component}/{name}</h1>
      <p class="subtitle">Instance detail, config, logs, and runtime tooling.</p>
    </div>
    <div class="actions">
      <button onclick={() => runAction("start")} disabled={busyAction !== null || running}> {busyAction === "start" ? "Starting..." : "Start"} </button>
      <button onclick={() => runAction("stop")} disabled={busyAction !== null || !running}> {busyAction === "stop" ? "Stopping..." : "Stop"} </button>
      <button onclick={() => runAction("restart")} disabled={busyAction !== null}> {busyAction === "restart" ? "Restarting..." : "Restart"} </button>
      <button onclick={() => runAction("update")} disabled={busyAction !== null}> {busyAction === "update" ? "Updating..." : "Update"} </button>
    </div>
  </header>

  {#if loadError}
    <div class="error">{loadError}</div>
  {/if}

  {#if !instanceStatus}
    <div class="empty">Instance not found in current status snapshot.</div>
  {:else}
    <div class="summary-grid">
      <div class="summary-card">
        <span class="label">Status</span>
        <strong>{statusText}</strong>
      </div>
      <div class="summary-card">
        <span class="label">Version</span>
        <strong>{instanceStatus.version || "-"}</strong>
      </div>
      <div class="summary-card">
        <span class="label">Port</span>
        <strong>{instanceStatus.port || "-"}</strong>
      </div>
      <div class="summary-card">
        <span class="label">Provider Health</span>
        <strong>{providerHealth?.status || "unknown"}</strong>
      </div>
      <div class="summary-card">
        <span class="label">Onboarding</span>
        <strong>{onboarding?.pending ? "pending" : onboarding?.completed ? "completed" : "unknown"}</strong>
      </div>
    </div>

    <nav class="tabs">
      {#each tabs as tab}
        <button class:active={activeTab === tab.key} onclick={() => (activeTab = tab.key)}>{tab.label}</button>
      {/each}
    </nav>

    <section class="panel">
      {#if activeTab === "overview"}
        <div class="overview-grid">
          <div>
            <h3>Runtime</h3>
            <pre>{JSON.stringify(instanceStatus, null, 2)}</pre>
          </div>
          <div>
            <h3>Provider Health</h3>
            <pre>{JSON.stringify(providerHealth || {}, null, 2)}</pre>
          </div>
          <div>
            <h3>Onboarding</h3>
            <pre>{JSON.stringify(onboarding || {}, null, 2)}</pre>
          </div>
        </div>
      {/if}

      {#if activeTab === "config"}
        <ConfigEditor {component} {name} onAction={loadSummary} />
      {/if}

      {#if activeTab === "logs"}
        <LogViewer {component} {name} />
      {/if}

      {#if activeTab === "history"}
        <InstanceHistoryPanel {component} {name} active={activeTab === "history"} />
      {/if}

      {#if activeTab === "memory"}
        <InstanceMemoryPanel {component} {name} active={activeTab === "memory"} />
      {/if}

      {#if activeTab === "skills"}
        <InstanceSkillsPanel {component} {name} active={activeTab === "skills"} />
      {/if}
    </section>
  {/if}
</div>

<style>
  .page {
    padding: var(--spacing-2xl);
    max-width: 1400px;
    margin: 0 auto;
  }
  .page-header {
    display: flex;
    justify-content: space-between;
    gap: 1rem;
    align-items: flex-start;
    margin-bottom: var(--spacing-lg);
  }
  h1 {
    margin: 0.25rem 0;
    font-family: var(--font-mono);
    font-size: var(--text-2xl);
  }
  .subtitle {
    margin: 0;
    color: var(--slate-500);
  }
  .back-link {
    color: var(--slate-500);
    text-decoration: none;
    font-size: var(--text-sm);
  }
  .actions {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
  }
  .actions button {
    border: 1px solid var(--slate-300);
    background: white;
    color: var(--slate-800);
    padding: 0.5rem 0.9rem;
    border-radius: 8px;
    cursor: pointer;
  }
  .actions button:disabled {
    opacity: 0.55;
    cursor: not-allowed;
  }
  .error {
    margin-bottom: 1rem;
    padding: 0.75rem 1rem;
    border: 1px solid var(--red-200);
    background: var(--red-50);
    color: var(--red-600);
    border-radius: 8px;
  }
  .empty {
    padding: 2rem;
    border: 1px dashed var(--slate-300);
    border-radius: 10px;
    color: var(--slate-500);
  }
  .summary-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(170px, 1fr));
    gap: 0.75rem;
    margin-bottom: 1rem;
  }
  .summary-card {
    border: 1px solid var(--slate-200);
    border-radius: 8px;
    background: white;
    padding: 0.7rem 0.9rem;
    display: flex;
    flex-direction: column;
    gap: 0.25rem;
  }
  .summary-card .label {
    font-size: var(--text-xs);
    color: var(--slate-500);
    text-transform: uppercase;
    letter-spacing: 0.4px;
  }
  .tabs {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
    margin-bottom: 1rem;
  }
  .tabs button {
    border: 1px solid var(--slate-200);
    background: white;
    border-radius: 999px;
    padding: 0.4rem 0.8rem;
    cursor: pointer;
    color: var(--slate-600);
  }
  .tabs button.active {
    border-color: var(--indigo-500);
    color: var(--indigo-700);
    background: var(--indigo-50);
  }
  .panel {
    border: 1px solid var(--slate-200);
    border-radius: 10px;
    background: white;
    padding: 1rem;
  }
  .overview-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
    gap: 0.9rem;
  }
  pre {
    margin: 0;
    border: 1px solid var(--slate-200);
    background: var(--slate-50);
    border-radius: 8px;
    padding: 0.75rem;
    max-height: 320px;
    overflow: auto;
    font-size: 12px;
  }
  @media (max-width: 900px) {
    .page-header {
      flex-direction: column;
    }
  }
</style>
