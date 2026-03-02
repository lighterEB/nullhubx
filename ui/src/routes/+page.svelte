<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import InstanceCard from '$lib/components/InstanceCard.svelte';
  import { api } from '$lib/api/client';

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

<div class="dashboard">
  <div class="header">
    <h1>Dashboard</h1>
    <a href="/install" class="install-btn">+ Install Component</a>
  </div>

  {#if error}
    <div class="error-banner">{error}</div>
  {/if}

  {#if status}
    <div class="instance-grid">
      {#each Object.entries(status.instances || {}) as [component, instances]}
        {#each Object.entries(instances as Record<string, any>) as [name, info]}
          <InstanceCard
            {component}
            {name}
            version={info.version}
            status={info.status || 'stopped'}
            autoStart={info.auto_start}
            port={info.port || 0}
            onAction={refresh}
          />
        {/each}
      {/each}
    </div>

    {#if Object.keys(status.instances || {}).length === 0}
      <div class="empty-state">
        <p>No instances installed yet.</p>
        <a href="/install">Install your first component</a>
      </div>
    {/if}
  {/if}
</div>

<style>
  .dashboard {
    padding: 2rem;
    max-width: 1200px;
    margin: 0 auto;
  }
  .header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 2rem;
  }
  h1 {
    font-size: 1.75rem;
    font-weight: 600;
  }
  .install-btn {
    padding: 0.5rem 1rem;
    background: var(--accent);
    color: white;
    border-radius: var(--radius);
    font-size: 0.875rem;
    font-weight: 500;
    transition: background 0.15s;
  }
  .install-btn:hover {
    background: var(--accent-hover);
    color: white;
  }
  .error-banner {
    padding: 0.75rem 1rem;
    background: color-mix(in srgb, var(--error) 15%, transparent);
    color: var(--error);
    border: 1px solid color-mix(in srgb, var(--error) 30%, transparent);
    border-radius: var(--radius);
    margin-bottom: 1.5rem;
    font-size: 0.875rem;
  }
  .instance-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
    gap: 1rem;
  }
  .empty-state {
    text-align: center;
    padding: 4rem 2rem;
    color: var(--text-secondary);
  }
  .empty-state p {
    margin-bottom: 1rem;
    font-size: 1.125rem;
  }
  .empty-state a {
    display: inline-block;
    padding: 0.5rem 1rem;
    background: var(--accent);
    color: white;
    border-radius: var(--radius);
    font-size: 0.875rem;
  }
  .empty-state a:hover {
    background: var(--accent-hover);
    color: white;
  }
</style>
