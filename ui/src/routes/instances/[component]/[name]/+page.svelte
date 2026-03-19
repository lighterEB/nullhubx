<script lang="ts">
  import { goto } from "$app/navigation";
  import { page } from "$app/stores";
  import { onMount, onDestroy } from "svelte";
  import { api } from "$lib/api/client";
  import type { LogSource } from "$lib/api/client";
  import ConfigEditor from "$lib/components/ConfigEditor.svelte";
  import LogViewer from "$lib/components/LogViewer.svelte";
  import InstanceHistoryPanel from "$lib/components/InstanceHistoryPanel.svelte";
  import InstanceMemoryPanel from "$lib/components/InstanceMemoryPanel.svelte";
  import InstanceSkillsPanel from "$lib/components/InstanceSkillsPanel.svelte";
  import InstanceAgentsPanel from "$lib/components/InstanceAgentsPanel.svelte";

  type TabKey =
    | "overview"
    | "agents"
    | "config"
    | "logs"
    | "usage"
    | "history"
    | "memory"
    | "skills"
    | "integration";

  type LaunchAction = "start" | "restart";

  let component = $derived($page.params.component);
  let name = $derived($page.params.name);
  let isValidInstance = $derived(Boolean(component && name));

  let activeTab = $state<TabKey>("overview");
  let busyAction = $state<"start" | "stop" | "restart" | "update" | "delete" | null>(null);
  let savingDefaults = $state(false);

  let instanceStatus = $state<any>(null);
  let providerHealth = $state<any>(null);
  let onboarding = $state<any>(null);
  let usage = $state<any>(null);
  let integration = $state<any>(null);
  let agentProfilesCount = $state<number | null>(null);
  let agentBindingsCount = $state<number | null>(null);
  let instanceMissing = $state(false);
  let loadError = $state("");
  let pollTimer: ReturnType<typeof setInterval> | null = null;
  let summaryRequestToken = $state(0);
  let activeRouteKey = $state("");
  let summaryBusy = $state(false);
  let pendingInteractiveRefresh = $state(false);

  let defaultsAutoStart = $state(false);
  let defaultsLaunchMode = $state("gateway");
  let defaultsVerbose = $state(false);
  let defaultsDirty = $state(false);

  let recentSupervisorError = $state("");
  let healthFailuresFromLogs = $state<number | null>(null);

  let launchDialogOpen = $state(false);
  let launchAction = $state<LaunchAction>("start");
  let launchMode = $state("gateway");
  let launchVerbose = $state(false);
  let launchPersistDefaults = $state(false);

  let logInitialSource = $state<LogSource>("instance");
  let logViewerKey = $state(0);

  const tabs: { key: TabKey; label: string }[] = [
    { key: "overview", label: "总览" },
    { key: "agents", label: "代理" },
    { key: "config", label: "配置" },
    { key: "logs", label: "日志" },
    { key: "usage", label: "用量" },
    { key: "history", label: "历史" },
    { key: "memory", label: "记忆" },
    { key: "skills", label: "技能" },
    { key: "integration", label: "集成" },
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

  const canStart = $derived(statusText === "stopped" || statusText === "failed");
  const canStop = $derived(["starting", "running", "restarting"].includes(statusText));
  const canRestart = $derived(statusText === "running" || statusText === "failed");

  const restartCount = $derived(Number(instanceStatus?.restart_count || 0));
  const healthFailureCount = $derived(
    Number(instanceStatus?.health_consecutive_failures ?? healthFailuresFromLogs ?? 0),
  );
  const usageJson = $derived.by(() => JSON.stringify(usage || {}, null, 2));
  const integrationJson = $derived.by(() => JSON.stringify(integration || {}, null, 2));

  function normalizeError(err: unknown): string {
    return err instanceof Error ? err.message : "请求失败";
  }

  function resolveRouteRef(): { component: string; name: string } | null {
    const c = (component || "").trim();
    const n = (name || "").trim();
    if (c && n) return { component: c, name: n };

    if (typeof window !== "undefined") {
      const m = window.location.pathname.match(/^\/instances\/([^/]+)\/([^/]+)$/);
      if (m) {
        return {
          component: decodeURIComponent(m[1]),
          name: decodeURIComponent(m[2]),
        };
      }
    }
    return null;
  }

  function isNotFoundError(err: unknown): boolean {
    const message = normalizeError(err).toLowerCase();
    return (
      message.includes("404") ||
      message.includes("not found") ||
      message.includes("未找到")
    );
  }

  function readInstanceFromList(payload: any, targetComponent: string, targetName: string): any | null {
    return payload?.instances?.[targetComponent]?.[targetName] ?? null;
  }

  async function fetchInstanceSnapshot(targetComponent: string, targetName: string): Promise<any | null> {
    try {
      const detail = await api.getInstance(targetComponent, targetName);
      instanceMissing = false;
      return detail ?? null;
    } catch (err) {
      if (isNotFoundError(err)) {
        instanceMissing = true;
        return null;
      }

      // Fallback for mixed-version deployments where detail endpoint may be unavailable.
      const listPayload = await api.getInstances().catch(() => null);
      const fromList = readInstanceFromList(listPayload, targetComponent, targetName);
      if (fromList) {
        instanceMissing = false;
        return fromList;
      }
      throw err;
    }
  }

  function parseSupervisorDiagnostics(lines: string[]) {
    if (!Array.isArray(lines) || lines.length === 0) {
      return { latestFailure: "", healthFailures: null as number | null };
    }

    const reversed = [...lines].reverse();
    const latestFailure =
      reversed.find((line) =>
        /(failed|error|health check|restart budget|terminate|startup)/i.test(line),
      ) || "";

    for (const line of reversed) {
      const m1 = line.match(/consecutive failures:\s*(\d+)/i);
      if (m1) return { latestFailure, healthFailures: Number(m1[1]) };
      const m2 = line.match(/after\s*(\d+)\s*consecutive health failures/i);
      if (m2) return { latestFailure, healthFailures: Number(m2[1]) };
    }

    return { latestFailure, healthFailures: null as number | null };
  }

  async function withTimeout<T>(promise: Promise<T>, timeoutMs: number): Promise<T> {
    let timeoutId: ReturnType<typeof setTimeout> | null = null;
    const timeoutPromise = new Promise<never>((_, reject) => {
      timeoutId = setTimeout(() => reject(new Error(`请求超时（${Math.ceil(timeoutMs / 1000)}s）`)), timeoutMs);
    });
    try {
      return await Promise.race([promise, timeoutPromise]);
    } finally {
      if (timeoutId) clearTimeout(timeoutId);
    }
  }

  async function loadSummary(mode: "poll" | "interactive" = "poll") {
    if (summaryBusy) {
      if (mode === "interactive") pendingInteractiveRefresh = true;
      return;
    }

    const routeRef = resolveRouteRef();
    if (!routeRef) return;

    summaryBusy = true;
    const requestToken = summaryRequestToken + 1;
    summaryRequestToken = requestToken;
    loadError = "";
    const targetComponent = routeRef.component;
    const targetName = routeRef.name;

    try {
      const inst = await withTimeout(fetchInstanceSnapshot(targetComponent, targetName), 6000);
      if (requestToken !== summaryRequestToken) return;
      const current = resolveRouteRef();
      if (!current || targetComponent !== current.component || targetName !== current.name) return;

      if (!inst) {
        instanceStatus = null;
        providerHealth = null;
        onboarding = null;
        usage = null;
        integration = null;
        agentProfilesCount = null;
        agentBindingsCount = null;
        recentSupervisorError = "";
        healthFailuresFromLogs = null;
        return;
      }

      instanceStatus = {
        ...(instanceStatus || {}),
        ...inst,
      };

      const shouldFetchUsage = mode === "interactive" && activeTab === "usage";
      const shouldFetchIntegration = mode === "interactive" && activeTab === "integration";
      const AUX_TIMEOUT_MS = 6000;

      const [healthRes, onboardingRes, usageRes, integrationRes, profilesRes, bindingsRes, supervisorLogsRes] =
        await Promise.allSettled([
          withTimeout(api.getProviderHealth(targetComponent, targetName), AUX_TIMEOUT_MS),
          withTimeout(api.getOnboarding(targetComponent, targetName), AUX_TIMEOUT_MS),
          shouldFetchUsage
            ? withTimeout(api.getUsage(targetComponent, targetName, "all"), AUX_TIMEOUT_MS)
            : Promise.resolve(usage),
          shouldFetchIntegration
            ? withTimeout(api.getIntegration(targetComponent, targetName), AUX_TIMEOUT_MS)
            : Promise.resolve(integration),
          withTimeout(api.getAgentProfiles(targetComponent, targetName), AUX_TIMEOUT_MS),
          withTimeout(api.getAgentBindings(targetComponent, targetName), AUX_TIMEOUT_MS),
          withTimeout(api.getLogs(targetComponent, targetName, 120, "nullhubx"), AUX_TIMEOUT_MS),
        ]);
      if (requestToken !== summaryRequestToken) return;
      const latest = resolveRouteRef();
      if (!latest || targetComponent !== latest.component || targetName !== latest.name) return;

      providerHealth = healthRes.status === "fulfilled" ? healthRes.value : null;
      onboarding = onboardingRes.status === "fulfilled" ? onboardingRes.value : null;
      if (shouldFetchUsage) {
        usage = usageRes.status === "fulfilled" ? usageRes.value : null;
      }
      if (shouldFetchIntegration) {
        integration = integrationRes.status === "fulfilled" ? integrationRes.value : null;
      }
      agentProfilesCount =
        profilesRes.status === "fulfilled" && Array.isArray(profilesRes.value?.profiles)
          ? profilesRes.value.profiles.length
          : null;
      agentBindingsCount =
        bindingsRes.status === "fulfilled" && Array.isArray(bindingsRes.value?.bindings)
          ? bindingsRes.value.bindings.length
          : null;

      if (supervisorLogsRes.status === "fulfilled") {
        const diagnostics = parseSupervisorDiagnostics(supervisorLogsRes.value?.lines || []);
        recentSupervisorError = diagnostics.latestFailure;
        healthFailuresFromLogs = diagnostics.healthFailures;
      } else {
        // Keep the last known diagnostics on transient failures.
      }
    } catch (err) {
      if (requestToken !== summaryRequestToken) return;
      // Keep last known snapshot for resilience; only show error message.
      loadError = normalizeError(err);
    } finally {
      summaryBusy = false;
      if (pendingInteractiveRefresh) {
        pendingInteractiveRefresh = false;
        void loadSummary("interactive");
      }
    }
  }

  function startPolling() {
    if (pollTimer) clearInterval(pollTimer);
    pollTimer = setInterval(() => {
      void loadSummary("poll");
    }, 4000);
  }

  function stopPolling() {
    if (pollTimer) clearInterval(pollTimer);
    pollTimer = null;
  }

  async function runControlAction(action: "stop" | "update") {
    busyAction = action;
    try {
      if (action === "stop") await api.stopInstance(component, name);
      if (action === "update") await api.applyUpdate(component, name);
      await loadSummary("interactive");
    } catch (err) {
      loadError = normalizeError(err);
    } finally {
      busyAction = null;
    }
  }

  function openLaunchDialog(action: LaunchAction) {
    if (busyAction !== null) return; // Prevent duplicate clicks
    if (!instanceStatus) return;
    launchAction = action;
    launchMode = defaultsLaunchMode || instanceStatus.launch_mode || "gateway";
    launchVerbose = defaultsVerbose;
    launchPersistDefaults = false;
    launchDialogOpen = true;
  }

  function closeLaunchDialog() {
    if (busyAction === "start" || busyAction === "restart") return;
    launchDialogOpen = false;
  }

  function handleLaunchBackdropClick(event: MouseEvent) {
    if (event.target === event.currentTarget) closeLaunchDialog();
  }

  function handleLaunchBackdropKeydown(event: KeyboardEvent) {
    if (event.key === "Escape" || event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      closeLaunchDialog();
    }
  }

  async function confirmLaunchAction() {
    if (busyAction !== null) return;
    if (!instanceStatus) return;
    const mode = launchMode.trim();
    if (mode.length === 0) {
      loadError = "启动模式不能为空";
      return;
    }

    busyAction = launchAction;
    try {
      if (launchPersistDefaults) {
        await api.patchInstance(component, name, {
          launch_mode: mode,
          verbose: launchVerbose,
        });
        defaultsLaunchMode = mode;
        defaultsVerbose = launchVerbose;
        defaultsDirty = false;
      }

      if (launchAction === "start") {
        await api.startInstance(component, name, { launch_mode: mode, verbose: launchVerbose });
      } else {
        await api.restartInstance(component, name, { launch_mode: mode, verbose: launchVerbose });
      }
      launchDialogOpen = false;
      await loadSummary("interactive");
    } catch (err) {
      loadError = normalizeError(err);
    } finally {
      busyAction = null;
    }
  }

  async function saveDefaultSettings() {
    const mode = defaultsLaunchMode.trim();
    if (mode.length === 0) {
      loadError = "默认启动模式不能为空";
      return;
    }

    savingDefaults = true;
    try {
      await api.patchInstance(component, name, {
        auto_start: defaultsAutoStart,
        launch_mode: mode,
        verbose: defaultsVerbose,
      });
      defaultsDirty = false;
      await loadSummary("interactive");
    } catch (err) {
      loadError = normalizeError(err);
    } finally {
      savingDefaults = false;
    }
  }

  function resetDefaultSettingsDraft() {
    if (!instanceStatus) return;
    defaultsAutoStart = !!instanceStatus.auto_start;
    defaultsLaunchMode = instanceStatus.launch_mode || "gateway";
    defaultsVerbose = !!instanceStatus.verbose;
    defaultsDirty = false;
  }

  async function runDelete() {
    if (busyAction !== null) return;
    if (!confirm(`确认删除实例 ${component}/${name} 吗？此操作不可撤销。`)) return;
    busyAction = "delete";
    try {
      await api.deleteInstance(component, name);
      await goto("/instances");
    } catch (err) {
      loadError = normalizeError(err);
    } finally {
      busyAction = null;
    }
  }

  function openFailureLogs() {
    activeTab = "logs";
    logInitialSource = "nullhubx";
    logViewerKey += 1;
  }

  onMount(() => {
    startPolling();
  });

  onDestroy(() => {
    stopPolling();
    summaryRequestToken += 1;
  });

  $effect(() => {
    if (!component || !name) return;
    const routeKey = `${component}/${name}`;
    if (routeKey === activeRouteKey) return;
    activeRouteKey = routeKey;

    activeTab = "overview";
    launchDialogOpen = false;
    instanceMissing = false;
    loadError = "";
    logInitialSource = "instance";
    logViewerKey += 1;
    summaryRequestToken += 1;
    void loadSummary("interactive");
  });

  $effect(() => {
    instanceStatus;
    if (instanceStatus && !defaultsDirty) {
      defaultsAutoStart = !!instanceStatus.auto_start;
      defaultsLaunchMode = instanceStatus.launch_mode || "gateway";
      defaultsVerbose = !!instanceStatus.verbose;
    }
  });

  $effect(() => {
    activeTab;
    if (!instanceStatus) return;
    if (activeTab === "usage" || activeTab === "integration") {
      void loadSummary("interactive");
    }
  });
</script>

<svelte:head>
  <title>{component}/{name} - 实例详情 - NullHubX</title>
</svelte:head>

<div class="page">
  <header class="instance-header">
    <div class="header-left">
      <button class="back-link" type="button" onclick={() => goto("/instances")}>← 返回实例工作区</button>
      {#if isValidInstance}
        <h1>{component}/{name}</h1>
        <p class="subtitle">多代理实例详情与运行控制</p>
      {/if}
    </div>
    <div class="actions">
      <button
        class="btn-action btn-start"
        onclick={() => openLaunchDialog("start")}
        disabled={busyAction !== null || !canStart || !instanceStatus}
      >
        {busyAction === "start" ? "启动中..." : "启动"}
      </button>
      <button
        class="btn-action btn-stop"
        onclick={() => runControlAction("stop")}
        disabled={busyAction !== null || !canStop || !instanceStatus}
      >
        {busyAction === "stop" ? "停止中..." : "停止"}
      </button>
      <button
        class="btn-action btn-restart"
        onclick={() => openLaunchDialog("restart")}
        disabled={busyAction !== null || !canRestart || !instanceStatus}
      >
        {busyAction === "restart" ? "重启中..." : "重启"}
      </button>
      <button class="btn-action btn-update" onclick={() => runControlAction("update")} disabled={busyAction !== null || !instanceStatus}>
        {busyAction === "update" ? "更新中..." : "更新"}
      </button>
      <button class="btn-action btn-delete" onclick={runDelete} disabled={busyAction !== null || !instanceStatus}>
        {busyAction === "delete" ? "删除中..." : "删除"}
      </button>
    </div>
  </header>

  {#if statusText === "failed"}
    <div class="failed-banner">
      <div>
        <h3>实例处于失败状态</h3>
        <p>建议先查看 NullHubX 监控日志，再决定重启或修改配置。</p>
        {#if recentSupervisorError}
          <p class="failed-detail">{recentSupervisorError}</p>
        {/if}
      </div>
      <button class="failed-log-btn" onclick={openFailureLogs}>查看故障日志</button>
    </div>
  {/if}

  {#if loadError}
    <div class="error">{loadError}</div>
  {/if}

  {#if !instanceStatus}
    <div class="empty">
      {#if instanceMissing}
        当前状态快照中未找到该实例。
      {:else}
        正在获取实例状态，请稍候。
      {/if}
      <div class="empty-actions">
        <button class="empty-btn" type="button" onclick={() => goto("/instances")}>返回实例工作区</button>
        <button class="empty-btn" type="button" onclick={() => goto("/")}>返回总览</button>
        <button class="empty-btn" onclick={loadSummary}>立即重试</button>
      </div>
    </div>
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
        <span class="label">重启次数</span>
        <strong>{restartCount}</strong>
      </div>
      <div class="summary-card">
        <span class="label">健康失败计数</span>
        <strong>{healthFailureCount}</strong>
      </div>
      <div class="summary-card">
        <span class="label">服务商健康</span>
        <strong>{providerHealth?.status || "未知"}</strong>
      </div>
      <div class="summary-card">
        <span class="label">引导状态</span>
        <strong>{onboarding?.pending ? "待完成" : onboarding?.completed ? "已完成" : "未知"}</strong>
      </div>
      <div class="summary-card">
        <span class="label">代理路由（Profiles/Bindings）</span>
        <strong>{agentProfilesCount ?? "-"} / {agentBindingsCount ?? "-"}</strong>
      </div>
      <div class="summary-card">
        <span class="label">最近监控事件</span>
        <strong class="recent-event">{recentSupervisorError || "-"}</strong>
      </div>
    </div>

    <section class="runtime-defaults">
      <div class="runtime-head">
        <h3>实例默认启动设置</h3>
        <p>这里保存的是实例持久默认值（通过实例 PATCH 接口生效）。</p>
      </div>
      <div class="runtime-form">
        <label class="field-toggle">
          <input
            type="checkbox"
            checked={defaultsAutoStart}
            onchange={(e) => {
              defaultsAutoStart = e.currentTarget.checked;
              defaultsDirty = true;
            }}
          />
          <span>自动启动（auto_start）</span>
        </label>

        <label class="field">
          <span>启动模式（launch_mode）</span>
          <input
            type="text"
            bind:value={defaultsLaunchMode}
            oninput={() => (defaultsDirty = true)}
            placeholder="gateway / agent / 自定义子命令"
          />
        </label>

        <label class="field-toggle">
          <input
            type="checkbox"
            checked={defaultsVerbose}
            onchange={(e) => {
              defaultsVerbose = e.currentTarget.checked;
              defaultsDirty = true;
            }}
          />
          <span>详细日志（verbose）</span>
        </label>
      </div>
      <div class="runtime-actions">
        <button class="btn-save" onclick={saveDefaultSettings} disabled={!defaultsDirty || savingDefaults}>
          {savingDefaults ? "保存中..." : "保存默认设置"}
        </button>
        <button class="btn-reset" onclick={resetDefaultSettingsDraft} disabled={!defaultsDirty || savingDefaults}>
          重置改动
        </button>
      </div>
    </section>

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
            <h3>服务商健康</h3>
            <pre>{JSON.stringify(providerHealth || {}, null, 2)}</pre>
          </div>
          <div>
            <h3>引导状态</h3>
            <pre>{JSON.stringify(onboarding || {}, null, 2)}</pre>
          </div>
        </div>
      {/if}

      {#if activeTab === "agents"}
        <InstanceAgentsPanel {component} {name} active={activeTab === "agents"} />
      {/if}

      {#if activeTab === "config"}
        <ConfigEditor {component} {name} onAction={loadSummary} />
      {/if}

      {#if activeTab === "logs"}
        {#key logViewerKey}
          <LogViewer {component} {name} initialSource={logInitialSource} />
        {/key}
      {/if}

      {#if activeTab === "usage"}
        <div>
          <h3>用量聚合</h3>
          <pre>{usageJson}</pre>
        </div>
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

      {#if activeTab === "integration"}
        <div>
          <h3>集成状态</h3>
          <pre>{integrationJson}</pre>
        </div>
      {/if}
    </section>
  {/if}
</div>

{#if launchDialogOpen}
  <div
    class="modal-backdrop"
    role="button"
    tabindex="0"
    aria-label="关闭启动参数弹窗"
    onclick={handleLaunchBackdropClick}
    onkeydown={handleLaunchBackdropKeydown}
  >
    <div class="modal" role="dialog" aria-modal="true" aria-labelledby="launch-dialog-title">
      <h3 id="launch-dialog-title">{launchAction === "start" ? "启动参数" : "重启参数"}</h3>
      <p class="modal-desc">以下参数仅用于本次操作；可选同步为实例默认值。</p>

      <label class="field">
        <span>启动模式（launch_mode）</span>
        <input type="text" bind:value={launchMode} placeholder="gateway / agent / 自定义子命令" />
      </label>

      <label class="field-toggle">
        <input type="checkbox" bind:checked={launchVerbose} />
        <span>详细日志（verbose）</span>
      </label>

      <label class="field-toggle persist">
        <input type="checkbox" bind:checked={launchPersistDefaults} />
        <span>同时保存为实例默认设置</span>
      </label>

      <div class="modal-actions">
        <button class="btn-reset" onclick={closeLaunchDialog} disabled={busyAction === "start" || busyAction === "restart"}>
          取消
        </button>
        <button class="btn-save" onclick={confirmLaunchAction} disabled={busyAction === "start" || busyAction === "restart"}>
          {busyAction === launchAction ? "执行中..." : launchAction === "start" ? "确认启动" : "确认重启"}
        </button>
      </div>
    </div>
  </div>
{/if}

<style>
  .page {
    padding: var(--spacing-2xl);
    max-width: 1400px;
    margin: 0 auto;
  }

  .instance-header {
    display: flex;
    justify-content: space-between;
    gap: 1rem;
    align-items: flex-start;
    margin-bottom: var(--spacing-lg);
  }

  .header-left {
    display: flex;
    flex-direction: column;
    gap: 0.35rem;
  }

  .back-link {
    color: var(--slate-500);
    text-decoration: none;
    font-size: var(--text-sm);
    background: none;
    border: none;
    cursor: pointer;
    padding: 0;
    font-family: inherit;
    transition: color var(--transition-fast);
  }

  .back-link:hover {
    color: var(--indigo-600);
  }

  h1 {
    margin: 0;
    font-family: var(--font-mono);
    font-size: var(--text-2xl);
  }

  .subtitle {
    margin: 0;
    color: var(--slate-500);
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

  .btn-stop {
    background: var(--red-600);
    color: white;
  }

  .btn-restart {
    background: var(--amber-500);
    color: var(--slate-800);
  }

  .btn-update {
    background: var(--indigo-600);
    color: white;
  }

  .btn-delete {
    background: white;
    color: var(--red-600);
    border-color: var(--red-300);
  }

  .btn-action:disabled {
    opacity: 0.55;
    cursor: not-allowed;
  }

  .failed-banner {
    margin-bottom: 1rem;
    padding: 0.85rem 1rem;
    border: 1px solid #f5d0a6;
    background: #fff7ed;
    color: #9a3412;
    border-radius: 10px;
    display: flex;
    justify-content: space-between;
    gap: 1rem;
    align-items: center;
  }

  .failed-banner h3 {
    margin: 0;
    font-size: var(--text-base);
  }

  .failed-banner p {
    margin: 0.2rem 0 0 0;
    font-size: var(--text-sm);
  }

  .failed-detail {
    font-family: var(--font-mono);
    opacity: 0.85;
  }

  .failed-log-btn {
    border: 1px solid #ea580c;
    background: #ea580c;
    color: white;
    border-radius: 8px;
    padding: 0.45rem 0.8rem;
    cursor: pointer;
    white-space: nowrap;
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
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
  }

  .empty-actions {
    display: flex;
    gap: 0.8rem;
    flex-wrap: wrap;
  }

  .empty-actions button {
    color: var(--indigo-600);
    background: none;
    border: 1px solid var(--indigo-300);
    border-radius: var(--radius-sm);
    padding: 0.4rem 0.8rem;
    font-size: var(--text-sm);
    cursor: pointer;
    transition: all var(--transition-fast);
  }

  .empty-actions button:hover {
    background: var(--indigo-50);
    border-color: var(--indigo-500);
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
    min-width: 0;
  }

  .summary-card .label {
    font-size: var(--text-xs);
    color: var(--slate-500);
    letter-spacing: 0.2px;
  }

  .recent-event {
    font-size: var(--text-xs);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .runtime-defaults {
    border: 1px solid var(--slate-200);
    border-radius: 10px;
    background: white;
    padding: 1rem;
    margin-bottom: 1rem;
  }

  .runtime-head h3 {
    margin: 0;
    color: var(--slate-800);
  }

  .runtime-head p {
    margin: 0.35rem 0 0 0;
    color: var(--slate-500);
    font-size: var(--text-sm);
  }

  .runtime-form {
    margin-top: 0.9rem;
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
    gap: 0.75rem;
  }

  .field {
    display: flex;
    flex-direction: column;
    gap: 0.35rem;
  }

  .field span {
    font-size: var(--text-xs);
    color: var(--slate-600);
  }

  .field input {
    border: 1px solid var(--slate-300);
    border-radius: 8px;
    padding: 0.5rem 0.65rem;
  }

  .field-toggle {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    color: var(--slate-700);
    font-size: var(--text-sm);
  }

  .runtime-actions {
    display: flex;
    gap: 0.6rem;
    margin-top: 0.9rem;
  }

  .btn-save,
  .btn-reset {
    border-radius: 8px;
    padding: 0.45rem 0.85rem;
    cursor: pointer;
    font-weight: 600;
  }

  .btn-save {
    border: 1px solid var(--indigo-600);
    background: var(--indigo-600);
    color: white;
  }

  .btn-reset {
    border: 1px solid var(--slate-300);
    background: white;
    color: var(--slate-700);
  }

  .btn-save:disabled,
  .btn-reset:disabled {
    opacity: 0.55;
    cursor: not-allowed;
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

  .modal-backdrop {
    position: fixed;
    inset: 0;
    background: rgba(15, 23, 42, 0.42);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 200;
    padding: 1rem;
  }

  .modal {
    width: min(560px, 100%);
    background: white;
    border-radius: 12px;
    border: 1px solid var(--slate-200);
    box-shadow: 0 16px 40px rgba(15, 23, 42, 0.22);
    padding: 1rem;
  }

  .modal h3 {
    margin: 0;
    color: var(--slate-800);
  }

  .modal-desc {
    margin: 0.35rem 0 0.8rem 0;
    color: var(--slate-500);
    font-size: var(--text-sm);
  }

  .persist {
    margin-top: 0.45rem;
    color: var(--slate-600);
  }

  .modal-actions {
    display: flex;
    justify-content: flex-end;
    gap: 0.55rem;
    margin-top: 1rem;
  }

  @media (max-width: 900px) {
    .instance-header {
      flex-direction: column;
    }

    .actions {
      width: 100%;
    }

    .btn-action {
      flex: 1 1 calc(50% - 0.5rem);
    }

    .failed-banner {
      flex-direction: column;
      align-items: flex-start;
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

    .modal-actions {
      flex-direction: column-reverse;
    }

    .modal-actions .btn-save,
    .modal-actions .btn-reset {
      width: 100%;
    }
  }
</style>
