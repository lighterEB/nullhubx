<script lang="ts">
  import { goto } from '$app/navigation';
  import { page } from '$app/stores';
  import { onMount, onDestroy, untrack } from 'svelte';
  import { api } from '$lib/api/client';
  import { formatTimeoutError } from '$lib/api/errorMessages';
  import { t } from '$lib/i18n/index.svelte';
  import type { LogSource } from '$lib/api/client';
  import InstanceDetailChrome from '$lib/components/InstanceDetailChrome.svelte';
  import ConfigEditor from '$lib/components/ConfigEditor.svelte';
  import LogViewer from '$lib/components/LogViewer.svelte';
  import InstanceHistoryPanel from '$lib/components/InstanceHistoryPanel.svelte';
  import InstanceMemoryPanel from '$lib/components/InstanceMemoryPanel.svelte';
  import InstanceSkillsPanel from '$lib/components/InstanceSkillsPanel.svelte';
  import InstanceAgentsPanel from '$lib/components/InstanceAgentsPanel.svelte';
  import InstanceCapabilitiesPanel from '$lib/components/InstanceCapabilitiesPanel.svelte';

  type TabKey =
    | 'overview'
    | 'agents'
    | 'config'
    | 'logs'
    | 'usage'
    | 'history'
    | 'capabilities'
    | 'memory'
    | 'skills'
    | 'integration';

  type LaunchAction = 'start' | 'restart';
  type AgentRouteSummaryState =
    | 'configured'
    | 'default_only'
    | 'missing_profiles'
    | 'unavailable'
    | 'unknown';
  type UsageWindow = '24h' | '7d' | '30d' | 'all';
  type UsageRow = {
    provider: string;
    model: string;
    prompt_tokens: number;
    completion_tokens: number;
    total_tokens: number;
    requests: number;
    last_used: number | null;
  };
  type IntegrationSnapshotEntry = {
    key: string;
    value: string;
  };
  type IntegrationTrackerOption = {
    name: string;
    port: number | null;
    running: boolean | null;
    pipelineCount: number;
  };
  type IntegrationLinkedBoiler = {
    name: string;
    port: number | null;
    trackerEntries: IntegrationSnapshotEntry[];
  };

  let { data } = $props();

  let component = $derived($page.params.component);
  let name = $derived($page.params.name);
  let isValidInstance = $derived(Boolean(component && name));
  let supportsIntegration = $derived(component === 'nullboiler' || component === 'nulltickets');
  let supportsRuntimeCapabilities = $derived(component === 'nullclaw');

  let activeTab = $state<TabKey>('overview');
  let visitedTabs = $state<TabKey[]>(['overview']);
  let busyAction = $state<'start' | 'stop' | 'restart' | 'update' | 'delete' | null>(null);
  let savingDefaults = $state(false);

  let instanceStatus = $state<any>(untrack(() => data.initialStatus));
  let providerHealth = $state<any>(null);
  let onboarding = $state<any>(null);
  let usage = $state<any>(null);
  let integration = $state<any>(null);
  let agentProfilesCount = $state<number | null>(null);
  let agentBindingsCount = $state<number | null>(null);
  let agentRouteSummaryState = $state<AgentRouteSummaryState>('unknown');
  let instanceMissing = $state(false);
  let loadError = $state('');
  let pollTimer: ReturnType<typeof setInterval> | null = null;
  let summaryRequestToken = $state(0);
  let activeRouteKey = $state('');
  let summaryBusy = $state(false);
  let pendingInteractiveRefresh = $state(false);
  let lastInteractiveAuxKey = $state('');
  let lastPolledTab = $state<TabKey>('overview');

  let defaultsAutoStart = $state(false);
  let defaultsLaunchMode = $state('gateway');
  let defaultsVerbose = $state(false);
  let defaultsDirty = $state(false);

  let recentSupervisorError = $state('');
  let healthFailuresFromLogs = $state<number | null>(null);

  let launchDialogOpen = $state(false);
  let launchAction = $state<LaunchAction>('start');
  let launchMode = $state('gateway');
  let launchVerbose = $state(false);
  let launchPersistDefaults = $state(false);

  let logInitialSource = $state<LogSource>('instance');
  let logViewerResetToken = $state(0);
  let usageWindow = $state<UsageWindow>('all');

  const tabs: { key: TabKey; label: string }[] = $derived.by(() => {
    const baseTabs: { key: TabKey; label: string }[] = [
      { key: 'overview', label: t('instanceDetail.tabs.overview') },
      { key: 'agents', label: t('instanceDetail.tabs.agents') },
      { key: 'config', label: t('instanceDetail.tabs.config') },
      { key: 'logs', label: t('instanceDetail.tabs.logs') },
      { key: 'usage', label: t('instanceDetail.tabs.usage') },
      { key: 'history', label: t('instanceDetail.tabs.history') },
      { key: 'capabilities', label: t('instanceDetail.tabs.capabilities') },
      { key: 'memory', label: t('instanceDetail.tabs.memory') },
      { key: 'skills', label: t('instanceDetail.tabs.skills') },
    ];
    if (!supportsRuntimeCapabilities) {
      const idx = baseTabs.findIndex((tab) => tab.key === 'capabilities');
      if (idx >= 0) baseTabs.splice(idx, 1);
    }
    if (supportsIntegration) {
      baseTabs.push({ key: 'integration', label: t('instanceDetail.tabs.integration') });
    }
    return baseTabs;
  });

  const statusText = $derived(instanceStatus?.status || 'unknown');
  const statusLabel = $derived(
    (
      {
        running: t('instanceDetail.statusLabels.running'),
        stopped: t('instanceDetail.statusLabels.stopped'),
        starting: t('instanceDetail.statusLabels.starting'),
        stopping: t('instanceDetail.statusLabels.stopping'),
        failed: t('instanceDetail.statusLabels.failed'),
        restarting: t('instanceDetail.statusLabels.restarting'),
      } as Record<string, string>
    )[statusText] || t('instanceDetail.statusLabels.unknown'),
  );
  const canStart = $derived(statusText === 'stopped' || statusText === 'failed');
  const canStop = $derived(['starting', 'running', 'restarting'].includes(statusText));
  const canRestart = $derived(statusText === 'running' || statusText === 'failed');

  const restartCount = $derived(Number(instanceStatus?.restart_count || 0));
  const healthFailureCount = $derived(
    Number(instanceStatus?.health_consecutive_failures ?? healthFailuresFromLogs ?? 0),
  );
  const providerHealthRecord = $derived(asRecord(providerHealth));
  const onboardingRecord = $derived(asRecord(onboarding));
  const usageRecord = $derived(asRecord(usage));
  const usageTotals = $derived(asRecord(usageRecord?.totals));
  const usageRows = $derived.by(() => normalizeUsageRows(usageRecord?.rows));
  const integrationRecord = $derived(asRecord(integration));
  const integrationKind = $derived(asString(integrationRecord?.kind) || component);
  const integrationCurrentLink = $derived(asRecord(integrationRecord?.current_link));
  const integrationLinkedTracker = $derived(asRecord(integrationRecord?.linked_tracker));
  const integrationAvailableTrackers = $derived.by(() =>
    normalizeAvailableTrackers(integrationRecord?.available_trackers),
  );
  const integrationLinkedBoilers = $derived.by(() =>
    normalizeLinkedBoilers(integrationRecord?.linked_boilers),
  );
  const integrationTrackerEntries = $derived.by(() =>
    summarizeSnapshotEntries(integrationRecord?.tracker),
  );
  const integrationQueueEntries = $derived.by(() =>
    summarizeSnapshotEntries(integrationRecord?.queue),
  );
  const usageWindowOptions = $derived.by(() => [
    { key: '24h' as UsageWindow, label: t('instanceDetail.usage.windows.24h') },
    { key: '7d' as UsageWindow, label: t('instanceDetail.usage.windows.7d') },
    { key: '30d' as UsageWindow, label: t('instanceDetail.usage.windows.30d') },
    { key: 'all' as UsageWindow, label: t('instanceDetail.usage.windows.all') },
  ]);
  const onboardingStateLabel = $derived(
    onboardingRecord?.pending
      ? t('instanceDetail.pending')
      : onboardingRecord?.completed
        ? t('instanceDetail.completed')
        : t('instanceDetail.unknown'),
  );

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
    return err instanceof Error ? err.message : t('error.requestFailed');
  }

  function asRecord(value: unknown): Record<string, any> | null {
    if (value && typeof value === 'object' && !Array.isArray(value)) {
      return value as Record<string, any>;
    }
    return null;
  }

  function asBoolean(value: unknown): boolean | null {
    return typeof value === 'boolean' ? value : null;
  }

  function asNumber(value: unknown): number | null {
    return typeof value === 'number' && Number.isFinite(value) ? value : null;
  }

  function asString(value: unknown): string | null {
    if (typeof value !== 'string') return null;
    const trimmed = value.trim();
    return trimmed ? trimmed : null;
  }

  function formatBoolean(value: unknown): string {
    const bool = asBoolean(value);
    if (bool === null) return '-';
    return bool ? t('common.enabled') : t('common.disabled');
  }

  function formatDateTime(value: unknown): string {
    const text = asString(value);
    if (!text) return '-';
    const date = new Date(text);
    return Number.isNaN(date.getTime()) ? text : date.toLocaleString();
  }

  function formatDuration(value: unknown): string {
    const seconds = asNumber(value);
    if (seconds === null || seconds < 0) return '-';
    if (seconds < 60) return `${Math.floor(seconds)}s`;

    const totalMinutes = Math.floor(seconds / 60);
    const days = Math.floor(totalMinutes / 1440);
    const hours = Math.floor((totalMinutes % 1440) / 60);
    const minutes = totalMinutes % 60;
    const parts: string[] = [];

    if (days > 0) parts.push(`${days}d`);
    if (hours > 0) parts.push(`${hours}h`);
    if (minutes > 0 || parts.length === 0) parts.push(`${minutes}m`);

    return parts.join(' ');
  }

  function formatReason(value: unknown): string {
    const text = asString(value);
    if (!text) return '-';
    return text.replace(/_/g, ' ');
  }

  function providerHealthTone(value: unknown): 'success' | 'error' | 'neutral' {
    const text = asString(value)?.toLowerCase();
    if (text === 'ok') return 'success';
    if (text === 'error') return 'error';
    return 'neutral';
  }

  function formatCount(value: unknown): string {
    const num = asNumber(value);
    if (num === null) return '0';
    return num.toLocaleString();
  }

  function formatEpochSeconds(value: unknown): string {
    const seconds = asNumber(value);
    if (seconds === null || seconds <= 0) return '-';
    return new Date(seconds * 1000).toLocaleString();
  }

  function normalizeUsageRows(value: unknown): UsageRow[] {
    if (!Array.isArray(value)) return [];

    return value
      .map((entry) => {
        const row = asRecord(entry);
        if (!row) return null;
        return {
          provider: asString(row.provider) || 'unknown',
          model: asString(row.model) || 'unknown',
          prompt_tokens: asNumber(row.prompt_tokens) ?? 0,
          completion_tokens: asNumber(row.completion_tokens) ?? 0,
          total_tokens: asNumber(row.total_tokens) ?? 0,
          requests: asNumber(row.requests) ?? 0,
          last_used: asNumber(row.last_used),
        } satisfies UsageRow;
      })
      .filter((row): row is UsageRow => row !== null)
      .sort((a, b) => {
        if (b.total_tokens !== a.total_tokens) return b.total_tokens - a.total_tokens;
        return b.requests - a.requests;
      });
  }

  function summarizeScalar(value: unknown): string {
    if (value === null || value === undefined) return '-';
    if (typeof value === 'string') return value.trim() || '-';
    if (typeof value === 'number') return Number.isFinite(value) ? value.toLocaleString() : '-';
    if (typeof value === 'boolean') return value ? t('common.enabled') : t('common.disabled');
    if (Array.isArray(value)) return `${value.length} ${t('instanceDetail.integration.items')}`;

    const record = asRecord(value);
    if (record) {
      const scalarPairs = Object.entries(record)
        .filter(([, entry]) => ['string', 'number', 'boolean'].includes(typeof entry))
        .slice(0, 2)
        .map(([key, entry]) => `${key}=${summarizeScalar(entry)}`);
      if (scalarPairs.length > 0) return scalarPairs.join(' · ');
      return `${Object.keys(record).length} ${t('instanceDetail.integration.fields')}`;
    }

    return String(value);
  }

  function summarizeSnapshotEntries(value: unknown): IntegrationSnapshotEntry[] {
    const record = asRecord(value);
    if (!record) return [];

    return Object.entries(record)
      .slice(0, 12)
      .map(([key, entry]) => ({
        key,
        value: summarizeScalar(entry),
      }));
  }

  function normalizeAvailableTrackers(value: unknown): IntegrationTrackerOption[] {
    if (!Array.isArray(value)) return [];

    return value
      .map((entry) => {
        const record = asRecord(entry);
        if (!record) return null;
        return {
          name: asString(record.name) || '-',
          port: asNumber(record.port),
          running: asBoolean(record.running),
          pipelineCount: Array.isArray(record.pipelines) ? record.pipelines.length : 0,
        } satisfies IntegrationTrackerOption;
      })
      .filter((entry): entry is IntegrationTrackerOption => entry !== null)
      .sort((a, b) => a.name.localeCompare(b.name));
  }

  function normalizeLinkedBoilers(value: unknown): IntegrationLinkedBoiler[] {
    if (!Array.isArray(value)) return [];

    return value
      .map((entry) => {
        const record = asRecord(entry);
        if (!record) return null;
        return {
          name: asString(record.name) || '-',
          port: asNumber(record.port),
          trackerEntries: summarizeSnapshotEntries(record.tracker),
        } satisfies IntegrationLinkedBoiler;
      })
      .filter((entry): entry is IntegrationLinkedBoiler => entry !== null)
      .sort((a, b) => a.name.localeCompare(b.name));
  }

  function resolveRouteRef(): { component: string; name: string } | null {
    const c = (component || '').trim();
    const n = (name || '').trim();
    if (c && n) return { component: c, name: n };

    if (typeof window !== 'undefined') {
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
    return message.includes('404') || message.includes('not found') || message.includes('未找到');
  }

  function readInstanceFromList(
    payload: any,
    targetComponent: string,
    targetName: string,
  ): any | null {
    return payload?.instances?.[targetComponent]?.[targetName] ?? null;
  }

  async function fetchInstanceSnapshot(
    targetComponent: string,
    targetName: string,
  ): Promise<any | null> {
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
      return { latestFailure: '', healthFailures: null as number | null };
    }

    const reversed = [...lines].reverse();
    const latestFailure =
      reversed.find((line) =>
        /(failed|error|health check|restart budget|terminate|startup)/i.test(line),
      ) || '';

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

  async function loadSummary(mode: 'poll' | 'interactive' = 'poll') {
    if (summaryBusy) {
      if (mode === 'interactive') pendingInteractiveRefresh = true;
      return;
    }

    const routeRef = resolveRouteRef();
    if (!routeRef) return;

    summaryBusy = true;
    const requestToken = summaryRequestToken + 1;
    summaryRequestToken = requestToken;
    loadError = '';
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
        agentRouteSummaryState = 'unknown';
        recentSupervisorError = '';
        healthFailuresFromLogs = null;
        return;
      }

      if (!sameInstanceSnapshot(instanceStatus, inst)) {
        instanceStatus = {
          ...(instanceStatus || {}),
          ...inst,
        };
      }

      const shouldFetchOverviewAux = mode === 'interactive' || activeTab === 'overview';
      const shouldFetchUsage = mode === 'interactive' && activeTab === 'usage';
      const shouldFetchIntegration =
        mode === 'interactive' && activeTab === 'integration' && supportsIntegration;
      const shouldFetchAgentRoutes =
        mode === 'interactive' || activeTab === 'agents' || activeTab === 'overview';
      const shouldFetchSupervisorLogs =
        mode === 'interactive' || activeTab === 'logs' || activeTab === 'overview';
      const AUX_TIMEOUT_MS = 6000;

      const [
        healthRes,
        onboardingRes,
        usageRes,
        integrationRes,
        profilesRes,
        bindingsRes,
        supervisorLogsRes,
      ] = await Promise.allSettled([
        shouldFetchOverviewAux
          ? withTimeout(api.getProviderHealth(targetComponent, targetName), AUX_TIMEOUT_MS)
          : Promise.resolve(providerHealth),
        shouldFetchOverviewAux
          ? withTimeout(api.getOnboarding(targetComponent, targetName), AUX_TIMEOUT_MS)
          : Promise.resolve(onboarding),
        shouldFetchUsage
          ? withTimeout(api.getUsage(targetComponent, targetName, usageWindow), AUX_TIMEOUT_MS)
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
          ? withTimeout(api.getLogs(targetComponent, targetName, 120, 'nullhubx'), AUX_TIMEOUT_MS)
          : Promise.resolve(null),
      ]);
      if (requestToken !== summaryRequestToken) return;
      const latest = resolveRouteRef();
      if (!latest || targetComponent !== latest.component || targetName !== latest.name) return;

      if (shouldFetchOverviewAux) {
        providerHealth = healthRes.status === 'fulfilled' ? healthRes.value : null;
        onboarding = onboardingRes.status === 'fulfilled' ? onboardingRes.value : null;
      }
      if (shouldFetchUsage) {
        usage = usageRes.status === 'fulfilled' ? usageRes.value : null;
      }
      if (shouldFetchIntegration) {
        integration = integrationRes.status === 'fulfilled' ? integrationRes.value : null;
      } else if (!supportsIntegration) {
        integration = null;
      }
      if (shouldFetchAgentRoutes) {
        agentProfilesCount =
          profilesRes.status === 'fulfilled' && Array.isArray(profilesRes.value?.profiles)
            ? profilesRes.value.profiles.length
            : null;
        agentBindingsCount =
          bindingsRes.status === 'fulfilled' && Array.isArray(bindingsRes.value?.bindings)
            ? bindingsRes.value.bindings.length
            : null;
        if (profilesRes.status !== 'fulfilled' || bindingsRes.status !== 'fulfilled') {
          agentRouteSummaryState = 'unavailable';
        } else if ((agentProfilesCount ?? 0) === 0) {
          agentRouteSummaryState = 'missing_profiles';
        } else if ((agentBindingsCount ?? 0) === 0) {
          agentRouteSummaryState = 'default_only';
        } else {
          agentRouteSummaryState = 'configured';
        }
      }

      if (shouldFetchSupervisorLogs && supervisorLogsRes.status === 'fulfilled') {
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
        void loadSummary('interactive');
      }
    }
  }

  function startPolling() {
    if (pollTimer) clearInterval(pollTimer);
    pollTimer = setInterval(() => {
      if (activeTab === 'config') return;
      void loadSummary('poll');
    }, 4000);
  }

  function stopPolling() {
    if (pollTimer) clearInterval(pollTimer);
    pollTimer = null;
  }

  async function runControlAction(action: 'stop' | 'update') {
    busyAction = action;
    try {
      if (action === 'stop') await api.stopInstance(component, name);
      if (action === 'update') await api.applyUpdate(component, name);
      await loadSummary('interactive');
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
    launchMode = defaultsLaunchMode || instanceStatus.launch_mode || 'gateway';
    launchVerbose = defaultsVerbose;
    launchPersistDefaults = false;
    launchDialogOpen = true;
  }

  function closeLaunchDialog() {
    if (busyAction === 'start' || busyAction === 'restart') return;
    launchDialogOpen = false;
  }

  function handleLaunchBackdropClick(event: MouseEvent) {
    if (event.target === event.currentTarget) closeLaunchDialog();
  }

  function handleLaunchBackdropKeydown(event: KeyboardEvent) {
    if (event.key === 'Escape' || event.key === 'Enter' || event.key === ' ') {
      event.preventDefault();
      closeLaunchDialog();
    }
  }

  async function confirmLaunchAction() {
    if (busyAction !== null) return;
    if (!instanceStatus) return;
    const mode = launchMode.trim();
    if (mode.length === 0) {
      loadError = t('instanceDetail.launchModeRequired');
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

      if (launchAction === 'start') {
        await api.startInstance(component, name, { launch_mode: mode, verbose: launchVerbose });
      } else {
        await api.restartInstance(component, name, { launch_mode: mode, verbose: launchVerbose });
      }
      launchDialogOpen = false;
      await loadSummary('interactive');
    } catch (err) {
      loadError = normalizeError(err);
    } finally {
      busyAction = null;
    }
  }

  async function saveDefaultSettings() {
    const mode = defaultsLaunchMode.trim();
    if (mode.length === 0) {
      loadError = t('instanceDetail.defaultLaunchModeRequired');
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
      await loadSummary('interactive');
    } catch (err) {
      loadError = normalizeError(err);
    } finally {
      savingDefaults = false;
    }
  }

  function resetDefaultSettingsDraft() {
    if (!instanceStatus) return;
    defaultsAutoStart = !!instanceStatus.auto_start;
    defaultsLaunchMode = instanceStatus.launch_mode || 'gateway';
    defaultsVerbose = !!instanceStatus.verbose;
    defaultsDirty = false;
  }

  async function runDelete() {
    if (busyAction !== null) return;
    const msg = t('instanceDetail.confirmDelete')
      .replace('{component}', component)
      .replace('{name}', name);
    if (!confirm(msg)) return;
    busyAction = 'delete';
    try {
      await api.deleteInstance(component, name);
      await goto('/instances');
    } catch (err) {
      loadError = normalizeError(err);
    } finally {
      busyAction = null;
    }
  }

  function openFailureLogs() {
    activateTab('logs');
    logInitialSource = 'nullhubx';
    logViewerResetToken += 1;
  }

  async function handleAgentsSaved() {
    await loadSummary('interactive');
  }

  function handleAgentRestartRequest() {
    openLaunchDialog('restart');
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

    visitedTabs = ['overview'];
    activeTab = 'overview';
    launchDialogOpen = false;
    instanceMissing = false;
    loadError = '';
    logInitialSource = 'instance';
    logViewerResetToken += 1;
    summaryRequestToken += 1;

    // Sync cache when route changes to avoid flash
    instanceStatus = data.initialStatus;

    void loadSummary('interactive');
  });

  $effect(() => {
    instanceStatus;
    if (instanceStatus && !defaultsDirty) {
      defaultsAutoStart = !!instanceStatus.auto_start;
      defaultsLaunchMode = instanceStatus.launch_mode || 'gateway';
      defaultsVerbose = !!instanceStatus.verbose;
    }
  });

  $effect(() => {
    const tab = activeTab;
    const routeKey = activeRouteKey;
    const currentUsageWindow = usageWindow;

    if (tab !== 'usage' && tab !== 'integration') {
      lastInteractiveAuxKey = '';
      return;
    }

    if (tab === 'integration' && !supportsIntegration) {
      lastInteractiveAuxKey = '';
      integration = null;
      return;
    }

    if (!routeKey) return;

    const refreshKey =
      tab === 'usage' ? `${routeKey}:${tab}:${currentUsageWindow}` : `${routeKey}:${tab}`;
    if (refreshKey === lastInteractiveAuxKey) return;

    lastInteractiveAuxKey = refreshKey;
    void loadSummary('interactive');
  });

  $effect(() => {
    if (supportsIntegration) return;
    if (activeTab === 'integration') {
      activeTab = 'overview';
    }
    if (visitedTabs.includes('integration')) {
      visitedTabs = visitedTabs.filter((tab) => tab !== 'integration');
    }
    integration = null;
  });

  $effect(() => {
    const currentTab = activeTab;
    const previousTab = lastPolledTab;
    lastPolledTab = currentTab;

    if (previousTab === 'config' && currentTab !== 'config') {
      void loadSummary('poll');
    }
  });
</script>

<svelte:head>
  <title>{component}/{name} - {t('instanceDetail.title')} - NullHubX</title>
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
    onBackWorkspace={() => goto('/instances')}
    onOpenStart={() => openLaunchDialog('start')}
    onStop={() => runControlAction('stop')}
    onOpenRestart={() => openLaunchDialog('restart')}
    onUpdate={() => runControlAction('update')}
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
        {t('instanceDetail.notFound')}
      {:else}
        {t('instanceDetail.fetching')}
      {/if}
      <div class="empty-actions">
        <button class="control-btn secondary" type="button" onclick={() => goto('/instances')}
          >{t('instanceDetail.backToWorkspace')}</button
        >
        <button class="control-btn secondary" type="button" onclick={() => goto('/')}
          >{t('instanceDetail.backToOverview')}</button
        >
        <button class="control-btn primary" onclick={() => void loadSummary('interactive')}
          >{t('instanceDetail.retryNow')}</button
        >
      </div>
    </div>
  {:else}
    <nav class="tabs">
      {#each tabs as tab}
        <button
          type="button"
          class:active={activeTab === tab.key}
          onclick={() => activateTab(tab.key)}>{tab.label}</button
        >
      {/each}
    </nav>

    <section class="section-shell panel tab-panel-shell">
      {#if hasVisitedTab('overview')}
        <div class="tab-pane" hidden={activeTab !== 'overview'}>
          <div class="overview-grid">
            <section class="overview-card">
              <div class="overview-card-header">
                <h3>{t('instanceDetail.overview.runtime')}</h3>
              </div>
              <div class="overview-stat-grid">
                <div class="overview-stat">
                  <span>{t('instanceDetail.statusLabel')}</span>
                  <strong>{statusLabel}</strong>
                </div>
                <div class="overview-stat">
                  <span>{t('instanceDetail.overview.pid')}</span>
                  <strong>{instanceStatus.pid ?? '-'}</strong>
                </div>
                <div class="overview-stat">
                  <span>{t('instanceDetail.portLabel')}</span>
                  <strong>{instanceStatus.port ?? '-'}</strong>
                </div>
                <div class="overview-stat">
                  <span>{t('instanceDetail.versionLabel')}</span>
                  <strong>{instanceStatus.version || '-'}</strong>
                </div>
                <div class="overview-stat">
                  <span>{t('instanceDetail.overview.uptime')}</span>
                  <strong>{formatDuration(instanceStatus.uptime_seconds)}</strong>
                </div>
                <div class="overview-stat">
                  <span>{t('instanceDetail.launchMode')}</span>
                  <strong>{instanceStatus.launch_mode || '-'}</strong>
                </div>
                <div class="overview-stat">
                  <span>{t('instanceDetail.autoStart')}</span>
                  <strong>{formatBoolean(instanceStatus.auto_start)}</strong>
                </div>
                <div class="overview-stat">
                  <span>{t('instanceDetail.verboseLog')}</span>
                  <strong>{formatBoolean(instanceStatus.verbose)}</strong>
                </div>
              </div>
            </section>

            <section class="overview-card">
              <div class="overview-card-header">
                <h3>{t('instanceDetail.overview.provider')}</h3>
                {#if providerHealthRecord}
                  <span class={`overview-pill ${providerHealthTone(providerHealthRecord.status)}`}>
                    {String(providerHealthRecord.status || t('instanceDetail.unknown'))}
                  </span>
                {/if}
              </div>

              {#if providerHealthRecord}
                <div class="overview-stat-grid">
                  <div class="overview-stat">
                    <span>{t('instanceDetail.overview.providerName')}</span>
                    <strong>{providerHealthRecord.provider || '-'}</strong>
                  </div>
                  <div class="overview-stat">
                    <span>{t('instanceDetail.overview.model')}</span>
                    <strong>{providerHealthRecord.model || '-'}</strong>
                  </div>
                  <div class="overview-stat">
                    <span>{t('instanceDetail.overview.configured')}</span>
                    <strong>{formatBoolean(providerHealthRecord.configured)}</strong>
                  </div>
                  <div class="overview-stat">
                    <span>{t('instanceDetail.overview.instanceRunning')}</span>
                    <strong>{formatBoolean(providerHealthRecord.running)}</strong>
                  </div>
                  <div class="overview-stat">
                    <span>{t('instanceDetail.overview.liveProbe')}</span>
                    <strong>{formatBoolean(providerHealthRecord.live_ok)}</strong>
                  </div>
                  <div class="overview-stat">
                    <span>{t('instanceDetail.overview.statusCode')}</span>
                    <strong>{providerHealthRecord.status_code ?? '-'}</strong>
                  </div>
                  <div class="overview-stat wide">
                    <span>{t('instanceDetail.overview.reason')}</span>
                    <strong>{formatReason(providerHealthRecord.reason)}</strong>
                  </div>
                </div>
              {:else}
                <p class="overview-empty">{t('common.noData')}</p>
              {/if}
            </section>

            <section class="overview-card">
              <div class="overview-card-header">
                <h3>{t('instanceDetail.overview.onboarding')}</h3>
                <span class="overview-pill neutral">{onboardingStateLabel}</span>
              </div>

              {#if onboardingRecord}
                <div class="overview-stat-grid">
                  <div class="overview-stat">
                    <span>{t('instanceDetail.onboardingStatusLabel')}</span>
                    <strong>{onboardingStateLabel}</strong>
                  </div>
                  <div class="overview-stat">
                    <span>{t('instanceDetail.overview.supported')}</span>
                    <strong>{formatBoolean(onboardingRecord.supported)}</strong>
                  </div>
                  <div class="overview-stat">
                    <span>{t('instanceDetail.overview.bootstrapExists')}</span>
                    <strong>{formatBoolean(onboardingRecord.bootstrap_exists)}</strong>
                  </div>
                  <div class="overview-stat">
                    <span>{t('instanceDetail.overview.seededAt')}</span>
                    <strong>{formatDateTime(onboardingRecord.bootstrap_seeded_at)}</strong>
                  </div>
                  <div class="overview-stat">
                    <span>{t('instanceDetail.overview.completedAt')}</span>
                    <strong>{formatDateTime(onboardingRecord.onboarding_completed_at)}</strong>
                  </div>
                  <div class="overview-stat wide">
                    <span>{t('instanceDetail.overview.starterMessage')}</span>
                    <strong>{onboardingRecord.starter_message || '-'}</strong>
                  </div>
                </div>
              {:else}
                <p class="overview-empty">{t('common.noData')}</p>
              {/if}
            </section>
          </div>
        </div>
      {/if}

      {#if hasVisitedTab('agents')}
        <div class="tab-pane" hidden={activeTab !== 'agents'}>
          <InstanceAgentsPanel
            {component}
            {name}
            active={activeTab === 'agents'}
            runtimeStatus={statusText}
            {canRestart}
            onSaved={handleAgentsSaved}
            onRequestRestart={handleAgentRestartRequest}
          />
        </div>
      {/if}

      {#if hasVisitedTab('config')}
        <div class="tab-pane" hidden={activeTab !== 'config'}>
          <ConfigEditor {component} {name} active={activeTab === 'config'} onAction={loadSummary} />
        </div>
      {/if}

      {#if hasVisitedTab('logs')}
        <div class="tab-pane" hidden={activeTab !== 'logs'}>
          <LogViewer
            {component}
            {name}
            active={activeTab === 'logs'}
            initialSource={logInitialSource}
            resetToken={logViewerResetToken}
          />
        </div>
      {/if}

      {#if hasVisitedTab('usage')}
        <div class="tab-pane" hidden={activeTab !== 'usage'}>
          <div class="usage-shell">
            <div class="usage-toolbar">
              <div class="usage-heading">
                <h3>{t('instanceDetail.tabs.usage')}</h3>
                <p>
                  {t('instanceDetail.usage.generatedAt')}: {formatEpochSeconds(
                    usageRecord?.generated_at,
                  )}
                </p>
              </div>

              <div
                class="usage-window-switch"
                role="tablist"
                aria-label={t('instanceDetail.usage.windowLabel')}
              >
                {#each usageWindowOptions as option}
                  <button
                    type="button"
                    class:active={usageWindow === option.key}
                    onclick={() => {
                      if (usageWindow === option.key) return;
                      usage = null;
                      usageWindow = option.key;
                    }}
                  >
                    {option.label}
                  </button>
                {/each}
              </div>
            </div>

            <div class="usage-summary-grid">
              <div class="usage-summary-card">
                <span>{t('instanceDetail.usage.totalRequests')}</span>
                <strong>{formatCount(usageTotals?.requests)}</strong>
              </div>
              <div class="usage-summary-card">
                <span>{t('instanceDetail.usage.totalTokens')}</span>
                <strong>{formatCount(usageTotals?.total_tokens)}</strong>
              </div>
              <div class="usage-summary-card">
                <span>{t('instanceDetail.usage.promptTokens')}</span>
                <strong>{formatCount(usageTotals?.prompt_tokens)}</strong>
              </div>
              <div class="usage-summary-card">
                <span>{t('instanceDetail.usage.completionTokens')}</span>
                <strong>{formatCount(usageTotals?.completion_tokens)}</strong>
              </div>
            </div>

            {#if usageRows.length > 0}
              <div class="usage-table-wrap">
                <table class="usage-table">
                  <thead>
                    <tr>
                      <th>{t('instanceDetail.usage.provider')}</th>
                      <th>{t('instanceDetail.usage.model')}</th>
                      <th>{t('instanceDetail.usage.requests')}</th>
                      <th>{t('instanceDetail.usage.promptTokens')}</th>
                      <th>{t('instanceDetail.usage.completionTokens')}</th>
                      <th>{t('instanceDetail.usage.totalTokens')}</th>
                      <th>{t('instanceDetail.usage.lastUsed')}</th>
                    </tr>
                  </thead>
                  <tbody>
                    {#each usageRows as row}
                      <tr>
                        <td>{row.provider}</td>
                        <td>{row.model}</td>
                        <td>{formatCount(row.requests)}</td>
                        <td>{formatCount(row.prompt_tokens)}</td>
                        <td>{formatCount(row.completion_tokens)}</td>
                        <td>{formatCount(row.total_tokens)}</td>
                        <td>{formatEpochSeconds(row.last_used)}</td>
                      </tr>
                    {/each}
                  </tbody>
                </table>
              </div>
            {:else}
              <p class="overview-empty">{t('instanceDetail.usage.empty')}</p>
            {/if}
          </div>
        </div>
      {/if}

      {#if hasVisitedTab('history')}
        <div class="tab-pane" hidden={activeTab !== 'history'}>
          <InstanceHistoryPanel {component} {name} active={activeTab === 'history'} />
        </div>
      {/if}

      {#if supportsRuntimeCapabilities && hasVisitedTab('capabilities')}
        <div class="tab-pane" hidden={activeTab !== 'capabilities'}>
          <InstanceCapabilitiesPanel {component} {name} active={activeTab === 'capabilities'} />
        </div>
      {/if}

      {#if hasVisitedTab('memory')}
        <div class="tab-pane" hidden={activeTab !== 'memory'}>
          <InstanceMemoryPanel {component} {name} active={activeTab === 'memory'} />
        </div>
      {/if}

      {#if hasVisitedTab('skills')}
        <div class="tab-pane" hidden={activeTab !== 'skills'}>
          <InstanceSkillsPanel {component} {name} active={activeTab === 'skills'} />
        </div>
      {/if}

      {#if supportsIntegration && hasVisitedTab('integration')}
        <div class="tab-pane" hidden={activeTab !== 'integration'}>
          <div class="integration-shell">
            <div class="integration-heading">
              <h3>{t('instanceDetail.tabs.integration')}</h3>
              <p>{t('instanceDetail.integration.kind')}: {integrationKind || '-'}</p>
            </div>

            {#if integrationKind === 'nullboiler'}
              <div class="integration-grid">
                <section class="integration-card">
                  <div class="integration-card-header">
                    <h4>{t('instanceDetail.integration.linkSummary')}</h4>
                    <span
                      class={`overview-pill ${integrationRecord?.configured ? 'success' : 'neutral'}`}
                    >
                      {integrationRecord?.configured
                        ? t('instanceDetail.integration.configured')
                        : t('instanceDetail.integration.notConfigured')}
                    </span>
                  </div>
                  <div class="overview-stat-grid">
                    <div class="overview-stat">
                      <span>{t('instanceDetail.integration.trackerName')}</span>
                      <strong>{integrationLinkedTracker?.name || '-'}</strong>
                    </div>
                    <div class="overview-stat">
                      <span>{t('instanceDetail.integration.trackerPort')}</span>
                      <strong>{integrationLinkedTracker?.port ?? '-'}</strong>
                    </div>
                    <div class="overview-stat">
                      <span>{t('instanceDetail.integration.pipelineId')}</span>
                      <strong>{integrationCurrentLink?.pipeline_id || '-'}</strong>
                    </div>
                    <div class="overview-stat">
                      <span>{t('instanceDetail.integration.claimRole')}</span>
                      <strong>{integrationCurrentLink?.claim_role || '-'}</strong>
                    </div>
                    <div class="overview-stat">
                      <span>{t('instanceDetail.integration.successTrigger')}</span>
                      <strong>{integrationCurrentLink?.success_trigger || '-'}</strong>
                    </div>
                    <div class="overview-stat">
                      <span>{t('instanceDetail.integration.maxConcurrentTasks')}</span>
                      <strong>{integrationCurrentLink?.max_concurrent_tasks ?? '-'}</strong>
                    </div>
                    <div class="overview-stat">
                      <span>{t('instanceDetail.integration.agentId')}</span>
                      <strong>{integrationCurrentLink?.agent_id || '-'}</strong>
                    </div>
                    <div class="overview-stat">
                      <span>{t('instanceDetail.integration.workflowFile')}</span>
                      <strong>{integrationCurrentLink?.workflow_file || '-'}</strong>
                    </div>
                  </div>
                </section>

                <section class="integration-card">
                  <div class="integration-card-header">
                    <h4>{t('instanceDetail.integration.availableTrackers')}</h4>
                  </div>
                  {#if integrationAvailableTrackers.length > 0}
                    <div class="integration-list">
                      {#each integrationAvailableTrackers as tracker}
                        <article class="integration-list-card">
                          <div class="integration-list-header">
                            <strong>{tracker.name}</strong>
                            <span
                              class={`overview-pill ${tracker.running ? 'success' : 'neutral'}`}
                            >
                              {tracker.running
                                ? t('instanceDetail.integration.running')
                                : t('instanceDetail.integration.stopped')}
                            </span>
                          </div>
                          <div class="integration-list-meta">
                            <span
                              >{t('instanceDetail.integration.trackerPort')}: {tracker.port ??
                                '-'}</span
                            >
                            <span
                              >{t('instanceDetail.integration.pipelineCount')}: {formatCount(
                                tracker.pipelineCount,
                              )}</span
                            >
                          </div>
                        </article>
                      {/each}
                    </div>
                  {:else}
                    <p class="overview-empty">{t('instanceDetail.integration.noTrackers')}</p>
                  {/if}
                </section>

                <section class="integration-card">
                  <div class="integration-card-header">
                    <h4>{t('instanceDetail.integration.trackerSnapshot')}</h4>
                  </div>
                  {#if integrationTrackerEntries.length > 0}
                    <div class="integration-snapshot-grid">
                      {#each integrationTrackerEntries as entry}
                        <div class="integration-snapshot-item">
                          <span>{entry.key}</span>
                          <strong>{entry.value}</strong>
                        </div>
                      {/each}
                    </div>
                  {:else}
                    <p class="overview-empty">
                      {t('instanceDetail.integration.noTrackerSnapshot')}
                    </p>
                  {/if}
                </section>

                <section class="integration-card">
                  <div class="integration-card-header">
                    <h4>{t('instanceDetail.integration.queueSnapshot')}</h4>
                  </div>
                  {#if integrationQueueEntries.length > 0}
                    <div class="integration-snapshot-grid">
                      {#each integrationQueueEntries as entry}
                        <div class="integration-snapshot-item">
                          <span>{entry.key}</span>
                          <strong>{entry.value}</strong>
                        </div>
                      {/each}
                    </div>
                  {:else}
                    <p class="overview-empty">{t('instanceDetail.integration.noQueueSnapshot')}</p>
                  {/if}
                </section>
              </div>
            {:else if integrationKind === 'nulltickets'}
              <div class="integration-grid">
                <section class="integration-card">
                  <div class="integration-card-header">
                    <h4>{t('instanceDetail.integration.queueSnapshot')}</h4>
                  </div>
                  {#if integrationQueueEntries.length > 0}
                    <div class="integration-snapshot-grid">
                      {#each integrationQueueEntries as entry}
                        <div class="integration-snapshot-item">
                          <span>{entry.key}</span>
                          <strong>{entry.value}</strong>
                        </div>
                      {/each}
                    </div>
                  {:else}
                    <p class="overview-empty">{t('instanceDetail.integration.noQueueSnapshot')}</p>
                  {/if}
                </section>

                <section class="integration-card">
                  <div class="integration-card-header">
                    <h4>{t('instanceDetail.integration.linkedBoilers')}</h4>
                  </div>
                  {#if integrationLinkedBoilers.length > 0}
                    <div class="integration-list">
                      {#each integrationLinkedBoilers as boiler}
                        <article class="integration-list-card">
                          <div class="integration-list-header">
                            <strong>{boiler.name}</strong>
                            <span class="overview-pill neutral">
                              {t('instanceDetail.integration.trackerPort')}: {boiler.port ?? '-'}
                            </span>
                          </div>

                          {#if boiler.trackerEntries.length > 0}
                            <div class="integration-snapshot-grid compact">
                              {#each boiler.trackerEntries as entry}
                                <div class="integration-snapshot-item">
                                  <span>{entry.key}</span>
                                  <strong>{entry.value}</strong>
                                </div>
                              {/each}
                            </div>
                          {:else}
                            <p class="overview-empty">
                              {t('instanceDetail.integration.noTrackerSnapshot')}
                            </p>
                          {/if}
                        </article>
                      {/each}
                    </div>
                  {:else}
                    <p class="overview-empty">{t('instanceDetail.integration.noLinkedBoilers')}</p>
                  {/if}
                </section>
              </div>
            {:else}
              <p class="overview-empty">{t('common.noData')}</p>
            {/if}
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
    aria-label={t('instanceDetail.closeLaunchDialog')}
    onclick={handleLaunchBackdropClick}
    onkeydown={handleLaunchBackdropKeydown}
  >
    <div class="modal" role="dialog" aria-modal="true" aria-labelledby="launch-dialog-title">
      <h3 id="launch-dialog-title">
        {launchAction === 'start'
          ? t('instanceDetail.launchDialog.start')
          : t('instanceDetail.launchDialog.restart')}
      </h3>
      <p class="modal-desc">{t('instanceDetail.launchDialogDesc')}</p>

      <label class="field">
        <span>{t('instanceDetail.launchDialog.launchMode')}</span>
        <input
          type="text"
          bind:value={launchMode}
          placeholder={t('instanceDetail.launchModePlaceholder')}
        />
      </label>

      <label class="field-toggle">
        <input type="checkbox" bind:checked={launchVerbose} />
        <span>{t('instanceDetail.launchDialog.verbose')}</span>
      </label>

      <label class="field-toggle persist">
        <input type="checkbox" bind:checked={launchPersistDefaults} />
        <span>{t('instanceDetail.launchDialog.persistDefaults')}</span>
      </label>

      <div class="modal-actions">
        <button
          class="control-btn secondary"
          onclick={closeLaunchDialog}
          disabled={busyAction === 'start' || busyAction === 'restart'}
        >
          {t('instanceDetail.launchDialog.cancel')}
        </button>
        <button
          class="control-btn primary"
          onclick={confirmLaunchAction}
          disabled={busyAction === 'start' || busyAction === 'restart'}
        >
          {busyAction === launchAction
            ? t('instanceDetail.executing')
            : launchAction === 'start'
              ? t('instanceDetail.confirmStart')
              : t('instanceDetail.confirmRestart')}
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

  .tab-panel-shell .overview-card h3 {
    color: var(--shell-text);
    font-size: var(--text-sm);
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }

  .overview-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
    gap: var(--spacing-md);
  }

  .overview-card {
    display: flex;
    flex-direction: column;
    gap: 0.95rem;
    padding: 1rem 1.05rem;
    border: 1px solid rgba(116, 136, 173, 0.2);
    border-radius: var(--radius-lg);
    background: linear-gradient(180deg, rgba(12, 19, 33, 0.82), rgba(16, 25, 42, 0.76));
    box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.03);
  }

  .overview-card-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 0.75rem;
    flex-wrap: wrap;
  }

  .overview-card h3 {
    margin: 0;
  }

  .overview-stat-grid {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 0.75rem;
  }

  .overview-stat {
    display: flex;
    flex-direction: column;
    gap: 0.22rem;
    min-width: 0;
    padding: 0.72rem 0.78rem;
    border: 1px solid rgba(116, 136, 173, 0.16);
    border-radius: var(--radius-md);
    background: rgba(255, 255, 255, 0.04);
  }

  .overview-stat.wide {
    grid-column: 1 / -1;
  }

  .overview-stat span {
    font-size: 0.72rem;
    letter-spacing: 0.04em;
    text-transform: uppercase;
    color: var(--shell-text-dim);
  }

  .overview-stat strong {
    min-width: 0;
    font-size: 0.96rem;
    line-height: 1.45;
    color: var(--shell-text);
    overflow-wrap: anywhere;
  }

  .overview-pill {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    min-height: 28px;
    padding: 0.2rem 0.65rem;
    border-radius: 999px;
    border: 1px solid rgba(116, 136, 173, 0.2);
    background: rgba(255, 255, 255, 0.05);
    color: var(--shell-text);
    font-size: 0.74rem;
    letter-spacing: 0.04em;
    text-transform: uppercase;
  }

  .overview-pill.success {
    border-color: rgba(16, 185, 129, 0.28);
    background: rgba(10, 48, 37, 0.4);
    color: #9af3cf;
  }

  .overview-pill.error {
    border-color: rgba(245, 158, 11, 0.28);
    background: rgba(58, 36, 14, 0.4);
    color: #ffd089;
  }

  .overview-pill.neutral {
    color: var(--shell-text-dim);
  }

  .overview-empty {
    margin: 0;
    padding: 0.95rem 1rem;
    border: 1px solid rgba(116, 136, 173, 0.18);
    border-radius: var(--radius-md);
    background: rgba(255, 255, 255, 0.04);
    color: var(--shell-text-dim);
  }

  .usage-shell {
    display: flex;
    flex-direction: column;
    gap: 1rem;
  }

  .usage-toolbar {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: 1rem;
    flex-wrap: wrap;
  }

  .usage-heading h3 {
    margin: 0;
    color: var(--shell-text);
    font-size: var(--text-sm);
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }

  .usage-heading p {
    margin: 0.28rem 0 0;
    color: var(--shell-text-dim);
    font-size: 0.8rem;
  }

  .usage-window-switch {
    display: inline-flex;
    flex-wrap: wrap;
    gap: 0.45rem;
  }

  .usage-window-switch button {
    border: 1px solid rgba(116, 136, 173, 0.22);
    background: rgba(255, 255, 255, 0.05);
    color: var(--shell-text-dim);
    border-radius: 999px;
    min-height: 34px;
    padding: 0.45rem 0.85rem;
    font-size: 0.78rem;
    letter-spacing: 0.04em;
    transition:
      color var(--transition-fast),
      background-color var(--transition-fast),
      border-color var(--transition-fast);
  }

  .usage-window-switch button.active {
    border-color: rgba(34, 211, 238, 0.28);
    background: rgba(34, 211, 238, 0.12);
    color: var(--shell-text);
  }

  .usage-summary-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
    gap: 0.8rem;
  }

  .usage-summary-card {
    display: flex;
    flex-direction: column;
    gap: 0.28rem;
    padding: 0.9rem 0.95rem;
    border: 1px solid rgba(116, 136, 173, 0.18);
    border-radius: var(--radius-lg);
    background: linear-gradient(180deg, rgba(12, 19, 33, 0.82), rgba(16, 25, 42, 0.76));
    box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.03);
  }

  .usage-summary-card span {
    font-size: 0.72rem;
    letter-spacing: 0.04em;
    text-transform: uppercase;
    color: var(--shell-text-dim);
  }

  .usage-summary-card strong {
    color: var(--shell-text);
    font-size: 1.08rem;
    line-height: 1.3;
  }

  .usage-table-wrap {
    overflow-x: auto;
    border: 1px solid rgba(116, 136, 173, 0.18);
    border-radius: var(--radius-lg);
    background: linear-gradient(180deg, rgba(12, 19, 33, 0.82), rgba(16, 25, 42, 0.76));
    box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.03);
  }

  .usage-table {
    width: 100%;
    border-collapse: collapse;
    min-width: 760px;
  }

  .usage-table th,
  .usage-table td {
    padding: 0.82rem 0.9rem;
    text-align: left;
    border-bottom: 1px solid rgba(116, 136, 173, 0.14);
    font-size: 0.88rem;
  }

  .usage-table th {
    color: var(--shell-text-dim);
    font-size: 0.72rem;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    background: rgba(255, 255, 255, 0.04);
    white-space: nowrap;
  }

  .usage-table td {
    color: var(--shell-text);
    vertical-align: top;
    overflow-wrap: anywhere;
  }

  .usage-table tbody tr:hover {
    background: rgba(34, 211, 238, 0.06);
  }

  .usage-table tbody tr:last-child td {
    border-bottom: none;
  }

  .integration-shell {
    display: flex;
    flex-direction: column;
    gap: 1rem;
  }

  .integration-heading h3 {
    margin: 0;
    color: var(--shell-text);
    font-size: var(--text-sm);
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }

  .integration-heading p {
    margin: 0.28rem 0 0;
    color: var(--shell-text-dim);
    font-size: 0.8rem;
  }

  .integration-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
    gap: 0.9rem;
  }

  .integration-card {
    display: flex;
    flex-direction: column;
    gap: 0.9rem;
    padding: 1rem 1.05rem;
    border: 1px solid rgba(116, 136, 173, 0.2);
    border-radius: var(--radius-lg);
    background: linear-gradient(180deg, rgba(12, 19, 33, 0.82), rgba(16, 25, 42, 0.76));
    box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.03);
  }

  .integration-card-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 0.75rem;
    flex-wrap: wrap;
  }

  .integration-card h4 {
    margin: 0;
    color: var(--shell-text);
    font-size: 0.86rem;
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }

  .integration-list {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
  }

  .integration-list-card {
    display: flex;
    flex-direction: column;
    gap: 0.7rem;
    padding: 0.85rem 0.9rem;
    border: 1px solid rgba(116, 136, 173, 0.16);
    border-radius: var(--radius-md);
    background: rgba(255, 255, 255, 0.04);
  }

  .integration-list-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 0.75rem;
    flex-wrap: wrap;
  }

  .integration-list-header strong {
    color: var(--shell-text);
    font-size: 0.96rem;
    overflow-wrap: anywhere;
  }

  .integration-list-meta {
    display: flex;
    flex-wrap: wrap;
    gap: 0.8rem;
    color: var(--shell-text-dim);
    font-size: 0.82rem;
  }

  .integration-snapshot-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
    gap: 0.7rem;
  }

  .integration-snapshot-grid.compact {
    grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
  }

  .integration-snapshot-item {
    display: flex;
    flex-direction: column;
    gap: 0.22rem;
    min-width: 0;
    padding: 0.72rem 0.78rem;
    border: 1px solid rgba(116, 136, 173, 0.16);
    border-radius: var(--radius-md);
    background: rgba(255, 255, 255, 0.04);
  }

  .integration-snapshot-item span {
    font-family: var(--font-mono);
    font-size: 0.72rem;
    color: var(--shell-text-dim);
    overflow-wrap: anywhere;
  }

  .integration-snapshot-item strong {
    color: var(--shell-text);
    font-size: 0.9rem;
    line-height: 1.45;
    overflow-wrap: anywhere;
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

    .overview-stat-grid {
      grid-template-columns: 1fr;
    }

    .usage-window-switch {
      width: 100%;
    }

    .integration-list-header {
      align-items: flex-start;
    }
  }
</style>
