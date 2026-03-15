<script lang="ts">
  import { onMount } from "svelte";
  import { api } from "$lib/api/client";

  type ServiceInfo = {
    status: string;
    message: string;
    registered: boolean;
    running: boolean;
    service_type: string;
    unit_path: string;
  };

  let settings = $state<any>({
    port: 19800,
    host: "127.0.0.1",
    auth_token: null,
    auto_update_check: true,
    access: null,
  });
  let saving = $state(false);
  let serviceLoading = $state(false);
  let serviceAction = $state<"status" | "install" | "uninstall" | null>(null);
  let messageTone = $state<"success" | "error">("success");
  let message = $state("");
  let service = $state<ServiceInfo>({
    status: "ok",
    message: "",
    registered: false,
    running: false,
    service_type: "",
    unit_path: "",
  });

  const serviceButtonLabel = $derived.by(() => {
    if (serviceLoading) {
      if (serviceAction === "install") return "Enabling...";
      if (serviceAction === "uninstall") return "Disabling...";
      return "Checking...";
    }
    return service.registered ? "Disable Autostart" : "Enable Autostart";
  });

  onMount(async () => {
    try {
      settings = await api.getSettings();
    } catch (e) {
      console.error(e);
    }
    await refreshServiceStatus();
  });

  function setMessage(text: string, tone: "success" | "error" = "success") {
    message = text;
    messageTone = tone;
  }

  function applyServiceStatus(data: any) {
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
    serviceAction = "status";
    try {
      const data = await api.serviceStatus();
      applyServiceStatus(data);
      if (data?.status === "error" && showErrorMessage) {
        setMessage(data?.message || "Failed to load service status", "error");
      }
    } catch (e) {
      applyServiceStatus({ status: "error", message: (e as Error).message || "Failed to load service status" });
      if (showErrorMessage) setMessage(`Error: ${(e as Error).message}`, "error");
    } finally {
      serviceLoading = false;
      serviceAction = null;
    }
  }

  async function toggleService() {
    const enabling = !service.registered;
    serviceLoading = true;
    serviceAction = enabling ? "install" : "uninstall";
    try {
      const data = enabling ? await api.serviceInstall() : await api.serviceUninstall();
      applyServiceStatus(data);
      if (data?.status === "error") {
        setMessage(data?.message || "Failed to update service", "error");
        return;
      }
      await refreshServiceStatus(false);
      setMessage(data?.message || (enabling ? "Service enabled" : "Service disabled"));
    } catch (e) {
      setMessage(`Error: ${(e as Error).message}`, "error");
    } finally {
      serviceLoading = false;
      serviceAction = null;
    }
  }

  async function save() {
    saving = true;
    try {
      const { access, ...payload } = settings;
      await api.putSettings(payload);
      setMessage("Settings saved");
    } catch (e) {
      setMessage(`Error: ${(e as Error).message}`, "error");
    } finally {
      saving = false;
    }
  }
</script>

<svelte:head>
  <title>Settings - NullHubX</title>
</svelte:head>

<div class="page">
  <header class="page-header">
    <div class="header-left">
      <div class="breadcrumb">
        <span class="breadcrumb-item">System</span>
        <span class="breadcrumb-sep">/</span>
        <span class="breadcrumb-item active">Settings</span>
      </div>
      <h1>SYSTEM <span class="highlight">SETTINGS</span></h1>
      <p class="subtitle">Configure NullHubX server and service preferences</p>
    </div>
  </header>

  <hr class="divider" />

  {#if message}
    <div class="message" class:error={messageTone === "error"}>
      {#if messageTone === "success"}
        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><polyline points="22 4 12 14.01 9 11.01"/></svg>
      {:else}
        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>
      {/if}
      <span>{message}</span>
    </div>
  {/if}

  <div class="settings-grid">
    <section class="settings-section">
      <h2>Server</h2>
      <div class="field">
        <label for="settings-port">Port</label>
        <input id="settings-port" type="number" bind:value={settings.port} />
        <p class="hint">The port NullHubX listens on</p>
      </div>
      <div class="field">
        <label for="settings-host">Host</label>
        <input id="settings-host" type="text" bind:value={settings.host} />
        <p class="hint">Bind address (use 0.0.0.0 for all interfaces)</p>
      </div>
    </section>

    <section class="settings-section">
      <h2>Security</h2>
      <div class="field">
        <label for="settings-auth-token">Auth Token</label>
        <input id="settings-auth-token" type="password" bind:value={settings.auth_token} placeholder="Leave empty to disable" />
        <p class="hint">Set a token to enable remote access authentication</p>
      </div>
    </section>

    <section class="settings-section">
      <h2>Updates</h2>
      <label class="toggle-field">
        <input type="checkbox" bind:checked={settings.auto_update_check} />
        <span class="toggle-slider"></span>
        <span class="toggle-label">Auto-check for updates</span>
      </label>
    </section>

    <section class="settings-section">
      <h2>Service</h2>
      <p class="section-hint">Register NullHubX as a system service for automatic startup</p>
      
      <div class="service-panel">
        <div class="service-row">
          <span class="service-label">Autostart</span>
          <span class="service-badge" class:active={service.registered}>
            {service.registered ? "Enabled" : "Disabled"}
          </span>
        </div>
        <div class="service-row">
          <span class="service-label">Runtime</span>
          <span class="service-badge" class:active={service.running}>
            {service.running ? "Running" : "Stopped"}
          </span>
        </div>
        {#if service.service_type}
          <div class="service-detail">
            <span class="service-label">Service Type</span>
            <code>{service.service_type}</code>
          </div>
        {/if}
        {#if service.unit_path}
          <div class="service-detail">
            <span class="service-label">Unit Path</span>
            <code>{service.unit_path}</code>
          </div>
        {/if}
        <div class="service-actions">
          <button class="btn-primary" onclick={toggleService} disabled={serviceLoading}>
            {serviceButtonLabel}
          </button>
          <button class="btn-secondary" onclick={() => refreshServiceStatus()} disabled={serviceLoading}>
            Refresh
          </button>
        </div>
      </div>
    </section>

    <div class="actions-bar">
      <button class="btn-save" onclick={save} disabled={saving}>
        {saving ? "Saving..." : "Save Settings"}
      </button>
    </div>
  </div>
</div>

<style>
  .page {
    padding: var(--spacing-4xl) var(--spacing-5xl);
    max-width: 800px;
    margin: 0 auto;
  }

  .page-header {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
    margin-bottom: var(--spacing-xl);
  }

  .header-left {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-sm);
  }

  .breadcrumb {
    display: flex;
    align-items: center;
    gap: var(--spacing-xs);
    font-family: var(--font-mono);
    font-size: var(--text-xs);
    color: var(--slate-400);
    letter-spacing: 1px;
  }

  .breadcrumb-sep { color: var(--slate-300); }
  .breadcrumb-item.active { color: var(--slate-600); }

  h1 {
    font-family: var(--font-mono);
    font-size: var(--text-3xl);
    font-weight: 700;
    color: var(--slate-900);
    letter-spacing: 3px;
  }

  .highlight { color: var(--indigo-600); }

  .subtitle {
    font-family: var(--font-sans);
    font-size: var(--text-base);
    color: var(--slate-500);
    margin-top: var(--spacing-xs);
  }

  .divider {
    border: none;
    height: 1px;
    background: var(--slate-200);
    margin: var(--spacing-xl) 0;
  }

  .message {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm);
    padding: var(--spacing-md) var(--spacing-lg);
    background: rgba(16, 185, 129, 0.08);
    border: 1px solid rgba(16, 185, 129, 0.2);
    border-radius: var(--radius-md);
    font-family: var(--font-sans);
    font-size: var(--text-sm);
    font-weight: 500;
    color: var(--emerald-600);
    margin-bottom: var(--spacing-xl);
  }

  .message.error {
    background: rgba(239, 68, 68, 0.08);
    border-color: rgba(239, 68, 68, 0.2);
    color: #ef4444;
  }

  .settings-grid {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-xl);
  }

  .settings-section {
    background: white;
    border: 1px solid var(--slate-200);
    border-radius: var(--radius-lg);
    padding: var(--spacing-lg);
    box-shadow: var(--shadow-sm);
  }

  .settings-section h2 {
    font-family: var(--font-mono);
    font-size: var(--text-sm);
    font-weight: 700;
    color: var(--slate-700);
    text-transform: uppercase;
    letter-spacing: 1px;
    margin-bottom: var(--spacing-lg);
    padding-bottom: var(--spacing-sm);
    border-bottom: 1px solid var(--slate-100);
  }

  .section-hint {
    font-family: var(--font-sans);
    font-size: var(--text-sm);
    color: var(--slate-500);
    margin-bottom: var(--spacing-md);
  }

  .field {
    margin-bottom: var(--spacing-md);
  }

  .field label {
    display: block;
    font-family: var(--font-mono);
    font-size: var(--text-xs);
    font-weight: 600;
    color: var(--slate-600);
    text-transform: uppercase;
    letter-spacing: 0.5px;
    margin-bottom: var(--spacing-sm);
  }

  .field input[type="text"],
  .field input[type="number"],
  .field input[type="password"] {
    width: 100%;
    padding: var(--spacing-sm) var(--spacing-md);
    background: var(--slate-50);
    border: 1px solid var(--slate-200);
    border-radius: var(--radius-md);
    color: var(--slate-900);
    font-family: var(--font-mono);
    font-size: var(--text-sm);
    outline: none;
    transition: all var(--transition-fast);
  }

  .field input:focus {
    border-color: var(--indigo-500);
    box-shadow: 0 0 0 3px rgba(99, 102, 241, 0.1);
  }

  .field input::placeholder { color: var(--slate-400); }

  .hint {
    font-family: var(--font-sans);
    font-size: var(--text-xs);
    color: var(--slate-400);
    margin-top: var(--spacing-xs);
  }

  .toggle-field {
    display: flex;
    align-items: center;
    gap: var(--spacing-md);
    cursor: pointer;
  }

  .toggle-field input { display: none; }

  .toggle-slider {
    position: relative;
    width: 44px;
    height: 24px;
    background: var(--slate-200);
    border-radius: 12px;
    transition: all var(--transition-fast);
  }

  .toggle-slider::before {
    content: "";
    position: absolute;
    width: 18px;
    height: 18px;
    left: 3px;
    top: 3px;
    background: white;
    border-radius: 50%;
    transition: all var(--transition-fast);
    box-shadow: var(--shadow-sm);
  }

  .toggle-field input:checked + .toggle-slider {
    background: var(--indigo-600);
  }

  .toggle-field input:checked + .toggle-slider::before {
    transform: translateX(20px);
  }

  .toggle-label {
    font-family: var(--font-sans);
    font-size: var(--text-sm);
    color: var(--slate-700);
  }

  .service-panel {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-md);
    padding: var(--spacing-md);
    background: var(--slate-50);
    border-radius: var(--radius-md);
  }

  .service-row {
    display: flex;
    justify-content: space-between;
    align-items: center;
  }

  .service-label {
    font-family: var(--font-mono);
    font-size: var(--text-xs);
    color: var(--slate-500);
    text-transform: uppercase;
    letter-spacing: 0.5px;
  }

  .service-badge {
    font-family: var(--font-mono);
    font-size: var(--text-xs);
    font-weight: 600;
    padding: var(--spacing-xs) var(--spacing-sm);
    background: var(--slate-200);
    color: var(--slate-500);
    border-radius: var(--radius-sm);
    text-transform: uppercase;
    letter-spacing: 0.5px;
  }

  .service-badge.active {
    background: rgba(16, 185, 129, 0.15);
    color: var(--emerald-600);
  }

  .service-detail {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-xs);
  }

  .service-detail code {
    font-family: var(--font-mono);
    font-size: var(--text-xs);
    color: var(--slate-700);
    word-break: break-all;
  }

  .service-actions {
    display: flex;
    gap: var(--spacing-sm);
    margin-top: var(--spacing-sm);
  }

  .btn-primary {
    padding: var(--spacing-sm) var(--spacing-lg);
    background: var(--indigo-600);
    color: white;
    border: none;
    border-radius: var(--radius-md);
    font-family: var(--font-mono);
    font-size: var(--text-sm);
    font-weight: 600;
    cursor: pointer;
    transition: all var(--transition-fast);
  }

  .btn-primary:hover:not(:disabled) {
    background: var(--indigo-700);
  }

  .btn-primary:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .btn-secondary {
    padding: var(--spacing-sm) var(--spacing-lg);
    background: white;
    color: var(--slate-600);
    border: 1px solid var(--slate-200);
    border-radius: var(--radius-md);
    font-family: var(--font-mono);
    font-size: var(--text-sm);
    font-weight: 500;
    cursor: pointer;
    transition: all var(--transition-fast);
  }

  .btn-secondary:hover:not(:disabled) {
    background: var(--slate-50);
    border-color: var(--slate-300);
  }

  .btn-secondary:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .actions-bar {
    display: flex;
    justify-content: flex-end;
    padding-top: var(--spacing-lg);
    border-top: 1px solid var(--slate-200);
    margin-top: var(--spacing-lg);
  }

  .btn-save {
    padding: var(--spacing-md) var(--spacing-xl);
    background: var(--indigo-600);
    color: white;
    border: none;
    border-radius: var(--radius-md);
    font-family: var(--font-mono);
    font-size: var(--text-sm);
    font-weight: 600;
    letter-spacing: 1px;
    cursor: pointer;
    transition: all var(--transition-fast);
  }

  .btn-save:hover:not(:disabled) {
    background: var(--indigo-700);
    box-shadow: var(--shadow-indigo);
    transform: translateY(-1px);
  }

  .btn-save:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
</style>