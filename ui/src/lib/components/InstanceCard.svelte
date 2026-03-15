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
</script>

<a href="/instances/{component}/{name}" class="card">
  <div class="card-header">
    <div class="card-title">
      <span class="card-name">{name}</span>
      <span class="component-badge">{component}</span>
    </div>
    <StatusBadge status={localStatus} />
  </div>
  
  <p class="card-description">
    {component === "nullclaw" ? "AI Agent Runtime" : component === "nullboiler" ? "Workflow Orchestrator" : "Task Tracker"}
  </p>
  
  {#if localStatus === "running" && port > 0}
    <div class="gateway-info">
      <span class="gateway-label">Gateway</span>
      <code class="gateway-addr">127.0.0.1:{port}</code>
    </div>
  {/if}
  
  <div class="card-footer">
    <span class="version">{displayVersion}</span>
    <div class="card-actions">
      {#if localStatus === "running" || localStatus === "stopping"}
        <button class="btn-stop" onclick={stop} disabled={loading}>
          {loading ? "Stopping..." : "Stop"}
        </button>
      {:else}
        <button class="btn-start" onclick={start} disabled={loading}>
          {loading ? "Starting..." : "Start"}
        </button>
      {/if}
    </div>
  </div>
</a>

<style>
  .card {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-md);
    padding: var(--spacing-xl);
    background: var(--bg-surface);
    border: 1px solid var(--border);
    border-radius: var(--radius-lg);
    color: var(--text-primary);
    text-decoration: none;
    transition: all var(--transition-base);
  }

  .card:hover {
    border-color: var(--border-hover);
    box-shadow: var(--shadow-md);
  }

  .card-header {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: var(--spacing-md);
  }

  .card-title {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-xs);
  }

  .card-name {
    font-size: var(--text-lg);
    font-weight: 600;
    color: var(--text-primary);
  }

  .component-badge {
    font-size: var(--text-xs);
    font-weight: 500;
    padding: 2px var(--spacing-sm);
    background: var(--badge-primary);
    color: var(--badge-primary-text);
    border-radius: var(--radius-sm);
    text-transform: uppercase;
    letter-spacing: 0.5px;
    width: fit-content;
  }

  .card-description {
    font-size: var(--text-sm);
    color: var(--text-secondary);
    margin: 0;
  }

  .gateway-info {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm);
    padding: var(--spacing-sm) var(--spacing-md);
    background: var(--bg-elevated);
    border-radius: var(--radius-md);
  }

  .gateway-label {
    font-size: var(--text-xs);
    color: var(--text-muted);
    text-transform: uppercase;
    letter-spacing: 0.5px;
  }

  .gateway-addr {
    font-family: var(--font-mono);
    font-size: var(--text-sm);
    color: var(--color-primary);
    font-weight: 500;
  }

  .card-footer {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding-top: var(--spacing-md);
    border-top: 1px solid var(--border);
    margin-top: auto;
  }

  .version {
    font-size: var(--text-xs);
    color: var(--text-muted);
    font-family: var(--font-mono);
  }

  .card-actions {
    display: flex;
    gap: var(--spacing-sm);
  }

  .btn-start,
  .btn-stop {
    font-size: var(--text-xs);
    font-weight: 600;
    padding: var(--spacing-xs) var(--spacing-md);
    border-radius: var(--radius-md);
    cursor: pointer;
    transition: all var(--transition-base);
    text-transform: uppercase;
    letter-spacing: 0.5px;
  }

  .btn-start {
    background: var(--color-primary);
    border: 1px solid var(--color-primary);
    color: white;
  }

  .btn-start:hover:not(:disabled) {
    background: var(--color-primary-hover);
    border-color: var(--color-primary-hover);
  }

  .btn-stop {
    background: transparent;
    border: 1px solid var(--border);
    color: var(--text-secondary);
  }

  .btn-stop:hover:not(:disabled) {
    background: var(--bg-hover);
    border-color: var(--status-error);
    color: var(--status-error);
  }

  .btn-start:disabled,
  .btn-stop:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
</style>