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
      if (serviceAction === "install") return "启用中...";
      if (serviceAction === "uninstall") return "停用中...";
      return "检查中...";
    }
    return service.registered ? "禁用开机自启" : "启用开机自启";
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
        setMessage(data?.message || "加载服务状态失败", "error");
      }
    } catch (e) {
      applyServiceStatus({ status: "error", message: (e as Error).message || "加载服务状态失败" });
      if (showErrorMessage) setMessage(`错误：${(e as Error).message}`, "error");
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
        setMessage(data?.message || "更新服务状态失败", "error");
        return;
      }
      await refreshServiceStatus(false);
      setMessage(data?.message || (enabling ? "服务已启用" : "服务已停用"));
    } catch (e) {
      setMessage(`错误：${(e as Error).message}`, "error");
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
      setMessage("设置已保存");
    } catch (e) {
      setMessage(`错误：${(e as Error).message}`, "error");
    } finally {
      saving = false;
    }
  }
</script>

<svelte:head>
  <title>系统设置 - NullHubX</title>
</svelte:head>

<div class="page">
  <header class="page-header">
    <div class="header-left">
      <div class="breadcrumb">
        <span class="breadcrumb-item">系统</span>
        <span class="breadcrumb-sep">/</span>
        <span class="breadcrumb-item active">设置</span>
      </div>
      <h1>系统 <span class="highlight">设置</span></h1>
      <p class="subtitle">配置 NullHubX 服务器与服务偏好</p>
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
      <h2>服务器</h2>
      <div class="field">
        <label for="settings-port">端口</label>
        <input id="settings-port" type="number" bind:value={settings.port} />
        <p class="hint">NullHubX 监听端口</p>
      </div>
      <div class="field">
        <label for="settings-host">主机地址</label>
        <input id="settings-host" type="text" bind:value={settings.host} />
        <p class="hint">绑定地址（0.0.0.0 表示监听所有网卡）</p>
      </div>
    </section>

    <section class="settings-section">
      <h2>安全</h2>
      <div class="field">
        <label for="settings-auth-token">认证令牌</label>
        <input id="settings-auth-token" type="password" bind:value={settings.auth_token} placeholder="留空表示关闭认证" />
        <p class="hint">设置后可启用远程访问认证</p>
      </div>
    </section>

    <section class="settings-section">
      <h2>更新</h2>
      <label class="toggle-field">
        <input type="checkbox" bind:checked={settings.auto_update_check} />
        <span class="toggle-slider"></span>
        <span class="toggle-label">自动检查更新</span>
      </label>
    </section>

    <section class="settings-section">
      <h2>服务</h2>
      <p class="section-hint">将 NullHubX 注册为系统服务以支持开机自启</p>

      <div class="service-panel">
        <div class="service-row">
          <span class="service-label">开机自启</span>
          <span class="service-badge" class:active={service.registered}>
            {service.registered ? "已启用" : "已禁用"}
          </span>
        </div>
        <div class="service-row">
          <span class="service-label">运行状态</span>
          <span class="service-badge" class:active={service.running}>
            {service.running ? "运行中" : "已停止"}
          </span>
        </div>
        {#if service.service_type}
          <div class="service-detail">
            <span class="service-label">服务类型</span>
            <code>{service.service_type}</code>
          </div>
        {/if}
        {#if service.unit_path}
          <div class="service-detail">
            <span class="service-label">单元路径</span>
            <code>{service.unit_path}</code>
          </div>
        {/if}
        <div class="service-actions">
          <button class="btn-primary" onclick={toggleService} disabled={serviceLoading}>
            {serviceButtonLabel}
          </button>
          <button class="btn-secondary" onclick={() => refreshServiceStatus()} disabled={serviceLoading}>
            刷新
          </button>
        </div>
      </div>
    </section>

    <div class="actions-bar">
      <button class="btn-save" onclick={save} disabled={saving}>
        {saving ? "保存中..." : "保存设置"}
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
    color: var(--red-600);
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

  @media (max-width: 900px) {
    .page {
      padding: var(--spacing-2xl);
    }
  }

  @media (max-width: 680px) {
    .page {
      padding: var(--spacing-lg);
    }

    h1 {
      font-size: var(--text-2xl);
      letter-spacing: 1.5px;
    }

    .service-actions {
      flex-direction: column;
    }

    .service-actions .btn-primary,
    .service-actions .btn-secondary {
      width: 100%;
    }

    .actions-bar {
      padding-top: var(--spacing-md);
      margin-top: var(--spacing-md);
    }

    .btn-save {
      width: 100%;
    }
  }
</style>
