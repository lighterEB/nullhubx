<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import InstanceCard from "$lib/components/InstanceCard.svelte";
  import { api } from "$lib/api/client";

  let status = $state<any>(null);
  let error = $state<string | null>(null);
  let interval: ReturnType<typeof setInterval>;

  async function refresh() {
    try {
      status = await api.getStatus();
      error = null;
    } catch (e) {
      error = (e as Error).message;
    }
  }

  onMount(() => {
    refresh();
    interval = setInterval(refresh, 5000);
  });

  onDestroy(() => clearInterval(interval));
</script>

<div class="page">
  <div class="page-header">
    <div class="header-content">
      <h1>System Status</h1>
      <p class="subtitle">Monitor and manage your instances</p>
    </div>
    <a href="/install" class="btn btn-primary">Install Component</a>
  </div>

  {#if error}
    <div class="error-banner">
      <strong>Error:</strong> {error}
    </div>
  {/if}

  {#if status}
    {#if Object.keys(status.instances || {}).length > 0}
      <div class="instance-grid">
        {#each Object.entries(status.instances || {}) as [component, instances]}
          {#each Object.entries(instances as Record<string, any>) as [name, info]}
            <InstanceCard
              {component}
              {name}
              version={info.version}
              status={info.status || "stopped"}
              autoStart={info.auto_start}
              port={info.port || 0}
              onAction={refresh}
            />
          {/each}
        {/each}
      </div>
    {:else}
      <div class="empty-state">
        <div class="empty-icon">
          <svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><rect width="20" height="8" x="2" y="2" rx="2" ry="2"></rect><rect width="20" height="8" x="2" y="14" rx="2" ry="2"></rect><line x1="6" x2="6.01" y1="6" y2="6"></line><line x1="6" x2="6.01" y1="18" y2="18"></line></svg>
        </div>
        <h2>No instances yet</h2>
        <p>Install your first component to get started</p>
        <a href="/install" class="btn btn-primary">Browse Components</a>
      </div>
    {/if}
  {/if}
</div>

<style>
  .page {
    max-width: 1200px;
  }

  .page-header {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    margin-bottom: var(--spacing-3xl);
  }

  .header-content h1 {
    font-size: var(--text-2xl);
    font-weight: 700;
    color: var(--text-primary);
    margin: 0;
  }

  .subtitle {
    font-size: var(--text-sm);
    color: var(--text-secondary);
    margin: var(--spacing-sm) 0 0 0;
  }

  .btn {
    display: inline-flex;
    align-items: center;
    gap: var(--spacing-sm);
    font-size: var(--text-sm);
    font-weight: 600;
    padding: var(--spacing-sm) var(--spacing-lg);
    border-radius: var(--radius-md);
    cursor: pointer;
    transition: all var(--transition-base);
    text-decoration: none;
  }

  .btn-primary {
    background: var(--color-primary);
    border: 1px solid var(--color-primary);
    color: white;
  }

  .btn-primary:hover {
    background: var(--color-primary-hover);
    border-color: var(--color-primary-hover);
    color: white;
    text-decoration: none;
  }

  .error-banner {
    padding: var(--spacing-md) var(--spacing-lg);
    background: rgba(239, 68, 68, 0.1);
    border: 1px solid var(--status-error);
    border-radius: var(--radius-md);
    color: var(--status-error);
    font-size: var(--text-sm);
    margin-bottom: var(--spacing-xl);
  }

  .instance-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(340px, 1fr));
    gap: var(--spacing-xl);
  }

  .empty-state {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    text-align: center;
    padding: var(--spacing-3xl) var(--spacing-xl);
    background: var(--bg-surface);
    border: 1px solid var(--border);
    border-radius: var(--radius-lg);
  }

  .empty-icon {
    color: var(--text-muted);
    margin-bottom: var(--spacing-lg);
  }

  .empty-state h2 {
    font-size: var(--text-lg);
    font-weight: 600;
    color: var(--text-primary);
    margin: 0;
  }

  .empty-state p {
    font-size: var(--text-sm);
    color: var(--text-secondary);
    margin: var(--spacing-sm) 0 var(--spacing-xl) 0;
  }
</style>