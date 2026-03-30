<script lang="ts">
  import { goto } from "$app/navigation";
  import { page } from "$app/stores";
  import { onMount, onDestroy } from "svelte";
  import { api } from "$lib/api/client";
  import { formatTimeoutError } from "$lib/api/errorMessages";
  import { t } from "$lib/i18n/index.svelte";
  import type { LogSource } from "$lib/api/client";
  import StatusBadge from "$lib/components/StatusBadge.svelte";
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
  let agentRouteSummaryState = $state<AgentRouteSummaryState>("unknown");
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

  const tabs: { key: TabKey; label: string }[] = $derived([
    { key: "overview", label: t("instanceDetail.tabs.overview") },
    { key: "agents", label: t("instanceDetail.tabs.agents") },
    { key: "config", label: t("instanceDetail.tabs.config") },
    { key: "logs", label: t("instanceDetail.tabs.logs") },
    { key: "usage", label: t("instanceDetail.tabs.usage") },
    { key: "history", label: t("instanceDetail.tabs.history") },
    { key: "memory", label: t("instanceDetail.tabs.memory") },
    { key: "skills", label: t("instanceDetail.tabs.skills") },
    { key: "integration", label: t("instanceDetail.tabs.integration") },
  ]);

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
      if (profilesRes.status !== "fulfilled" || bindingsRes.status !== "fulfilled") {
        agentRouteSummaryState = "unavailable";
      } else if ((agentProfilesCount ?? 0) === 0) {
        agentRouteSummaryState = "missing_profiles";
      } else if ((agentBindingsCount ?? 0) === 0) {
        agentRouteSummaryState = "default_only";
      } else {
        agentRouteSummaryState = "configured";
      }

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
    activeTab = "logs";
    logInitialSource = "nullhubx";
    logViewerKey += 1;
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
  <title>{component}/{name} - {t("instanceDetail.title")} - NullHubX</title>
</svelte:head>

<div class="page-shell instance-page">
  <section class="section-shell hero-shell">
    <div class="instance-header">
      <div class="header-left">
        <button class="control-btn secondary back-link" type="button" onclick={() => goto("/instances")}>
          {t("instanceDetail.backToWorkspace")}
        </button>
        {#if isValidInstance}
          <div class="title-stack">
            <div class="header-meta">
              <span class="page-kicker">{component}</span>
              {#if instanceStatus}
                <StatusBadge status={statusText} />
              {/if}
            </div>
            <h1 class="page-title">{component}/{name}</h1>
            <p class="page-subtitle">{t("instanceDetail.subtitle")}</p>
          </div>
        {/if}
      </div>
      <div class="actions">
        <button
          class="control-btn primary"
          onclick={() => openLaunchDialog("start")}
          disabled={busyAction !== null || !canStart || !instanceStatus}
        >
          {busyAction === "start" ? t("instanceDetail.starting") : t("instanceDetail.start")}
        </button>
        <button
          class="control-btn warning"
          onclick={() => runControlAction("stop")}
          disabled={busyAction !== null || !canStop || !instanceStatus}
        >
          {busyAction === "stop" ? t("instanceDetail.stopping") : t("instanceDetail.stop")}
        </button>
        <button
          class="control-btn secondary"
          onclick={() => openLaunchDialog("restart")}
          disabled={busyAction !== null || !canRestart || !instanceStatus}
        >
          {busyAction === "restart" ? t("instanceDetail.restarting") : t("instanceDetail.restart")}
        </button>
        <button class="control-btn secondary" onclick={() => runControlAction("update")} disabled={busyAction !== null || !instanceStatus}>
          {busyAction === "update" ? t("instanceDetail.updating") : t("instanceDetail.update")}
        </button>
        <button class="control-btn danger" onclick={runDelete} disabled={busyAction !== null || !instanceStatus}>
          {busyAction === "delete" ? t("instanceDetail.deleting") : t("instanceDetail.delete")}
        </button>
      </div>
    </div>
  </section>

  {#if statusText === "failed"}
    <div class="section-shell failed-banner">
      <div>
        <h3>{t("instanceDetail.failedBannerTitle")}</h3>
        <p>{t("instanceDetail.failedBannerDesc")}</p>
        {#if recentSupervisorError}
          <p class="failed-detail">{recentSupervisorError}</p>
        {/if}
      </div>
      <button class="control-btn warning failed-log-btn" onclick={openFailureLogs}>{t("instanceDetail.viewFailureLogs")}</button>
    </div>
  {/if}

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
    <section class="section-shell summary-shell">
      <div class="section-heading-row">
        <div class="section-heading">
          <span class="section-kicker">{t("instanceDetail.tabs.overview")}</span>
          <h2 class="section-title">{t("instanceDetail.title")}</h2>
          <p class="section-subtitle">{t("instanceDetail.subtitle")}</p>
        </div>
      </div>

      <div class="summary-grid">
        <div class="summary-card status-card">
          <span class="label">{t("instanceDetail.statusLabel")}</span>
          <strong>{statusLabel}</strong>
          <StatusBadge status={statusText} />
        </div>
        <div class="summary-card">
          <span class="label">{t("instanceDetail.versionLabel")}</span>
          <strong>{instanceStatus.version || "-"}</strong>
        </div>
        <div class="summary-card">
          <span class="label">{t("instanceDetail.portLabel")}</span>
          <strong>{instanceStatus.port || "-"}</strong>
        </div>
        <div class="summary-card">
          <span class="label">{t("instanceDetail.restartCountLabel")}</span>
          <strong>{restartCount}</strong>
        </div>
        <div class="summary-card">
          <span class="label">{t("instanceDetail.healthFailuresLabel")}</span>
          <strong>{healthFailureCount}</strong>
        </div>
        <div class="summary-card">
          <span class="label">{t("instanceDetail.providerHealthLabel")}</span>
          <strong>{providerHealth?.status || t("instanceDetail.unknown")}</strong>
        </div>
        <div class="summary-card">
          <span class="label">{t("instanceDetail.onboardingStatusLabel")}</span>
          <strong>{onboarding?.pending ? t("instanceDetail.pending") : onboarding?.completed ? t("instanceDetail.completed") : t("instanceDetail.unknown")}</strong>
        </div>
        <div class="summary-card">
          <span class="label">{t("instanceDetail.agentRoutesLabel")}</span>
          <strong>{agentProfilesCount ?? "-"} / {agentBindingsCount ?? "-"}</strong>
          <span class="summary-note">{t(`instanceDetail.agentRouteStates.${agentRouteSummaryState}`)}</span>
        </div>
        <div class="summary-card wide">
          <span class="label">{t("instanceDetail.recentEventsLabel")}</span>
          <strong class="recent-event">{recentSupervisorError || "-"}</strong>
        </div>
      </div>
    </section>

    <section class="section-shell runtime-defaults">
      <div class="runtime-head">
        <h3>{t("instanceDetail.defaultsTitle")}</h3>
        <p>{t("instanceDetail.defaultsDesc")}</p>
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
          <span>{t("instanceDetail.autoStart")}</span>
        </label>

        <label class="field">
          <span>{t("instanceDetail.launchMode")}</span>
          <input
            type="text"
            bind:value={defaultsLaunchMode}
            oninput={() => (defaultsDirty = true)}
            placeholder={t("instanceDetail.launchModePlaceholder")}
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
          <span>{t("instanceDetail.verboseLog")}</span>
        </label>
      </div>
      <div class="runtime-actions">
        <button class="control-btn primary" onclick={saveDefaultSettings} disabled={!defaultsDirty || savingDefaults}>
          {savingDefaults ? t("instanceDetail.savingDefaults") : t("instanceDetail.saveDefaults")}
        </button>
        <button class="control-btn secondary" onclick={resetDefaultSettingsDraft} disabled={!defaultsDirty || savingDefaults}>
          {t("instanceDetail.resetChanges")}
        </button>
      </div>
    </section>

    <nav class="tabs">
      {#each tabs as tab}
        <button class:active={activeTab === tab.key} onclick={() => (activeTab = tab.key)}>{tab.label}</button>
      {/each}
    </nav>

    <section class="section-shell panel">
      {#if activeTab === "overview"}
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
      {/if}

      {#if activeTab === "agents"}
        <InstanceAgentsPanel
          {component}
          {name}
          active={activeTab === "agents"}
          runtimeStatus={statusText}
          {canRestart}
          onSaved={handleAgentsSaved}
          onRequestRestart={handleAgentRestartRequest}
        />
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
        <div class="json-card">
          <h3>{t("instanceDetail.tabs.usage")}</h3>
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
        <div class="json-card">
          <h3>{t("instanceDetail.tabs.integration")}</h3>
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
  .hero-shell {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-lg);
  }

  .instance-header {
    display: flex;
    justify-content: space-between;
    gap: var(--spacing-lg);
    align-items: flex-start;
  }

  .header-left {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-md);
  }

  .back-link {
    width: fit-content;
  }

  .title-stack {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-sm);
  }

  .header-meta {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm);
    flex-wrap: wrap;
  }

  .actions {
    display: flex;
    flex-wrap: wrap;
    gap: var(--spacing-sm);
    justify-content: flex-end;
  }

  .failed-banner {
    display: flex;
    justify-content: space-between;
    gap: var(--spacing-lg);
    align-items: center;
    border-color: rgba(245, 158, 11, 0.2);
    background: linear-gradient(180deg, rgba(255, 251, 235, 0.92), rgba(255, 247, 237, 0.84));
    color: #9a3412;
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
    white-space: nowrap;
  }

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

  .summary-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
    gap: var(--spacing-md);
  }

  .summary-card {
    border: 1px solid rgba(141, 154, 178, 0.18);
    border-radius: var(--radius-lg);
    background: linear-gradient(180deg, rgba(255, 255, 255, 0.86), rgba(246, 249, 255, 0.76));
    padding: 0.95rem 1rem;
    display: flex;
    flex-direction: column;
    gap: var(--spacing-xs);
    min-width: 0;
    box-shadow: var(--shadow-sm);
  }

  .summary-card .label {
    font-size: var(--text-xs);
    color: var(--slate-500);
    letter-spacing: 0.08em;
    text-transform: uppercase;
    font-weight: 600;
  }

  .summary-card strong {
    color: var(--slate-900);
    font-size: var(--text-base);
    line-height: 1.5;
  }

  .summary-note {
    color: var(--slate-500);
    font-size: var(--text-xs);
    line-height: 1.5;
  }

  .summary-card.status-card {
    border-color: rgba(34, 211, 238, 0.22);
    box-shadow: 0 16px 36px rgba(14, 165, 198, 0.08), 0 0 0 1px rgba(34, 211, 238, 0.08);
  }

  .summary-card.wide {
    grid-column: 1 / -1;
  }

  .recent-event {
    font-family: var(--font-mono);
    font-size: var(--text-sm);
    line-height: 1.6;
    white-space: normal;
    overflow-wrap: anywhere;
  }

  .runtime-defaults {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-lg);
  }

  .runtime-head h3 {
    margin: 0;
    color: var(--slate-900);
  }

  .runtime-head p {
    margin: 0.35rem 0 0 0;
    color: var(--slate-600);
    font-size: var(--text-sm);
  }

  .runtime-form {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
    gap: var(--spacing-md);
  }

  .field {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-xs);
  }

  .field span {
    font-size: var(--text-sm);
    color: var(--slate-700);
    font-weight: 600;
  }

  .field input {
    border-radius: var(--radius-md);
    padding: 0.75rem 0.85rem;
  }

  .field-toggle {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm);
    min-height: 48px;
    padding: 0.8rem 0.95rem;
    border: 1px solid rgba(141, 154, 178, 0.16);
    border-radius: var(--radius-lg);
    background: rgba(255, 255, 255, 0.64);
    color: var(--slate-700);
    font-size: var(--text-sm);
  }

  .runtime-actions {
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
    transition: all var(--transition-fast);
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

  @media (max-width: 900px) {
    .instance-header {
      flex-direction: column;
    }

    .actions {
      width: 100%;
      justify-content: flex-start;
    }

    .actions .control-btn {
      flex: 1 1 calc(50% - 0.5rem);
    }

    .failed-banner {
      flex-direction: column;
      align-items: flex-start;
    }
  }

  @media (max-width: 640px) {
    .summary-grid {
      grid-template-columns: 1fr;
    }

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
