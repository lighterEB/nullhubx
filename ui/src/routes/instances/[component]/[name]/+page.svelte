<script lang="ts">
  import { page } from "$app/stores";
  import { goto } from "$app/navigation";
  import { api } from "$lib/api/client";
  import ConfigEditor from "$lib/components/ConfigEditor.svelte";
  import LogViewer from "$lib/components/LogViewer.svelte";
  import InstanceHistoryPanel from "$lib/components/InstanceHistoryPanel.svelte";
  import InstanceMemoryPanel from "$lib/components/InstanceMemoryPanel.svelte";
  import InstanceSkillsPanel from "$lib/components/InstanceSkillsPanel.svelte";
  import InstanceAgentsPanel from "$lib/components/InstanceAgentsPanel.svelte";

  type TabKey = "overview" | "config" | "agents" | "logs" | "history" | "memory" | "skills";

  let component = $derived($page.params.component);
  let name = $derived($page.params.name);

  let activeTab = $state<TabKey>("overview");
  let busyAction = $state<"start" | "stop" | "restart" | "update" | "delete" | null>(null);

  let instanceStatus = $state<any>(null);
  let providerHealth = $state<any>(null);
  let onboarding = $state<any>(null);
  let agentProfilesCount = $state<number | null>(null);
  let agentBindingsCount = $state<number | null>(null);
  let loadError = $state("");

  const tabs: { key: TabKey; label: string }[] = [
    { key: "overview", label: "总览" },
    { key: "config", label: "配置" },
    { key: "agents", label: "代理" },
    { key: "logs", label: "日志" },
    { key: "history", label: "历史" },
    { key: "memory", label: "记忆" },
    { key: "skills", label: "技能" },
  ];

  const statusText = $derived(instanceStatus?.status || "unknown");
  const statusLabel = $derived(
    ({
      running: "运行中",
      stopped: "已停止",
      starting: "启动中",
      stopping: "停止中",
      failed: "失败",
      restarting: "重启中",
    } as Record<string, string>)[statusText] || statusText,
  );
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
        agentProfilesCount = null;
        agentBindingsCount = null;
        return;
      }

      const [healthRes, onboardingRes, profilesRes, bindingsRes] = await Promise.allSettled([
        api.getProviderHealth(component, name),
        api.getOnboarding(component, name),
        api.getAgentProfiles(component, name),
        api.getAgentBindings(component, name),
      ]);

      providerHealth = healthRes.status === "fulfilled" ? healthRes.value : null;
      onboarding = onboardingRes.status === "fulfilled" ? onboardingRes.value : null;
      agentProfilesCount =
        profilesRes.status === "fulfilled" && Array.isArray(profilesRes.value?.profiles)
          ? profilesRes.value.profiles.length
          : null;
      agentBindingsCount =
        bindingsRes.status === "fulfilled" && Array.isArray(bindingsRes.value?.bindings)
          ? bindingsRes.value.bindings.length
          : null;
    } catch (err) {
      instanceStatus = null;
      providerHealth = null;
      onboarding = null;
      agentProfilesCount = null;
      agentBindingsCount = null;
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

  async function runDelete() {
    if (!confirm(`确认删除实例 ${component}/${name} 吗？此操作不可撤销。`)) return;
    busyAction = "delete";
    try {
      await api.deleteInstance(component, name);
      await goto("/");
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
      <a class="back-link" href="/">← 返回仪表盘</a>
      <h1>{component}/{name}</h1>
      <p class="subtitle">实例详情、配置、日志与运行状态管理。</p>
    </div>
    <div class="actions">
      <button class="btn-action btn-start" onclick={() => runAction("start")} disabled={busyAction !== null || running}>
        {busyAction === "start" ? "启动中..." : "启动"}
      </button>
      <button class="btn-action btn-stop" onclick={() => runAction("stop")} disabled={busyAction !== null || !running}>
        {busyAction === "stop" ? "停止中..." : "停止"}
      </button>
      <button class="btn-action btn-restart" onclick={() => runAction("restart")} disabled={busyAction !== null}>
        {busyAction === "restart" ? "重启中..." : "重启"}
      </button>
      <button class="btn-action btn-update" onclick={() => runAction("update")} disabled={busyAction !== null}>
        {busyAction === "update" ? "更新中..." : "更新"}
      </button>
      <button class="btn-action btn-delete" onclick={runDelete} disabled={busyAction !== null}>
        {busyAction === "delete" ? "删除中..." : "删除"}
      </button>
    </div>
  </header>

  {#if loadError}
    <div class="error">{loadError}</div>
  {/if}

  {#if !instanceStatus}
    <div class="empty">当前状态快照中未找到该实例。</div>
  {:else}
    <div class="summary-grid">
      <div class="summary-card">
        <span class="label">状态</span>
        <strong>{statusLabel}</strong>
      </div>
      <div class="summary-card">
        <span class="label">版本</span>
        <strong>{instanceStatus.version || "-"}</strong>
      </div>
      <div class="summary-card">
        <span class="label">端口</span>
        <strong>{instanceStatus.port || "-"}</strong>
      </div>
      <div class="summary-card">
        <span class="label">Provider 健康</span>
        <strong>{providerHealth?.status || "未知"}</strong>
      </div>
      <div class="summary-card">
        <span class="label">引导状态</span>
        <strong>{onboarding?.pending ? "待完成" : onboarding?.completed ? "已完成" : "未知"}</strong>
      </div>
      <div class="summary-card">
        <span class="label">代理 Profiles</span>
        <strong>{agentProfilesCount ?? "-"}</strong>
      </div>
      <div class="summary-card">
        <span class="label">代理 Bindings</span>
        <strong>{agentBindingsCount ?? "-"}</strong>
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
            <h3>运行状态</h3>
            <pre>{JSON.stringify(instanceStatus, null, 2)}</pre>
          </div>
          <div>
            <h3>Provider 健康</h3>
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

      {#if activeTab === "agents"}
        <InstanceAgentsPanel {component} {name} active={activeTab === "agents"} />
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
  .btn-action {
    border: 1px solid transparent;
    padding: 0.5rem 0.9rem;
    border-radius: 8px;
    cursor: pointer;
    font-weight: 600;
    letter-spacing: 0.5px;
    transition: all 0.2s ease;
  }
  .btn-start {
    background: var(--emerald-600);
    color: white;
  }
  .btn-start:hover:not(:disabled) {
    background: var(--emerald-700);
  }
  .btn-stop {
    background: var(--red-600);
    color: white;
  }
  .btn-stop:hover:not(:disabled) {
    background: var(--red-700);
  }
  .btn-restart {
    background: var(--amber-500);
    color: var(--slate-800);
  }
  .btn-restart:hover:not(:disabled) {
    background: var(--amber-600);
    color: white;
  }
  .btn-update {
    background: var(--indigo-600);
    color: white;
  }
  .btn-update:hover:not(:disabled) {
    background: var(--indigo-700);
  }
  .btn-delete {
    background: white;
    color: var(--red-600);
    border-color: var(--red-300);
  }
  .btn-delete:hover:not(:disabled) {
    background: var(--red-50);
    border-color: var(--red-500);
  }
  .btn-action:disabled {
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
    letter-spacing: 0.2px;
  }
  .tabs {
    display: flex;
    flex-wrap: wrap;
    gap: var(--spacing-xl);
    margin-bottom: 1rem;
    border-bottom: 1px solid var(--slate-200);
  }
  .tabs button {
    border: none;
    background: transparent;
    padding: var(--spacing-md) 0;
    cursor: pointer;
    color: var(--slate-400);
    border-bottom: 2px solid transparent;
    font-family: var(--font-mono);
    font-size: var(--text-sm);
    letter-spacing: 0.5px;
    transition: all var(--transition-fast);
  }
  .tabs button:hover {
    color: var(--slate-600);
  }
  .tabs button.active {
    border-bottom-color: var(--indigo-600);
    color: var(--indigo-600);
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

    .actions {
      width: 100%;
    }

    .btn-action {
      flex: 1 1 calc(50% - 0.5rem);
    }
  }

  @media (max-width: 640px) {
    .page {
      padding: var(--spacing-lg);
    }

    .summary-grid {
      grid-template-columns: 1fr;
    }

    .tabs {
      gap: var(--spacing-md);
      overflow-x: auto;
      scrollbar-width: none;
    }

    .tabs::-webkit-scrollbar {
      display: none;
    }
  }
</style>
