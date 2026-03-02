<script lang="ts">
  import { page } from '$app/stores';
  import { onMount } from 'svelte';
  import { api } from '$lib/api/client';

  let instances = $state<Record<string, any>>({});
  let currentPath = $derived($page.url.pathname);

  async function loadInstances() {
    try {
      const status = await api.getStatus();
      instances = status.instances || {};
    } catch {}
  }

  onMount(() => {
    loadInstances();
    const interval = setInterval(loadInstances, 5000);
    return () => clearInterval(interval);
  });
</script>

<nav class="sidebar">
  <div class="logo">
    <h2>NullHub</h2>
  </div>

  <div class="nav-section">
    <a href="/" class:active={currentPath === '/'}>Dashboard</a>
    <a href="/install" class:active={currentPath === '/install'}>Install Component</a>
  </div>

  <div class="nav-section">
    <h3>Instances</h3>
    {#each Object.entries(instances) as [component, items]}
      <div class="component-group">
        <span class="component-name">{component}</span>
        {#each Object.entries(items as Record<string, any>) as [name, info]}
          <a
            href="/instances/{component}/{name}"
            class:active={currentPath === `/instances/${component}/${name}`}
          >
            <span class="status-dot" class:running={info.status === 'running'}></span>
            {name}
          </a>
        {/each}
      </div>
    {/each}
  </div>

  <div class="nav-bottom">
    <a href="/settings" class:active={currentPath === '/settings'}>Settings</a>
  </div>
</nav>

<style>
  .sidebar {
    width: 240px;
    min-width: 240px;
    height: 100vh;
    background: var(--bg-secondary);
    border-right: 1px solid var(--border);
    display: flex;
    flex-direction: column;
    overflow-y: auto;
  }

  .logo {
    padding: 1.25rem 1rem;
    border-bottom: 1px solid var(--border);
  }

  .logo h2 {
    font-size: 1.25rem;
    font-weight: 700;
    color: var(--text-primary);
    letter-spacing: 0.5px;
  }

  .nav-section {
    padding: 0.75rem 0;
    border-bottom: 1px solid var(--border);
  }

  .nav-section h3 {
    font-size: 0.65rem;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 1px;
    color: var(--text-muted);
    padding: 0.25rem 1rem 0.5rem;
  }

  .nav-section a {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0.5rem 1rem;
    color: var(--text-secondary);
    font-size: 0.875rem;
    transition: background 0.15s ease, color 0.15s ease;
    border-radius: 0;
  }

  .nav-section a:hover {
    background: var(--bg-hover);
    color: var(--text-primary);
  }

  .nav-section a.active {
    background: var(--bg-tertiary);
    color: var(--accent);
    border-left: 2px solid var(--accent);
  }

  .component-group {
    margin-bottom: 0.25rem;
  }

  .component-name {
    display: block;
    font-size: 0.75rem;
    font-weight: 600;
    color: var(--text-muted);
    padding: 0.375rem 1rem 0.125rem;
    text-transform: capitalize;
  }

  .component-group a {
    padding-left: 1.5rem;
  }

  .status-dot {
    display: inline-block;
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: var(--text-muted);
    flex-shrink: 0;
  }

  .status-dot.running {
    background: var(--success);
    box-shadow: 0 0 6px var(--success);
  }

  .nav-bottom {
    margin-top: auto;
    padding: 0.75rem 0;
    border-top: 1px solid var(--border);
  }

  .nav-bottom a {
    display: block;
    padding: 0.5rem 1rem;
    color: var(--text-secondary);
    font-size: 0.875rem;
    transition: background 0.15s ease, color 0.15s ease;
  }

  .nav-bottom a:hover {
    background: var(--bg-hover);
    color: var(--text-primary);
  }

  .nav-bottom a.active {
    background: var(--bg-tertiary);
    color: var(--accent);
    border-left: 2px solid var(--accent);
  }
</style>
