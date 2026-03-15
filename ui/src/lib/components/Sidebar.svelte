<script lang="ts">
  import { page } from "$app/stores";
  import { onMount } from "svelte";
  import { api } from "$lib/api/client";
  import { orchestrationUiRoutes } from "$lib/orchestration/routes";

  let instances = $state<Record<string, any>>({});
  let installedComponents = $state<Record<string, any>>({});
  let currentPath = $derived($page.url.pathname);
  let showOrchestration = $derived(Boolean(installedComponents["nullboiler"]?.installed));

  async function loadSidebarState() {
    const [statusResult, componentsResult] = await Promise.allSettled([
      api.getStatus(),
      api.getComponents(),
    ]);

    if (statusResult.status === "fulfilled") {
      instances = statusResult.value.instances || {};
    }

    if (componentsResult.status === "fulfilled") {
      installedComponents = Object.fromEntries(
        (componentsResult.value.components || []).map((component: any) => [component.name, component]),
      );
    }
  }

  onMount(() => {
    void loadSidebarState();
    const interval = setInterval(loadSidebarState, 5000);
    return () => clearInterval(interval);
  });
</script>

<nav class="sidebar">
  <a href="/" class="logo" aria-label="Go to NullHubX home">
    <h2>NullHubX</h2>
  </a>

  <div class="nav-section">
    <a href="/" class:active={currentPath === "/"}>System Status</a>
    <a href="/dashboard" class:active={currentPath === "/dashboard"}>Dashboard</a>
    <a href="/install" class:active={currentPath === "/install"}
      >Install Component</a
    >
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
            <span class="status-dot" class:running={info.status === "running"}
            ></span>
            {name}
          </a>
        {/each}
      </div>
    {/each}
  </div>

  {#if showOrchestration}
    <div class="nav-section">
      <h3>Orchestration</h3>
      <a href={orchestrationUiRoutes.dashboard()} class:active={currentPath === orchestrationUiRoutes.dashboard()}>Dashboard</a>
      <a href={orchestrationUiRoutes.workflows()} class:active={currentPath.startsWith(orchestrationUiRoutes.workflows())}>Workflows</a>
      <a href={orchestrationUiRoutes.runs()} class:active={currentPath.startsWith(orchestrationUiRoutes.runs())}>Runs</a>
      <a href={orchestrationUiRoutes.store()} class:active={currentPath.startsWith(orchestrationUiRoutes.store())}>Store</a>
    </div>
  {/if}

  <div class="nav-section">
    <a href="/providers" class:active={currentPath === "/providers"}>Providers</a>
  </div>

  <div class="nav-section">
    <a href="/channels" class:active={currentPath === "/channels"}>Channels</a>
  </div>

  <div class="nav-bottom">
    <a href="/settings" class:active={currentPath === "/settings"}>Settings</a>
  </div>
</nav>

<style>
  .sidebar {
    width: 260px;
    min-width: 260px;
    height: 100vh;
    background: var(--bg-surface);
    border-right: 1px solid var(--border);
    display: flex;
    flex-direction: column;
    overflow-y: auto;
    z-index: 20;
  }

  .logo {
    display: block;
    padding: var(--spacing-xl) var(--spacing-lg);
    border-bottom: 1px solid var(--border);
    text-align: center;
    color: inherit;
    transition: all var(--transition-base);
  }

  .logo:hover,
  .logo:focus-visible {
    text-decoration: none;
    background: var(--bg-hover);
  }

  .logo h2 {
    font-size: var(--text-lg);
    font-weight: 700;
    color: var(--color-primary);
    letter-spacing: 2px;
    text-transform: uppercase;
  }

  .nav-section {
    padding: var(--spacing-lg) 0;
    border-bottom: 1px solid var(--border);
  }

  .nav-section h3 {
    font-size: var(--text-xs);
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 1px;
    color: var(--text-muted);
    padding: var(--spacing-sm) var(--spacing-lg);
  }

  .nav-section a {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm);
    padding: var(--spacing-sm) var(--spacing-lg);
    color: var(--text-secondary);
    font-size: var(--text-sm);
    font-weight: 500;
    transition: all var(--transition-base);
    border-left: 3px solid transparent;
  }

  .nav-section a:hover {
    text-decoration: none;
    background: var(--bg-hover);
    color: var(--text-primary);
    border-left-color: var(--color-primary);
  }

  .nav-section a.active {
    background: var(--bg-active);
    color: var(--color-primary);
    border-left: 3px solid var(--color-primary);
    font-weight: 600;
  }

  .component-group {
    margin-bottom: var(--spacing-xs);
  }

  .component-name {
    display: block;
    font-size: var(--text-xs);
    font-weight: 600;
    color: var(--text-muted);
    padding: var(--spacing-xs) var(--spacing-lg) 0;
    text-transform: uppercase;
    letter-spacing: 0.5px;
  }

  .component-group a {
    padding-left: calc(var(--spacing-lg) + var(--spacing-md));
  }

  .status-dot {
    display: inline-block;
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: var(--status-stopped);
    flex-shrink: 0;
  }

  .status-dot.running {
    background: var(--status-running);
    box-shadow: 0 0 6px var(--status-running);
  }

  .nav-bottom {
    margin-top: auto;
    padding: var(--spacing-lg) 0;
    border-top: 1px solid var(--border);
  }

  .nav-bottom a {
    display: block;
    padding: var(--spacing-sm) var(--spacing-lg);
    color: var(--text-secondary);
    font-size: var(--text-sm);
    font-weight: 500;
    transition: all var(--transition-base);
    border-left: 3px solid transparent;
  }

  .nav-bottom a:hover {
    text-decoration: none;
    background: var(--bg-hover);
    color: var(--text-primary);
    border-left-color: var(--color-primary);
  }

  .nav-bottom a.active {
    background: var(--bg-active);
    color: var(--color-primary);
    border-left: 3px solid var(--color-primary);
    font-weight: 600;
  }
</style>
