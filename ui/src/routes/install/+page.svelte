<script lang="ts">
  import { afterNavigate } from "$app/navigation";
  import ComponentCard from "$lib/components/ComponentCard.svelte";
  import { api } from "$lib/api/client";

  let components = $state<any[]>([]);
  let filter = $state<"all" | "available" | "coming">("all");

  async function loadComponents() {
    try {
      const data = await api.getComponents();
      components = data.components || [];
    } catch (e) {
      console.error(e);
    }
  }

  afterNavigate(loadComponents);

  let filteredComponents = $derived(() => {
    if (filter === "available") {
      return components.filter(c => !c.alpha || c.installed);
    }
    if (filter === "coming") {
      return components.filter(c => c.alpha && !c.installed && !c.standalone);
    }
    return components;
  });

  let availableCount = $derived(components.filter(c => !c.alpha || c.installed).length);
</script>

<svelte:head>
  <title>Install Component - NullHubX</title>
</svelte:head>

<div class="page">
  <header class="page-header">
    <div class="header-left">
      <div class="breadcrumb">
        <span class="breadcrumb-item">Components</span>
        <span class="breadcrumb-sep">/</span>
        <span class="breadcrumb-item active">Install</span>
      </div>
      <h1>
        INSTALL <span class="highlight">COMPONENT</span>
      </h1>
      <p class="subtitle">Select a runtime module to deploy into the null stack</p>
    </div>
    <div class="header-right">
      <span class="badge badge-indigo">{components.length} modules</span>
      <span class="badge badge-emerald">{availableCount} available</span>
    </div>
  </header>

  <div class="filter-tabs">
    <button 
      class="filter-tab" 
      class:active={filter === "all"}
      onclick={() => filter = "all"}
    >
      All
    </button>
    <button 
      class="filter-tab" 
      class:active={filter === "available"}
      onclick={() => filter = "available"}
    >
      Available
    </button>
    <button 
      class="filter-tab" 
      class:active={filter === "coming"}
      onclick={() => filter = "coming"}
    >
      Coming Soon
    </button>
  </div>

  <hr class="divider" />

  <div class="catalog-grid">
    {#each filteredComponents() as comp, i}
      <div class="card-wrapper" style="animation-delay: {i * 80}ms">
        <ComponentCard
          name={comp.name}
          displayName={comp.display_name}
          description={comp.description}
          alpha={Boolean(comp.alpha)}
          installed={comp.installed}
          standalone={comp.standalone}
          instanceCount={comp.instance_count}
        />
      </div>
    {/each}
  </div>
</div>

<style>
  .page {
    padding: var(--spacing-4xl) var(--spacing-5xl);
    max-width: 1400px;
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

  .breadcrumb-sep {
    color: var(--slate-300);
  }

  .breadcrumb-item.active {
    color: var(--slate-600);
  }

  h1 {
    font-family: var(--font-mono);
    font-size: var(--text-3xl);
    font-weight: 700;
    color: var(--slate-900);
    letter-spacing: 3px;
  }

  .highlight {
    color: var(--indigo-600);
  }

  .subtitle {
    font-family: var(--font-sans);
    font-size: var(--text-base);
    color: var(--slate-500);
    margin-top: var(--spacing-xs);
  }

  .header-right {
    display: flex;
    gap: var(--spacing-sm);
  }

  .filter-tabs {
    display: flex;
    gap: var(--spacing-sm);
    margin-top: var(--spacing-xl);
  }

  .filter-tab {
    font-family: var(--font-sans);
    font-size: var(--text-sm);
    font-weight: 500;
    padding: var(--spacing-sm) var(--spacing-lg);
    border-radius: var(--radius-sm);
    background: white;
    color: var(--slate-500);
    border: 1px solid var(--slate-200);
    cursor: pointer;
    transition: all var(--transition-fast);
  }

  .filter-tab:hover {
    color: var(--slate-700);
  }

  .filter-tab.active {
    background: var(--indigo-600);
    color: white;
    border-color: var(--indigo-600);
    box-shadow: var(--shadow-sm);
  }

  .divider {
    border: none;
    height: 1px;
    background: var(--slate-200);
    margin: var(--spacing-xl) 0;
  }

  .catalog-grid {
    display: grid;
    grid-template-columns: 2fr 1fr 1fr;
    gap: var(--spacing-xl);
    grid-auto-rows: 1fr;
  }

  @media (max-width: 1200px) {
    .catalog-grid {
      grid-template-columns: 1fr 1fr;
    }
  }

  @media (max-width: 768px) {
    .catalog-grid {
      grid-template-columns: 1fr;
    }
    
    .page {
      padding: var(--spacing-xl);
    }
  }

  .card-wrapper {
    opacity: 0;
    animation: fadeUp 0.4s ease forwards;
  }

  @keyframes fadeUp {
    from {
      opacity: 0;
      transform: translateY(20px);
    }
    to {
      opacity: 1;
      transform: translateY(0);
    }
  }
</style>