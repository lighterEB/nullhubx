<script lang="ts">
  import { goto } from "$app/navigation";
  import { page } from "$app/stores";
  import { onMount, onDestroy } from "svelte";
  import { api } from "$lib/api/client";
  import { formatTimeoutError } from "$lib/api/errorMessages";
  import { t } from "$lib/i18n/index.svelte";
  import type { LogSource } from "$lib/api/client";
  import InstanceDetailChrome from "$lib/components/InstanceDetailChrome.svelte";
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
  type AgentRouteSummaryState = "configured" | "default_only" | "missing_profiles" | "unavailable" | "unknown";

  let component = $derived($page.params.component);
  let name = $derived($page.params.name);
  let isValidInstance = $derived(Boolean(component && name));
  let supportsIntegration = $derived(component === "nullboiler" || component === "nulltickets");

  let activeTab = $state<TabKey>("overview");
  let visitedTabs = $state<TabKey[]>(["overview"]);
  let busyAction = $state<"start" | "stop" | "restart" | "update" | "delete" | null>(null);
  let savingDefaults = $state(false);

  let instanceStatus = $state<any>(null);
  let providerHealth = $state<any>(null);
  let onboarding = $state<any>(null);
  let usage = $state<any>(null);
  let integration = $state<any>(null);
  let agentProfilesCount = $state<number | null>(null);
  let agentBindingsCount = $state<number | null>(null);
  let agentRouteSummaryState = $state<AgentRouteSummaryState>("unknown");
  let instanceMissing = $state(false);
  let loadError = $state("");
  let pollTimer: ReturnType<typeof setInterval> | null = null;
  let summaryRequestToken = $state(0);
  let activeRouteKey = $state("");
  let summaryBusy = $state(false);
  let pendingInteractiveRefresh = $state(false);
  let lastInteractiveAuxKey = $state("");
  let lastPolledTab = $state<TabKey>("overview");

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
  let logViewerResetToken = $state(0);

  const tabs: { key: TabKey; label: string }[] = $derived.by(() => {
    const baseTabs: { key: TabKey; label: string }[] = [
      { key: "overview", label: t("instanceDetail.tabs.overview") },
      { key: "agents", label: t("instanceDetail.tabs.agents") },
      { key: "config", label: t("instanceDetail.tabs.config") },
      { key: "logs", label: t("instanceDetail.tabs.logs") },
      { key: "usage", label: t("instanceDetail.tabs.usage") },
      { key: "history", label: t("instanceDetail.tabs.history") },
      { key: "memory", label: t("instanceDetail.tabs.memory") },
      { key: "skills", label: t("instanceDetail.tabs.skills") },
    ];
    if (supportsIntegration) {
      baseTabs.push({ key: "integration", label: t("instanceDetail.tabs.integration") });
    }
    return baseTabs;
  });

  const statusText = $derived(instanceStatus?.status || "unknown");
  const statusLabel = $derived(
    ({
      running: t("instanceDetail.statusLabels.running"),
      stopped: t("instanceDetail.statusLabels.stopped"),
      starting: t("instanceDetail.statusLabels.starting"),
      stopping: t("instanceDetail.statusLabels.stopping"),
      failed: t("instanceDetail.statusLabels.failed"),
      restarting: t("instanceDetail.statusLabels.restarting"),
    } as Record<string, string>)[statusText] || t("instanceDetail.statusLabels.unknown"),
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

  function hasVisitedTab(tab: TabKey): boolean {
    return visitedTabs.includes(tab);
  }

  function activateTab(tab: TabKey) {
    if (!visitedTabs.includes(tab)) {
      visitedTabs = [...visitedTabs, tab];
    }
    activeTab = tab;
  }

  function normalizeError(err: unknown): string {
    return err instanceof Error ? err.message : t("error.requestFailed");
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

  function sameInstanceSnapshot(
    a: Record<string, unknown> | null | undefined,
    b: Record<string, unknown> | null | undefined,
  ): boolean {
    if (a === b) return true;
    if (!a || !b) return false;
    return (
      a.component === b.component &&
      a.name === b.name &&
      a.status === b.status &&
      a.pid === b.pid &&
      a.port === b.port &&
      a.version === b.version &&
      a.auto_start === b.auto_start &&
      a.launch_mode === b.launch_mode &&
      a.verbose === b.verbose &&
      a.uptime_seconds === b.uptime_seconds &&
      a.restart_count === b.restart_count &&
      a.health_consecutive_failures === b.health_consecutive_failures
    );
  }

  async function withTimeout<T>(promise: Promise<T>, timeoutMs: number): Promise<T> {
    let timeoutId: ReturnType<typeof setTimeout> | null = null;
    const timeoutPromise = new Promise<never>((_, reject) => {
      timeoutId = setTimeout(
        () => reject(new Error(formatTimeoutError(timeoutMs, `/instances/${component}/${name}`))),
        timeoutMs,
      );
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
        agentRouteSummaryState = "unknown";
        recentSupervisorError = "";
        healthFailuresFromLogs = null;
        return;
      }

      if (!sameInstanceSnapshot(instanceStatus, inst)) {
        instanceStatus = {
          ...(instanceStatus || {}),
          ...inst,
        };
      }

      const shouldFetchOverviewAux = mode === "interactive" || activeTab === "overview";
      const shouldFetchUsage = mode === "interactive" && activeTab === "usage";
      const shouldFetchIntegration =
        mode === "interactive" && activeTab === "integration" && supportsIntegration;
      const shouldFetchAgentRoutes = mode === "interactive" || activeTab === "agents" || activeTab === "overview";
      const shouldFetchSupervisorLogs = mode === "interactive" || activeTab === "logs" || activeTab === "overview";
      const AUX_TIMEOUT_MS = 6000;

      const [healthRes, onboardingRes, usageRes, integrationRes, profilesRes, bindingsRes, supervisorLogsRes] =
        await Promise.allSettled([
          shouldFetchOverviewAux
            ? withTimeout(api.getProviderHealth(targetComponent, targetName), AUX_TIMEOUT_MS)
            : Promise.resolve(providerHealth),
          shouldFetchOverviewAux
            ? withTimeout(api.getOnboarding(targetComponent, targetName), AUX_TIMEOUT_MS)
            : Promise.resolve(onboarding),
          shouldFetchUsage
            ? withTimeout(api.getUsage(targetComponent, targetName, "all"), AUX_TIMEOUT_MS)
            : Promise.resolve(usage),
          shouldFetchIntegration
            ? withTimeout(api.getIntegration(targetComponent, targetName), AUX_TIMEOUT_MS)
            : Promise.resolve(integration),
          shouldFetchAgentRoutes
            ? withTimeout(api.getAgentProfiles(targetComponent, targetName), AUX_TIMEOUT_MS)
            : Promise.resolve(null),
          shouldFetchAgentRoutes
            ? withTimeout(api.getAgentBindings(targetComponent, targetName), AUX_TIMEOUT_MS)
            : Promise.resolve(null),
          shouldFetchSupervisorLogs
            ? withTimeout(api.getLogs(targetComponent, targetName, 120, "nullhubx"), AUX_TIMEOUT_MS)
            : Promise.resolve(null),
        ]);
      if (requestToken !== summaryRequestToken) return;
      const latest = resolveRouteRef();
      if (!latest || targetComponent !== latest.component || targetName !== latest.name) return;

      if (shouldFetchOverviewAux) {
        providerHealth = healthRes.status === "fulfilled" ? healthRes.value : null;
        onboarding = onboardingRes.status === "fulfilled" ? onboardingRes.value : null;
      }
      if (shouldFetchUsage) {
        usage = usageRes.status === "fulfilled" ? usageRes.value : null;
      }
      if (shouldFetchIntegration) {
        integration = integrationRes.status === "fulfilled" ? integrationRes.value : null;
      } else if (!supportsIntegration) {
        integration = null;
      }
      if (shouldFetchAgentRoutes) {
        agentProfilesCount =
          profilesRes.status === "fulfilled" && Array.isArray(profilesRes.value?.profiles)
            ? profilesRes.value.profiles.length
            : null;
        agentBindingsCount =
          bindingsRes.status === "fulfilled" && Array.isArray(bindingsRes.value?.bindings)
            ? bindingsRes.value.bindings.length
            : null;
        if (profilesRes.status !== "fulfilled" || bindingsRes.status !== "fulfilled") {
          agentRouteSummaryState = "unavailable";
        } else if ((agentProfilesCount ?? 0) === 0) {
          agentRouteSummaryState = "missing_profiles";
        } else if ((agentBindingsCount ?? 0) === 0) {
          agentRouteSummaryState = "default_only";
        } else {
          agentRouteSummaryState = "configured";
        }
      }

      if (shouldFetchSupervisorLogs && supervisorLogsRes.status === "fulfilled") {
        const diagnostics = parseSupervisorDiagnostics(supervisorLogsRes.value?.lines || []);
        recentSupervisorError = diagnostics.latestFailure;
        healthFailuresFromLogs = diagnostics.healthFailures;
      } else if (shouldFetchSupervisorLogs) {
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
      if (activeTab === "config") return;
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
      loadError = t("instanceDetail.launchModeRequired");
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
      loadError = t("instanceDetail.defaultLaunchModeRequired");
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
    const msg = t("instanceDetail.confirmDelete")
      .replace("{component}", component)
      .replace("{name}", name);
    if (!confirm(msg)) return;
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
    activateTab("logs");
    logInitialSource = "nullhubx";
    logViewerResetToken += 1;
  }

  async function handleAgentsSaved() {
    await loadSummary("interactive");
  }

  function handleAgentRestartRequest() {
    openLaunchDialog("restart");
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

    visitedTabs = ["overview"];
    activeTab = "overview";
    launchDialogOpen = false;
    instanceMissing = false;
    loadError = "";
    logInitialSource = "instance";
    logViewerResetToken += 1;
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
    const tab = activeTab;
    const routeKey = activeRouteKey;

    if (tab !== "usage" && tab !== "integration") {
      lastInteractiveAuxKey = "";
      return;
    }

    if (tab === "integration" && !supportsIntegration) {
      lastInteractiveAuxKey = "";
      integration = null;
      return;
    }

    if (!routeKey) return;

    const refreshKey = `${routeKey}:${tab}`;
    if (refreshKey === lastInteractiveAuxKey) return;

    lastInteractiveAuxKey = refreshKey;
    void loadSummary("interactive");
  });

  $effect(() => {
    if (supportsIntegration) return;
    if (activeTab === "integration") {
      activeTab = "overview";
    }
    if (visitedTabs.includes("integration")) {
      visitedTabs = visitedTabs.filter((tab) => tab !== "integration");
    }
    integration = null;
  });

  $effect(() => {
    const currentTab = activeTab;
    const previousTab = lastPolledTab;
    lastPolledTab = currentTab;

    if (previousTab === "config" && currentTab !== "config") {
      void loadSummary("poll");
    }
  });
</script>

<svelte:head>
  <title>{component}/{name} - {t("instanceDetail.title")} - NullHubX</title>
</svelte:head>

<div class="page-shell instance-page">
  <InstanceDetailChrome
    {component}
    {name}
    {isValidInstance}
    {instanceStatus}
    {statusText}
    {statusLabel}
    {recentSupervisorError}
    {providerHealth}
    {onboarding}
    {agentProfilesCount}
    {agentBindingsCount}
    {agentRouteSummaryState}
    {restartCount}
    {healthFailureCount}
    {defaultsAutoStart}
    {defaultsLaunchMode}
    {defaultsVerbose}
    {defaultsDirty}
    {savingDefaults}
    {busyAction}
    {canStart}
    {canStop}
    {canRestart}
    onBackWorkspace={() => goto("/instances")}
    onOpenStart={() => openLaunchDialog("start")}
    onStop={() => runControlAction("stop")}
    onOpenRestart={() => openLaunchDialog("restart")}
    onUpdate={() => runControlAction("update")}
    onDelete={runDelete}
    onOpenFailureLogs={openFailureLogs}
    onDefaultsAutoStartChange={(checked) => {
      defaultsAutoStart = checked;
      defaultsDirty = true;
    }}
    onDefaultsLaunchModeChange={(value) => {
      defaultsLaunchMode = value;
      defaultsDirty = true;
    }}
    onDefaultsVerboseChange={(checked) => {
      defaultsVerbose = checked;
      defaultsDirty = true;
    }}
    onSaveDefaults={saveDefaultSettings}
    onResetDefaults={resetDefaultSettingsDraft}
  />

  {#if loadError}
    <div class="feedback-banner error">{loadError}</div>
  {/if}

  {#if !instanceStatus}
    <div class="section-shell empty">
      {#if instanceMissing}
        {t("instanceDetail.notFound")}
      {:else}
        {t("instanceDetail.fetching")}
      {/if}
      <div class="empty-actions">
        <button class="control-btn secondary" type="button" onclick={() => goto("/instances")}>{t("instanceDetail.backToWorkspace")}</button>
        <button class="control-btn secondary" type="button" onclick={() => goto("/")}>{t("instanceDetail.backToOverview")}</button>
        <button class="control-btn primary" onclick={() => void loadSummary("interactive")}>{t("instanceDetail.retryNow")}</button>
      </div>
    </div>
  {:else}
    <nav class="tabs">
      {#each tabs as tab}
        <button type="button" class:active={activeTab === tab.key} onclick={() => activateTab(tab.key)}>{tab.label}</button>
      {/each}
    </nav>

    <section class="section-shell panel tab-panel-shell">
      {#if hasVisitedTab("overview")}
        <div class="tab-pane" hidden={activeTab !== "overview"}>
        <div class="json-grid">
          <div class="json-card">
            <h3>{t("instanceDetail.statusLabel")}</h3>
            <pre>{JSON.stringify(instanceStatus, null, 2)}</pre>
          </div>
          <div class="json-card">
            <h3>{t("instanceDetail.providerHealthLabel")}</h3>
            <pre>{JSON.stringify(providerHealth || {}, null, 2)}</pre>
          </div>
          <div class="json-card">
            <h3>{t("instanceDetail.onboardingStatusLabel")}</h3>
            <pre>{JSON.stringify(onboarding || {}, null, 2)}</pre>
          </div>
        </div>
        </div>
      {/if}

      {#if hasVisitedTab("agents")}
        <div class="tab-pane" hidden={activeTab !== "agents"}>
        <InstanceAgentsPanel
          {component}
          {name}
          active={activeTab === "agents"}
          runtimeStatus={statusText}
          {canRestart}
          onSaved={handleAgentsSaved}
          onRequestRestart={handleAgentRestartRequest}
        />
        </div>
      {/if}

      {#if hasVisitedTab("config")}
        <div class="tab-pane" hidden={activeTab !== "config"}>
          <ConfigEditor {component} {name} active={activeTab === "config"} onAction={loadSummary} />
        </div>
      {/if}

      {#if hasVisitedTab("logs")}
        <div class="tab-pane" hidden={activeTab !== "logs"}>
        <LogViewer
          {component}
          {name}
          active={activeTab === "logs"}
          initialSource={logInitialSource}
          resetToken={logViewerResetToken}
        />
        </div>
      {/if}

      {#if hasVisitedTab("usage")}
        <div class="tab-pane" hidden={activeTab !== "usage"}>
          <div class="json-card">
            <h3>{t("instanceDetail.tabs.usage")}</h3>
            <pre>{usageJson}</pre>
          </div>
        </div>
      {/if}

      {#if hasVisitedTab("history")}
        <div class="tab-pane" hidden={activeTab !== "history"}>
          <InstanceHistoryPanel {component} {name} active={activeTab === "history"} />
        </div>
      {/if}

      {#if hasVisitedTab("memory")}
        <div class="tab-pane" hidden={activeTab !== "memory"}>
          <InstanceMemoryPanel {component} {name} active={activeTab === "memory"} />
        </div>
      {/if}

      {#if hasVisitedTab("skills")}
        <div class="tab-pane" hidden={activeTab !== "skills"}>
          <InstanceSkillsPanel {component} {name} active={activeTab === "skills"} />
        </div>
      {/if}

      {#if supportsIntegration && hasVisitedTab("integration")}
        <div class="tab-pane" hidden={activeTab !== "integration"}>
          <div class="json-card">
            <h3>{t("instanceDetail.tabs.integration")}</h3>
            <pre>{integrationJson}</pre>
          </div>
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
    aria-label={t("instanceDetail.closeLaunchDialog")}
    onclick={handleLaunchBackdropClick}
    onkeydown={handleLaunchBackdropKeydown}
  >
    <div class="modal" role="dialog" aria-modal="true" aria-labelledby="launch-dialog-title">
      <h3 id="launch-dialog-title">{launchAction === "start" ? t("instanceDetail.launchDialog.start") : t("instanceDetail.launchDialog.restart")}</h3>
      <p class="modal-desc">{t("instanceDetail.launchDialogDesc")}</p>

      <label class="field">
        <span>{t("instanceDetail.launchDialog.launchMode")}</span>
        <input type="text" bind:value={launchMode} placeholder={t("instanceDetail.launchModePlaceholder")} />
      </label>

      <label class="field-toggle">
        <input type="checkbox" bind:checked={launchVerbose} />
        <span>{t("instanceDetail.launchDialog.verbose")}</span>
      </label>

      <label class="field-toggle persist">
        <input type="checkbox" bind:checked={launchPersistDefaults} />
        <span>{t("instanceDetail.launchDialog.persistDefaults")}</span>
      </label>

      <div class="modal-actions">
        <button class="control-btn secondary" onclick={closeLaunchDialog} disabled={busyAction === "start" || busyAction === "restart"}>
          {t("instanceDetail.launchDialog.cancel")}
        </button>
        <button class="control-btn primary" onclick={confirmLaunchAction} disabled={busyAction === "start" || busyAction === "restart"}>
          {busyAction === launchAction ? t("instanceDetail.executing") : launchAction === "start" ? t("instanceDetail.confirmStart") : t("instanceDetail.confirmRestart")}
        </button>
      </div>
    </div>
  </div>
{/if}

<style>
  .feedback-banner {
    padding: 0.85rem 1rem;
    border-radius: var(--radius-lg);
    border: 1px solid rgba(244, 63, 94, 0.16);
    background: rgba(255, 241, 245, 0.82);
    color: var(--red-700);
    box-shadow: var(--shadow-sm);
  }

  .empty {
    padding: var(--spacing-3xl);
    color: var(--slate-500);
    display: flex;
    flex-direction: column;
    gap: var(--spacing-md);
  }

  .empty-actions {
    display: flex;
    gap: var(--spacing-sm);
    flex-wrap: wrap;
  }

  .tabs {
    display: flex;
    flex-wrap: wrap;
    gap: var(--spacing-sm);
  }

  .tabs button {
    border: 1px solid rgba(141, 154, 178, 0.18);
    background: rgba(255, 255, 255, 0.74);
    padding: 0.7rem 1rem;
    cursor: pointer;
    color: var(--slate-500);
    border-radius: 999px;
    font-family: var(--font-mono);
    font-size: var(--text-sm);
    letter-spacing: 0.04em;
    transition:
      color var(--transition-fast),
      background-color var(--transition-fast),
      border-color var(--transition-fast),
      box-shadow var(--transition-fast);
    max-width: 100%;
    white-space: normal;
    overflow-wrap: anywhere;
    text-align: center;
    line-height: 1.35;
  }

  .tabs button.active {
    border-color: rgba(34, 211, 238, 0.22);
    background: linear-gradient(135deg, rgba(15, 23, 42, 0.96), rgba(24, 34, 56, 0.94));
    color: var(--shell-text);
    box-shadow: var(--glow-cyan);
  }

  .panel {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-lg);
  }

  .tab-pane {
    min-width: 0;
  }

  .tab-panel-shell {
    gap: var(--spacing-xl);
    background:
      linear-gradient(180deg, rgba(9, 15, 27, 0.96), rgba(14, 22, 38, 0.92)),
      radial-gradient(circle at top right, rgba(34, 211, 238, 0.14), transparent 34%);
    border-color: rgba(116, 136, 173, 0.24);
    box-shadow:
      0 24px 64px rgba(6, 11, 21, 0.24),
      inset 0 1px 0 rgba(255, 255, 255, 0.04);
  }

  .tab-panel-shell :global(.history-panel),
  .tab-panel-shell :global(.memory-panel),
  .tab-panel-shell :global(.skills-panel),
  .tab-panel-shell :global(.config-editor) {
    gap: var(--spacing-xl);
  }

  .tab-panel-shell :global(.history-panel .panel-toolbar),
  .tab-panel-shell :global(.memory-panel .panel-toolbar),
  .tab-panel-shell :global(.skills-panel .panel-toolbar),
  .tab-panel-shell :global(.config-editor .editor-header) {
    gap: 0.9rem;
    padding: 1rem 1.1rem;
    border: 1px solid rgba(116, 136, 173, 0.22);
    border-radius: var(--radius-lg);
    background: linear-gradient(180deg, rgba(11, 18, 31, 0.84), rgba(15, 23, 42, 0.76));
    box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.04);
    backdrop-filter: blur(8px);
  }

  .tab-panel-shell :global(.history-panel .panel-toolbar h2),
  .tab-panel-shell :global(.memory-panel .panel-toolbar h2),
  .tab-panel-shell :global(.skills-panel .panel-toolbar h2),
  .tab-panel-shell :global(.memory-panel .section-header h3),
  .tab-panel-shell :global(.skills-panel .section-header h3) {
    font-size: 1rem;
    line-height: 1.2;
    color: var(--shell-text);
  }

  .tab-panel-shell :global(.history-panel .panel-toolbar p),
  .tab-panel-shell :global(.memory-panel .panel-toolbar p),
  .tab-panel-shell :global(.skills-panel .panel-toolbar p),
  .tab-panel-shell :global(.memory-panel .section-header p),
  .tab-panel-shell :global(.skills-panel .section-header p) {
    margin-top: 0.2rem;
    font-size: 0.82rem;
    line-height: 1.55;
    color: var(--shell-text-dim);
  }

  .tab-panel-shell :global(.history-panel .toolbar-btn),
  .tab-panel-shell :global(.memory-panel .toolbar-btn),
  .tab-panel-shell :global(.skills-panel .toolbar-btn),
  .tab-panel-shell :global(.skills-panel .toolbar-link) {
    min-height: 38px;
    border-color: rgba(116, 136, 173, 0.22);
    background: rgba(255, 255, 255, 0.05);
    color: var(--shell-text-dim);
    box-shadow: none;
  }

  .tab-panel-shell :global(.history-panel .toolbar-btn:hover),
  .tab-panel-shell :global(.memory-panel .toolbar-btn:hover),
  .tab-panel-shell :global(.skills-panel .toolbar-btn:hover),
  .tab-panel-shell :global(.skills-panel .toolbar-link:hover) {
    border-color: rgba(34, 211, 238, 0.28);
    background: rgba(34, 211, 238, 0.1);
    color: var(--shell-text);
  }

  .tab-panel-shell :global(.history-panel .session-list),
  .tab-panel-shell :global(.history-panel .message-pane),
  .tab-panel-shell :global(.memory-panel .memory-section),
  .tab-panel-shell :global(.memory-panel .stat-card),
  .tab-panel-shell :global(.skills-panel .skill-section),
  .tab-panel-shell :global(.skills-panel .install-card),
  .tab-panel-shell :global(.skills-panel .skill-card),
  .tab-panel-shell :global(.config-editor .ui-content),
  .tab-panel-shell :global(.config-editor .raw-editor) {
    border-color: rgba(116, 136, 173, 0.2);
    background: linear-gradient(180deg, rgba(12, 19, 33, 0.82), rgba(16, 25, 42, 0.76));
    box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.03);
  }

  .tab-panel-shell :global(.config-editor .ui-content) {
    padding: 0.35rem;
    border: 1px solid rgba(116, 136, 173, 0.2);
    border-radius: var(--radius-lg);
  }

  .tab-panel-shell :global(.history-panel .session-list-header),
  .tab-panel-shell :global(.history-panel .session-page-controls),
  .tab-panel-shell :global(.history-panel .message-header) {
    border-color: rgba(116, 136, 173, 0.18);
    color: var(--shell-text-dim);
    background: rgba(255, 255, 255, 0.04);
  }

  .tab-panel-shell :global(.history-panel .session-item) {
    padding: 0.78rem 0.9rem;
    color: var(--shell-text-subtle);
    border-color: rgba(116, 136, 173, 0.14);
  }

  .tab-panel-shell :global(.history-panel .session-item:hover),
  .tab-panel-shell :global(.history-panel .session-item.active) {
    background: rgba(34, 211, 238, 0.12);
  }

  .tab-panel-shell :global(.history-panel .session-meta),
  .tab-panel-shell :global(.history-panel .message-subtitle),
  .tab-panel-shell :global(.history-panel .message-card header),
  .tab-panel-shell :global(.memory-panel .entry-meta),
  .tab-panel-shell :global(.memory-panel .search-meta),
  .tab-panel-shell :global(.skills-panel .skill-description),
  .tab-panel-shell :global(.skills-panel .skill-meta span) {
    color: var(--shell-text-dim);
  }

  .tab-panel-shell :global(.history-panel .session-id),
  .tab-panel-shell :global(.history-panel .message-title),
  .tab-panel-shell :global(.memory-panel .stat-card strong),
  .tab-panel-shell :global(.memory-panel .entry-key),
  .tab-panel-shell :global(.skills-panel .skill-name),
  .tab-panel-shell :global(.skills-panel .skill-meta strong) {
    color: var(--shell-text);
  }

  .tab-panel-shell :global(.memory-panel .stat-card span),
  .tab-panel-shell :global(.skills-panel .badge),
  .tab-panel-shell :global(.skills-panel .skill-version) {
    color: var(--shell-text-dim);
  }

  .tab-panel-shell :global(.history-panel .message-card),
  .tab-panel-shell :global(.memory-panel .entry-card),
  .tab-panel-shell :global(.memory-panel .search-card),
  .tab-panel-shell :global(.skills-panel .skill-path),
  .tab-panel-shell :global(.skills-panel .missing-deps) {
    padding: 0.82rem 0.9rem;
    border-color: rgba(116, 136, 173, 0.18);
    background: rgba(255, 255, 255, 0.05);
  }

  .tab-panel-shell :global(.history-panel .message-list),
  .tab-panel-shell :global(.memory-panel .entry-list),
  .tab-panel-shell :global(.memory-panel .search-list) {
    gap: 0.8rem;
  }

  .tab-panel-shell :global(.memory-panel .stats-grid),
  .tab-panel-shell :global(.skills-panel .skill-grid),
  .tab-panel-shell :global(.skills-panel .install-grid) {
    gap: 0.85rem;
  }

  .tab-panel-shell :global(.history-panel pre),
  .tab-panel-shell :global(.memory-panel pre),
  .tab-panel-shell :global(.skills-panel .skill-path),
  .tab-panel-shell :global(.config-editor .raw-editor) {
    color: #dce8ff;
  }

  .tab-panel-shell :global(.memory-panel select),
  .tab-panel-shell :global(.memory-panel input),
  .tab-panel-shell :global(.skills-panel .install-card input),
  .tab-panel-shell :global(.config-editor .raw-editor) {
    border-color: rgba(116, 136, 173, 0.22);
    background: rgba(255, 255, 255, 0.05);
    color: var(--shell-text);
  }

  .tab-panel-shell :global(.memory-panel input::placeholder),
  .tab-panel-shell :global(.skills-panel .install-card input::placeholder),
  .tab-panel-shell :global(.config-editor .raw-editor::placeholder) {
    color: var(--shell-text-dim);
  }

  .tab-panel-shell :global(.config-editor .mode-toggle) {
    border-color: rgba(116, 136, 173, 0.2);
    background: rgba(255, 255, 255, 0.05);
  }

  .tab-panel-shell :global(.config-editor .action-buttons) {
    gap: 0.55rem;
  }

  .tab-panel-shell :global(.config-editor .mode-btn) {
    color: var(--shell-text-dim);
  }

  .tab-panel-shell :global(.config-editor .mode-btn:hover) {
    color: var(--shell-text);
    background: rgba(34, 211, 238, 0.08);
  }

  .tab-panel-shell :global(.config-editor .mode-btn.active) {
    color: var(--shell-text);
    border-color: rgba(34, 211, 238, 0.24);
    background: linear-gradient(135deg, rgba(34, 211, 238, 0.16), rgba(139, 92, 246, 0.12));
    box-shadow: inset 0 0 16px rgba(34, 211, 238, 0.12);
  }

  .tab-panel-shell :global(.history-panel .panel-state),
  .tab-panel-shell :global(.memory-panel .panel-state),
  .tab-panel-shell :global(.skills-panel .panel-state),
  .tab-panel-shell :global(.config-editor .message) {
    padding: 1rem 1.1rem;
    border-color: rgba(116, 136, 173, 0.22);
    background: rgba(8, 14, 24, 0.68);
    color: var(--shell-text-dim);
    box-shadow: none;
  }

  .tab-panel-shell :global(.history-panel .panel-state.warning),
  .tab-panel-shell :global(.memory-panel .panel-state.warning),
  .tab-panel-shell :global(.skills-panel .panel-state.warning),
  .tab-panel-shell :global(.config-editor .message.error) {
    border-color: rgba(245, 158, 11, 0.28);
    background: rgba(58, 36, 14, 0.4);
    color: #ffd089;
  }

  .tab-panel-shell :global(.skills-panel .panel-state.success) {
    border-color: rgba(16, 185, 129, 0.26);
    background: rgba(10, 48, 37, 0.4);
    color: #9af3cf;
  }

  .tab-panel-shell :global(.log-viewer) {
    min-height: 520px;
    border-color: rgba(116, 136, 173, 0.22);
    box-shadow:
      0 18px 40px rgba(6, 11, 21, 0.18),
      inset 0 1px 0 rgba(255, 255, 255, 0.03);
  }

  .tab-panel-shell :global(.log-header) {
    padding: 1rem 1.1rem;
    border-bottom-color: rgba(116, 136, 173, 0.2);
    background: rgba(255, 255, 255, 0.04);
  }

  .tab-panel-shell :global(.log-title-group > span:first-child) {
    font-size: 0.78rem;
    letter-spacing: 0.1em;
  }

  .tab-panel-shell :global(.log-content) {
    padding: 1.05rem 1.1rem 1.25rem;
    line-height: 1.55;
  }

  .tab-panel-shell :global(.log-line) {
    padding: 0.16rem 0.42rem;
  }

  .tab-panel-shell :global(.log-empty) {
    padding: 2.6rem 1.2rem;
  }

  .tab-panel-shell .json-card h3 {
    color: var(--shell-text);
    font-size: var(--text-sm);
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }

  .tab-panel-shell .json-card pre {
    border-color: rgba(116, 136, 173, 0.2);
    background: linear-gradient(180deg, rgba(12, 19, 33, 0.82), rgba(16, 25, 42, 0.76));
    color: #dce8ff;
    box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.03);
  }

  .json-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
    gap: var(--spacing-md);
  }

  .json-card {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-sm);
  }

  .json-card h3 {
    margin: 0;
    color: var(--slate-900);
    font-size: var(--text-base);
  }

  pre {
    margin: 0;
    border: 1px solid rgba(141, 154, 178, 0.18);
    background: rgba(255, 255, 255, 0.72);
    border-radius: var(--radius-lg);
    padding: 0.9rem 1rem;
    max-height: 320px;
    overflow: auto;
    font-size: 12px;
    box-shadow: inset 0 1px 2px rgba(15, 23, 42, 0.04);
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
    background: rgba(248, 251, 255, 0.96);
    border-radius: var(--radius-xl);
    border: 1px solid rgba(141, 154, 178, 0.18);
    box-shadow: 0 24px 72px rgba(15, 23, 42, 0.22);
    padding: var(--spacing-xl);
    backdrop-filter: blur(20px);
  }

  .modal h3 {
    margin: 0;
    color: var(--slate-900);
  }

  .modal-desc {
    margin: 0.35rem 0 0.8rem 0;
    color: var(--slate-600);
    font-size: var(--text-sm);
  }

  .persist {
    margin-top: 0.45rem;
    color: var(--slate-600);
  }

  .modal-actions {
    display: flex;
    justify-content: flex-end;
    gap: var(--spacing-sm);
    margin-top: var(--spacing-lg);
  }

  @media (max-width: 640px) {
    .tabs {
      overflow-x: auto;
      scrollbar-width: none;
      flex-wrap: nowrap;
      padding-bottom: 2px;
    }

    .tabs::-webkit-scrollbar {
      display: none;
    }

    .modal-actions {
      flex-direction: column-reverse;
    }

    .modal-actions .control-btn {
      width: 100%;
    }
  }
</style>
