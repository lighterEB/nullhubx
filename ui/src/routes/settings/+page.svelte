<script lang="ts">
  import { api, type JsonObject, type ServiceStatusResponse } from "$lib/api/client";
  import { t } from "$lib/i18n/index.svelte";
  import type { PageData } from "./$types";

  type ServiceInfo = {
    status: string;
    message: string;
    registered: boolean;
    running: boolean;
    service_type: string;
    unit_path: string;
  };

  type SettingsPayload = JsonObject & {
    port?: number;
    host?: string;
    auth_token?: string | null;
    auto_update_check?: boolean;
    access?: JsonObject | null;
  };

  let { data }: { data: PageData } = $props();

  const defaultSettings: SettingsPayload = {
    port: 19800,
    host: "127.0.0.1",
    auth_token: null,
    auto_update_check: true,
    access: null,
  };

  const initialSettings = (() => {
    const pageData = data;
    return {
      ...defaultSettings,
      ...(((pageData.settings as SettingsPayload | null) ?? {})),
    };
  })();
  const initialSettingsReady = (() => {
    const pageData = data;
    return Boolean(pageData.settings);
  })();
  const initialSettingsLoadError = (() => {
    const pageData = data;
    return pageData.settingsLoadError || "";
  })();
  const initialService: ServiceInfo = (() => {
    const pageData = data;
    return {
      status: typeof pageData.serviceStatus?.status === "string" ? pageData.serviceStatus.status : "ok",
      message:
        typeof pageData.serviceStatus?.message === "string"
          ? pageData.serviceStatus.message
          : pageData.serviceStatusError || "",
      registered: !!pageData.serviceStatus?.registered,
      running: !!pageData.serviceStatus?.running,
      service_type:
        typeof pageData.serviceStatus?.service_type === "string" ? pageData.serviceStatus.service_type : "",
      unit_path:
        typeof pageData.serviceStatus?.unit_path === "string" ? pageData.serviceStatus.unit_path : "",
    };
  })();

  let settings = $state<SettingsPayload>(initialSettings);
  let saving = $state(false);
  let settingsInitializing = $state(false);
  let settingsReady = $state(initialSettingsReady);
  let settingsLoadError = $state(initialSettingsLoadError);
  let serviceLoading = $state(false);
  let messageTone = $state<"success" | "error">("success");
  let message = $state("");
  let service = $state<ServiceInfo>(initialService);

  const serviceButtonLabel = $derived.by(() => {
    if (serviceLoading) {
      return t('common.loading');
    }
    return service.registered ? t('settings.disableAutostart') : t('settings.enableAutostart');
  });

  async function initializePage() {
    settingsInitializing = true;
    settingsLoadError = "";

    const [settingsResult, serviceResult] = await Promise.allSettled([
      api.getSettings(),
      api.serviceStatus(),
    ]);

    if (settingsResult.status === "fulfilled") {
      settings = settingsResult.value as SettingsPayload;
      settingsReady = true;
    } else {
      settingsReady = false;
      settingsLoadError = (settingsResult.reason as Error)?.message || t('error.requestFailed');
    }

    if (serviceResult.status === "fulfilled") {
      applyServiceStatus(serviceResult.value);
    } else {
      applyServiceStatus({
        status: "error",
        message: (serviceResult.reason as Error)?.message || t('settings.serviceStatusLoadFailed'),
      });
    }

    settingsInitializing = false;
  }

  function setMessage(text: string, tone: "success" | "error" = "success") {
    message = text;
    messageTone = tone;
  }

  function applyServiceStatus(data: ServiceStatusResponse | null | undefined) {
    service = {
      status: typeof data?.status === "string" ? data.status : "ok",
      message: typeof data?.message === "string" ? data.message : "",
      registered: !!data?.registered,
      running: !!data?.running,
      service_type: typeof data?.service_type === "string" ? data.service_type : "",
      unit_path: typeof data?.unit_path === "string" ? data.unit_path : "",
    };
  }

  async function refreshServiceStatus(showErrorMessage = true) {
    serviceLoading = true;
    try {
      const data = await api.serviceStatus();
      applyServiceStatus(data);
      if (data?.status === "error" && showErrorMessage) {
        setMessage(data?.message || t('settings.serviceStatusLoadFailed'), "error");
      }
    } catch (e) {
      applyServiceStatus({ status: "error", message: (e as Error).message || t('settings.serviceStatusLoadFailed') });
      if (showErrorMessage) setMessage(t('settings.error').replace('{message}', (e as Error).message), "error");
    } finally {
      serviceLoading = false;
    }
  }

  async function toggleService() {
    const enabling = !service.registered;
    serviceLoading = true;
    try {
      const data = enabling ? await api.serviceInstall() : await api.serviceUninstall();
      applyServiceStatus(data);
      if (data?.status === "error") {
        setMessage(data?.message || t('settings.serviceStatusUpdateFailed'), "error");
        return;
      }
      await refreshServiceStatus(false);
      setMessage(data?.message || (enabling ? t('settings.serviceEnabled') : t('settings.serviceDisabled')));
    } catch (e) {
      setMessage(t('settings.error').replace('{message}', (e as Error).message), "error");
    } finally {
      serviceLoading = false;
    }
  }

  async function save() {
    saving = true;
    try {
      const { access: _access, ...payload } = settings;
      await api.putSettings(payload);
      setMessage(t('settings.settingsSaved'));
    } catch (e) {
      setMessage(t('settings.error').replace('{message}', (e as Error).message), "error");
    } finally {
      saving = false;
    }
  }
</script>

<svelte:head>
  <title>{t('nav.settings')} - NullHubX</title>
</svelte:head>

<div class="page-shell narrow settings-page">
  <section class="section-shell hero-shell">
    <div class="page-hero">
      <div class="page-title-group">
        <span class="page-kicker">NullHubX</span>
        <h1 class="page-title">{t('settings.title')}</h1>
        <p class="page-subtitle">{t('settings.subtitle')}</p>
      </div>
      <div class="page-actions">
        <span class="surface-chip status-summary" class:is-active={service.registered}>
          {t('settings.autostart')}: {service.registered ? t('settings.enabled') : t('settings.disabled')}
        </span>
        <span class="surface-chip status-summary" class:is-running={service.running}>
          {t('settings.serviceStatus')}: {service.running ? t('settings.running') : t('settings.stopped')}
        </span>
      </div>
    </div>
  </section>

  {#if message}
    <div class="feedback-banner" class:error={messageTone === "error"}>
      {#if messageTone === "success"}
        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><polyline points="22 4 12 14.01 9 11.01"/></svg>
      {:else}
        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>
      {/if}
      <span>{message}</span>
    </div>
  {/if}

  {#if settingsInitializing}
    <section class="section-shell settings-loading-shell" aria-busy="true">
      <h2>{t('common.loading')}</h2>
      <p>{t('settings.subtitle')}</p>
    </section>
  {:else if !settingsReady}
    <section class="section-shell settings-loading-shell">
      <h2>{t('error.requestFailed')}</h2>
      <p>{settingsLoadError || t('error.requestFailed')}</p>
      <div class="service-actions">
        <button class="control-btn primary service-btn" onclick={() => void initializePage()}>
          {t('instanceDetail.retryNow')}
        </button>
      </div>
    </section>
  {:else}
    <div class="settings-grid">
      <section class="section-shell settings-section">
        <div class="settings-section-head">
          <h2>{t('settings.server')}</h2>
        </div>
        <div class="field">
          <label for="settings-port">{t('settings.port')}</label>
          <input id="settings-port" type="number" bind:value={settings.port} />
          <p class="hint">{t('settings.portHint')}</p>
        </div>
        <div class="field">
          <label for="settings-host">{t('settings.host')}</label>
          <input id="settings-host" type="text" bind:value={settings.host} />
          <p class="hint">{t('settings.hostHint')}</p>
        </div>
      </section>

      <section class="section-shell settings-section">
        <div class="settings-section-head">
          <h2>{t('settings.security')}</h2>
        </div>
        <div class="field">
          <label for="settings-auth-token">{t('settings.authToken')}</label>
          <input id="settings-auth-token" type="password" bind:value={settings.auth_token} placeholder="" />
          <p class="hint">{t('settings.authTokenHint')}</p>
        </div>
      </section>

      <section class="section-shell settings-section updates-section">
        <div class="settings-section-head">
          <h2>{t('settings.updates')}</h2>
        </div>
        <label class="toggle-field">
          <input type="checkbox" bind:checked={settings.auto_update_check} />
          <span class="toggle-slider"></span>
          <span class="toggle-label">{t('settings.autoUpdateCheck')}</span>
        </label>
      </section>

      <section class="section-shell settings-section service-section">
        <div class="settings-section-head">
          <h2>{t('settings.service')}</h2>
          <p class="section-hint">{t('settings.serviceHint')}</p>
        </div>

        <div class="service-panel">
          <div class="service-row">
            <span class="service-label">{t('settings.autostart')}</span>
            <span class="service-badge" class:active={service.registered}>
              {service.registered ? t('settings.enabled') : t('settings.disabled')}
            </span>
          </div>
          <div class="service-row">
            <span class="service-label">{t('settings.serviceStatus')}</span>
            <span class="service-badge" class:active={service.running}>
              {service.running ? t('settings.running') : t('settings.stopped')}
            </span>
          </div>
          {#if service.service_type}
            <div class="service-detail">
              <span class="service-label">{t('settings.serviceType')}</span>
              <code>{service.service_type}</code>
            </div>
          {/if}
          {#if service.unit_path}
            <div class="service-detail">
              <span class="service-label">{t('settings.unitPath')}</span>
              <code>{service.unit_path}</code>
            </div>
          {/if}
          <div class="service-actions">
            <button class="control-btn primary service-btn" onclick={toggleService} disabled={serviceLoading}>
              {serviceButtonLabel}
            </button>
            <button class="control-btn secondary service-btn" onclick={() => refreshServiceStatus()} disabled={serviceLoading}>
              {t('common.refresh')}
            </button>
          </div>
        </div>
      </section>

      <div class="section-shell actions-shell">
        <button class="control-btn primary save-btn" onclick={save} disabled={saving}>
          {saving ? t('settings.saving') : t('settings.saveSettings')}
        </button>
      </div>
    </div>
  {/if}
</div>

<style>
  .feedback-banner {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm);
    padding: var(--spacing-md) var(--spacing-lg);
    border-radius: var(--radius-lg);
    border: 1px solid rgba(16, 185, 129, 0.18);
    background: rgba(236, 253, 245, 0.84);
    color: var(--emerald-700);
    box-shadow: var(--shadow-sm);
  }

  .feedback-banner.error {
    border-color: rgba(244, 63, 94, 0.16);
    background: rgba(255, 241, 245, 0.82);
    color: var(--red-700);
  }

  .feedback-banner :global(*) {
    min-width: 0;
    overflow-wrap: anywhere;
  }

  .status-summary {
    max-width: 100%;
    white-space: normal;
    overflow-wrap: anywhere;
  }

  .status-summary.is-active {
    border-color: rgba(16, 185, 129, 0.18);
    background: rgba(236, 253, 245, 0.78);
    color: var(--emerald-700);
  }

  .status-summary.is-running {
    border-color: rgba(34, 211, 238, 0.2);
    background: rgba(239, 250, 255, 0.82);
    color: var(--cyan-700, var(--cyan-600));
  }

  .settings-loading-shell {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-sm);
    min-height: 220px;
    justify-content: center;
  }

  .settings-loading-shell h2,
  .settings-loading-shell p {
    margin: 0;
  }

  .settings-grid {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: var(--spacing-lg);
  }

  .settings-section {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-md);
  }

  .updates-section,
  .service-section,
  .actions-shell {
    grid-column: 1 / -1;
  }

  .settings-section-head {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-xs);
  }

  .settings-section-head h2 {
    margin: 0;
    color: var(--slate-900);
    font-size: var(--text-lg);
  }

  .section-hint {
    margin: 0;
    color: var(--slate-600);
    font-size: var(--text-sm);
    line-height: 1.6;
  }

  .field {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-xs);
  }

  .field + .field {
    margin-top: var(--spacing-sm);
  }

  .field label {
    color: var(--slate-700);
    font-size: var(--text-sm);
    font-weight: 600;
  }

  .field input[type="text"],
  .field input[type="number"],
  .field input[type="password"] {
    width: 100%;
    font-family: var(--font-sans);
  }

  .hint {
    margin: 0;
    color: var(--slate-500);
    font-size: var(--text-xs);
    line-height: 1.5;
  }

  .toggle-field {
    display: flex;
    align-items: center;
    gap: var(--spacing-md);
    padding: var(--spacing-md);
    border-radius: var(--radius-lg);
    border: 1px solid rgba(141, 154, 178, 0.18);
    background: rgba(255, 255, 255, 0.6);
    cursor: pointer;
  }

  .toggle-field input {
    display: none;
  }

  .toggle-slider {
    position: relative;
    width: 44px;
    height: 24px;
    background: rgba(141, 154, 178, 0.34);
    border-radius: 12px;
    transition:
      background-color var(--transition-fast),
      box-shadow var(--transition-fast);
  }

  .toggle-slider::before {
    content: "";
    position: absolute;
    width: 18px;
    height: 18px;
    left: 3px;
    top: 3px;
    background: rgba(255, 255, 255, 0.96);
    border-radius: 50%;
    transition:
      transform var(--transition-fast),
      background-color var(--transition-fast),
      box-shadow var(--transition-fast);
    box-shadow: var(--shadow-sm);
  }

  .toggle-field input:checked + .toggle-slider {
    background: linear-gradient(135deg, rgba(34, 211, 238, 0.84), rgba(139, 92, 246, 0.84));
  }

  .toggle-field input:checked + .toggle-slider::before {
    transform: translateX(20px);
  }

  .toggle-label {
    font-size: var(--text-sm);
    color: var(--slate-700);
    line-height: 1.5;
  }

  .service-panel {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: var(--spacing-md);
    padding: var(--spacing-lg);
    border-radius: var(--radius-lg);
    border: 1px solid rgba(141, 154, 178, 0.16);
    background: rgba(255, 255, 255, 0.58);
  }

  .service-row {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
    flex-wrap: wrap;
    gap: var(--spacing-sm);
  }

  .service-label {
    min-width: 0;
    font-size: var(--text-xs);
    color: var(--slate-500);
    text-transform: uppercase;
    letter-spacing: 0.08em;
    font-weight: 600;
    overflow-wrap: anywhere;
  }

  .service-badge {
    min-width: 0;
    max-width: 100%;
    font-size: var(--text-xs);
    font-weight: 600;
    padding: 5px 10px;
    background: rgba(255, 255, 255, 0.84);
    color: var(--slate-500);
    border-radius: 999px;
    border: 1px solid rgba(141, 154, 178, 0.18);
    text-transform: uppercase;
    letter-spacing: 0.06em;
    white-space: normal;
    overflow-wrap: anywhere;
  }

  .service-badge.active {
    background: rgba(236, 253, 245, 0.78);
    border-color: rgba(16, 185, 129, 0.18);
    color: var(--emerald-700);
  }

  .service-detail {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-xs);
    grid-column: span 2;
  }

  .service-detail code {
    font-family: var(--font-mono);
    font-size: var(--text-sm);
    color: var(--slate-700);
    word-break: break-all;
  }

  .service-actions {
    display: flex;
    gap: var(--spacing-sm);
    margin-top: var(--spacing-sm);
    grid-column: span 2;
    flex-wrap: wrap;
  }

  .service-btn {
    min-width: 160px;
  }

  .actions-shell {
    display: flex;
    justify-content: flex-end;
  }

  .save-btn {
    min-width: 180px;
  }

  @media (max-width: 900px) {
    .settings-grid {
      grid-template-columns: 1fr;
    }

    .updates-section,
    .service-section,
    .actions-shell {
      grid-column: auto;
    }

    .service-panel {
      grid-template-columns: 1fr;
    }

    .service-detail,
    .service-actions {
      grid-column: auto;
    }
  }

  @media (max-width: 680px) {
    .service-actions {
      flex-direction: column;
    }

    .service-btn,
    .save-btn {
      width: 100%;
    }
  }
</style>
