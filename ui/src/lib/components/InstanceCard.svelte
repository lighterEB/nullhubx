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

  // Sync localStatus when prop changes (from poll)
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
    <span class="card-name">{name}</span>
    <StatusBadge status={localStatus} />
  </div>
  <div class="card-meta">
    <span class="component-tag">{component}</span>
    <span class="version">{displayVersion}</span>
  </div>
  {#if localStatus === "running" && port > 0}
    <div class="gateway-addr">
      <span class="gateway-label">Gateway:</span>
      <code>127.0.0.1:{port}</code>
    </div>
  {/if}
  <div class="card-actions">
    {#if localStatus === "running" || localStatus === "stopping"}
      <button onclick={stop} disabled={loading}>
        {loading ? "Stopping..." : "Stop"}
      </button>
    {:else}
      <button onclick={start} disabled={loading}>
        {loading ? "Starting..." : "Start"}
      </button>
    {/if}
  </div>
</a>

<style>
  .card {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-lg);
    padding: var(--spacing-xl);
    background: var(--glass-bg);
    border: 1px solid var(--glass-border);
    border-radius: var(--radius-lg);
    color: var(--text-primary);
    text-decoration: none;
    transition: all var(--transition-base) ease;
    backdrop-filter: blur(12px);
    -webkit-backdrop-filter: blur(12px);
    position: relative;
    overflow: hidden;
  }

  .card:hover {
    border-color: var(--glass-border-hover);
    box-shadow: var(--glass-shadow);
    transform: translateY(-2px);
  }

  /* 扫光线效果 */
  .card::before {
    content: '';
    position: absolute;
    top: 0;
    left: -100%;
    width: 100%;
    height: 2px;
    background: linear-gradient(90deg,
      transparent,
      var(--glass-glow),
      transparent
    );
    transition: left var(--transition-slower) ease;
    z-index: 1;
  }

  .card:hover::before {
    left: 100%;
  }

  .card-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    border-bottom: 1px solid var(--glass-border);
    padding-bottom: var(--spacing-md);
  }

  .card-name {
    font-weight: 600;
    font-size: var(--font-size-xl);
    text-transform: uppercase;
    letter-spacing: 1px;
    color: var(--text-primary);
  }

  .card-meta {
    display: flex;
    align-items: center;
    gap: var(--spacing-md);
    font-size: var(--font-size-sm);
    color: var(--text-secondary);
  }

  .component-tag {
    padding: var(--spacing-xs) var(--spacing-sm);
    background: rgba(99, 102, 241, 0.15);
    border: 1px solid rgba(99, 102, 241, 0.3);
    border-radius: var(--radius-sm);
    font-family: var(--font-mono);
    font-size: var(--font-size-sm);
    font-weight: 500;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    color: var(--color-primary);
  }

  .version {
    font-family: var(--font-mono);
    font-size: var(--font-size-sm);
    color: var(--text-muted);
  }

  .card-actions {
    display: flex;
    gap: var(--spacing-sm);
    margin-top: var(--spacing-sm);
  }

  .card-actions button {
    padding: var(--spacing-sm) var(--spacing-lg);
    border: 1px solid var(--color-accent);
    border-radius: var(--radius-md);
    background: rgba(6, 182, 212, 0.1);
    color: var(--color-accent);
    font-size: var(--font-size-sm);
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    cursor: pointer;
    transition: all var(--transition-base) ease;
    backdrop-filter: blur(4px);
    -webkit-backdrop-filter: blur(4px);
  }

  .card-actions button:hover:not(:disabled) {
    background: rgba(6, 182, 212, 0.2);
    border-color: #0891b2;
    box-shadow: 0 0 15px rgba(6, 182, 212, 0.3);
  }

  .card-actions button:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .gateway-addr {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm);
    font-size: var(--font-size-sm);
    padding: var(--spacing-sm);
    background: rgba(6, 182, 212, 0.1);
    border: 1px solid rgba(6, 182, 212, 0.2);
    border-radius: var(--radius-md);
  }

  .gateway-label {
    color: var(--text-muted);
    font-size: var(--font-size-sm);
    text-transform: uppercase;
    letter-spacing: 0.5px;
  }

  .gateway-addr code {
    font-family: var(--font-mono);
    font-size: var(--font-size-sm);
    color: var(--color-accent);
    font-weight: 600;
  }
</style>
