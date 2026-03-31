<script lang="ts">
  import { t } from "$lib/i18n/index.svelte";
  import StatusBadge from "$lib/components/StatusBadge.svelte";

  type BusyAction = "start" | "stop" | "restart" | "update" | "delete" | null;
  type AgentRouteSummaryState = "configured" | "default_only" | "missing_profiles" | "unavailable" | "unknown";

  let {
    component,
    name,
    isValidInstance,
    instanceStatus,
    statusText,
    statusLabel,
    recentSupervisorError,
    providerHealth,
    onboarding,
    agentProfilesCount,
    agentBindingsCount,
    agentRouteSummaryState,
    restartCount,
    healthFailureCount,
    defaultsAutoStart,
    defaultsLaunchMode,
    defaultsVerbose,
    defaultsDirty,
    savingDefaults,
    busyAction,
    canStart,
    canStop,
    canRestart,
    onBackWorkspace,
    onOpenStart,
    onStop,
    onOpenRestart,
    onUpdate,
    onDelete,
    onOpenFailureLogs,
    onDefaultsAutoStartChange,
    onDefaultsLaunchModeChange,
    onDefaultsVerboseChange,
    onSaveDefaults,
    onResetDefaults,
  }: {
    component: string;
    name: string;
    isValidInstance: boolean;
    instanceStatus: Record<string, unknown> | null;
    statusText: string;
    statusLabel: string;
    recentSupervisorError: string;
    providerHealth: Record<string, unknown> | null;
    onboarding: Record<string, unknown> | null;
    agentProfilesCount: number | null;
    agentBindingsCount: number | null;
    agentRouteSummaryState: AgentRouteSummaryState;
    restartCount: number;
    healthFailureCount: number;
    defaultsAutoStart: boolean;
    defaultsLaunchMode: string;
    defaultsVerbose: boolean;
    defaultsDirty: boolean;
    savingDefaults: boolean;
    busyAction: BusyAction;
    canStart: boolean;
    canStop: boolean;
    canRestart: boolean;
    onBackWorkspace: () => void;
    onOpenStart: () => void;
    onStop: () => void;
    onOpenRestart: () => void;
    onUpdate: () => void;
    onDelete: () => void;
    onOpenFailureLogs: () => void;
    onDefaultsAutoStartChange: (checked: boolean) => void;
    onDefaultsLaunchModeChange: (value: string) => void;
    onDefaultsVerboseChange: (checked: boolean) => void;
    onSaveDefaults: () => void;
    onResetDefaults: () => void;
  } = $props();
</script>

<section class="section-shell hero-shell">
  <div class="instance-header">
    <div class="header-left">
      <button class="control-btn secondary back-link" type="button" onclick={onBackWorkspace}>
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
      <button class="control-btn primary" onclick={onOpenStart} disabled={busyAction !== null || !canStart || !instanceStatus}>
        {busyAction === "start" ? t("instanceDetail.starting") : t("instanceDetail.start")}
      </button>
      <button class="control-btn warning" onclick={onStop} disabled={busyAction !== null || !canStop || !instanceStatus}>
        {busyAction === "stop" ? t("instanceDetail.stopping") : t("instanceDetail.stop")}
      </button>
      <button class="control-btn secondary" onclick={onOpenRestart} disabled={busyAction !== null || !canRestart || !instanceStatus}>
        {busyAction === "restart" ? t("instanceDetail.restarting") : t("instanceDetail.restart")}
      </button>
      <button class="control-btn secondary" onclick={onUpdate} disabled={busyAction !== null || !instanceStatus}>
        {busyAction === "update" ? t("instanceDetail.updating") : t("instanceDetail.update")}
      </button>
      <button class="control-btn danger" onclick={onDelete} disabled={busyAction !== null || !instanceStatus}>
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
    <button class="control-btn warning failed-log-btn" onclick={onOpenFailureLogs}>{t("instanceDetail.viewFailureLogs")}</button>
  </div>
{/if}

{#if instanceStatus}
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
        <strong>{String(instanceStatus.version || "-")}</strong>
      </div>
      <div class="summary-card">
        <span class="label">{t("instanceDetail.portLabel")}</span>
        <strong>{String(instanceStatus.port || "-")}</strong>
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
        <strong>{String(providerHealth?.status || t("instanceDetail.unknown"))}</strong>
      </div>
      <div class="summary-card">
        <span class="label">{t("instanceDetail.onboardingStatusLabel")}</span>
        <strong>
          {onboarding?.pending
            ? t("instanceDetail.pending")
            : onboarding?.completed
              ? t("instanceDetail.completed")
              : t("instanceDetail.unknown")}
        </strong>
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
        <input type="checkbox" checked={defaultsAutoStart} onchange={(e) => onDefaultsAutoStartChange(e.currentTarget.checked)} />
        <span>{t("instanceDetail.autoStart")}</span>
      </label>

      <label class="field">
        <span>{t("instanceDetail.launchMode")}</span>
        <input
          type="text"
          value={defaultsLaunchMode}
          oninput={(e) => onDefaultsLaunchModeChange(e.currentTarget.value)}
          placeholder={t("instanceDetail.launchModePlaceholder")}
        />
      </label>

      <label class="field-toggle">
        <input type="checkbox" checked={defaultsVerbose} onchange={(e) => onDefaultsVerboseChange(e.currentTarget.checked)} />
        <span>{t("instanceDetail.verboseLog")}</span>
      </label>
    </div>
    <div class="runtime-actions">
      <button class="control-btn primary" onclick={onSaveDefaults} disabled={!defaultsDirty || savingDefaults}>
        {savingDefaults ? t("instanceDetail.savingDefaults") : t("instanceDetail.saveDefaults")}
      </button>
      <button class="control-btn secondary" onclick={onResetDefaults} disabled={!defaultsDirty || savingDefaults}>
        {t("instanceDetail.resetChanges")}
      </button>
    </div>
  </section>
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
    flex-wrap: wrap;
  }

  .header-left {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-md);
    min-width: 0;
  }

  .back-link {
    width: fit-content;
  }

  .title-stack {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-sm);
    min-width: 0;
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
    flex-wrap: wrap;
    border-color: rgba(245, 158, 11, 0.2);
    background: linear-gradient(180deg, rgba(255, 251, 235, 0.92), rgba(255, 247, 237, 0.84));
    color: #9a3412;
  }

  .failed-banner h3 {
    margin: 0;
    font-size: var(--text-base);
    overflow-wrap: anywhere;
  }

  .failed-banner p {
    margin: 0.2rem 0 0 0;
    font-size: var(--text-sm);
    overflow-wrap: anywhere;
  }

  .failed-detail {
    font-family: var(--font-mono);
    opacity: 0.85;
    overflow-wrap: anywhere;
  }

  .failed-log-btn {
    white-space: normal;
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
    overflow-wrap: anywhere;
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
  }
</style>
