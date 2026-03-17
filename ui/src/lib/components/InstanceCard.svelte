<script lang="ts">
  import StatusBadge from "./StatusBadge.svelte";
  import { api } from "$lib/api/client";

  let {
    component = "",
    name = "",
    version = "",
    status = "stopped",
    autoStart = false,
    port = 0,
    onAction = () => {},
  } = $props();

  let loading = $state(false);
  let localStatus = $state("stopped");
  let displayVersion = $derived(
    !version ? "-" : version.startsWith("v") || version.startsWith("dev-") ? version : `v${version}`,
  );

  $effect(() => {
    localStatus = status || "stopped";
  });

  async function start(e: Event) {
    e.preventDefault();
    e.stopPropagation();
    loading = true;
    localStatus = "starting";
    try {
      await api.startInstance(component, name);
      onAction();
    } catch {
      localStatus = "stopped";
    } finally {
      loading = false;
    }
  }

  async function stop(e: Event) {
    e.preventDefault();
    e.stopPropagation();
    loading = true;
    localStatus = "stopping";
    try {
      await api.stopInstance(component, name);
      onAction();
    } catch {
      localStatus = "running";
    } finally {
      loading = false;
    }
  }

  async function remove(e: Event) {
    e.preventDefault();
    e.stopPropagation();
    if (!confirm(`确认删除实例 ${component}/${name} 吗？此操作不可撤销。`)) return;
    loading = true;
    try {
      await api.deleteInstance(component, name);
      onAction();
    } finally {
      loading = false;
    }
  }

  const colorMap: Record<string, "indigo" | "violet" | "amber"> = {
    nullclaw: "indigo",
    nullboiler: "violet",
    nulltickets: "amber",
  };

  const iconMap: Record<string, string> = {
    nullclaw: "⬡",
    nullboiler: "⊗",
    nulltickets: "⊞",
  };
</script>

<a href="/instances/{component}/{name}" class="instance-card">
  <div class="accent-bar {colorMap[component] || 'indigo'}"></div>

  <div class="card-top">
    <div class="icon-box {colorMap[component] || 'indigo'}">
      {iconMap[component] || "◈"}
    </div>
    <StatusBadge status={localStatus} />
  </div>

  <h3 class="card-name">{name}</h3>

  <div class="card-meta">
    <span class="component-tag">{component}</span>
    <span class="version">{displayVersion}</span>
  </div>

  {#if localStatus === "running" && port > 0}
    <div class="gateway-info">
      <span class="gateway-label">网关:</span>
      <code class="gateway-addr">127.0.0.1:{port}</code>
    </div>
  {/if}

  <div class="card-actions">
    {#if localStatus === "running" || localStatus === "stopping"}
      <button class="btn-stop" onclick={stop} disabled={loading}>
        {loading ? "停止中..." : "停止"}
      </button>
    {:else}
      <button class="btn-start" onclick={start} disabled={loading}>
        {loading ? "启动中..." : "启动"}
      </button>
    {/if}
    <button class="btn-delete" onclick={remove} disabled={loading}>
      删除
    </button>
  </div>
</a>

<style>
  .instance-card {
    position: relative;
    display: flex;
    flex-direction: column;
    gap: var(--spacing-md);
    padding: var(--spacing-xl);
    padding-left: calc(var(--spacing-xl) + 3px);
    background: white;
    border: 1px solid var(--slate-200);
    border-radius: var(--radius-lg);
    box-shadow: var(--shadow-sm);
    text-decoration: none;
    color: inherit;
    transition: all var(--transition-base);
    overflow: hidden;
  }

  .instance-card:hover {
    transform: translateY(-3px);
    box-shadow: var(--shadow-md);
    border-color: var(--indigo-200);
  }

  .accent-bar {
    position: absolute;
    left: 0;
    top: 0;
    bottom: 0;
    width: 3px;
    background: linear-gradient(to bottom, var(--indigo-500), var(--indigo-600));
  }

  .accent-bar.violet {
    background: linear-gradient(to bottom, var(--violet-500), color-mix(in srgb, var(--violet-500) 75%, black));
  }

  .accent-bar.amber {
    background: linear-gradient(to bottom, var(--amber-500), var(--amber-600));
  }

  .card-top {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
  }

  .icon-box {
    width: 36px;
    height: 36px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 18px;
    border-radius: var(--radius-md);
    background: var(--indigo-50);
    border: 1px solid var(--indigo-200);
    color: var(--indigo-500);
  }

  .icon-box.violet {
    background: rgba(139, 92, 246, 0.1);
    border-color: rgba(139, 92, 246, 0.2);
    color: var(--violet-500);
  }

  .icon-box.amber {
    background: rgba(245, 158, 11, 0.1);
    border-color: rgba(245, 158, 11, 0.2);
    color: var(--amber-500);
  }

  .card-name {
    font-family: var(--font-mono);
    font-size: var(--text-lg);
    font-weight: 700;
    color: var(--slate-900);
    letter-spacing: 2px;
    margin: 0;
  }

  .card-meta {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm);
  }

  .component-tag {
    font-family: var(--font-mono);
    font-size: 10px;
    font-weight: 500;
    padding: var(--spacing-xs) var(--spacing-sm);
    border-radius: var(--radius-sm);
    background: var(--indigo-50);
    color: var(--indigo-500);
    border: 1px solid var(--indigo-200);
    text-transform: uppercase;
    letter-spacing: 0.5px;
  }

  .version {
    font-family: var(--font-mono);
    font-size: var(--text-xs);
    color: var(--slate-400);
  }

  .gateway-info {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm);
    padding: var(--spacing-sm) var(--spacing-md);
    background: rgba(6, 182, 212, 0.08);
    border: 1px solid rgba(6, 182, 212, 0.15);
    border-radius: var(--radius-md);
  }

  .gateway-label {
    font-family: var(--font-mono);
    font-size: var(--text-xs);
    color: var(--slate-500);
    letter-spacing: 0.5px;
  }

  .gateway-addr {
    font-family: var(--font-mono);
    font-size: var(--text-xs);
    font-weight: 600;
    color: var(--cyan-500);
    background: none;
  }

  .card-actions {
    display: flex;
    gap: var(--spacing-sm);
    margin-top: auto;
  }

  .btn-start, .btn-stop {
    flex: 1;
    padding: var(--spacing-sm) var(--spacing-md);
    font-family: var(--font-mono);
    font-size: var(--text-sm);
    font-weight: 600;
    letter-spacing: 1px;
    border-radius: var(--radius-md);
    cursor: pointer;
    transition: all var(--transition-fast);
  }

  .btn-start {
    background: var(--emerald-600);
    color: white;
    border: none;
  }

  .btn-start:hover:not(:disabled) {
    background: var(--emerald-700);
    box-shadow: 0 10px 20px rgba(16, 185, 129, 0.2);
    transform: translateY(-1px);
  }

  .btn-stop {
    background: var(--red-600);
    color: white;
    border: none;
  }

  .btn-stop:hover:not(:disabled) {
    background: var(--red-700);
  }

  .btn-start:disabled, .btn-stop:disabled {
    opacity: 0.5;
    cursor: not-allowed;
    transform: none;
  }

  .btn-delete {
    padding: var(--spacing-sm) var(--spacing-md);
    font-family: var(--font-mono);
    font-size: var(--text-sm);
    font-weight: 600;
    letter-spacing: 1px;
    border-radius: var(--radius-md);
    cursor: pointer;
    border: 1px solid var(--red-300);
    background: white;
    color: var(--red-600);
    transition: all var(--transition-fast);
  }

  .btn-delete:hover:not(:disabled) {
    background: var(--red-50);
    border-color: var(--red-500);
  }

  .btn-delete:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  @media (max-width: 640px) {
    .instance-card {
      padding: var(--spacing-lg);
      padding-left: calc(var(--spacing-lg) + 3px);
    }

    .card-name {
      letter-spacing: 1px;
      font-size: var(--text-base);
    }

    .card-actions {
      flex-direction: column;
    }
  }
</style>
