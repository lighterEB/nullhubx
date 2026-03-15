<script lang="ts">
  import { afterNavigate } from "$app/navigation";
  import ComponentCard from "$lib/components/ComponentCard.svelte";
  import { api } from "$lib/api/client";

  let components = $state<any[]>([]);

  async function loadComponents() {
    try {
      const data = await api.getComponents();
      components = data.components || [];
    } catch (e) {
      console.error(e);
    }
  }

  afterNavigate(loadComponents);
</script>

<div class="page">
  <div class="page-header">
    <div class="header-content">
      <h1>Install Component</h1>
      <p class="subtitle">Choose a component to install or import</p>
    </div>
  </div>

  <div class="catalog-grid">
    {#each components as comp}
      <ComponentCard
        name={comp.name}
        displayName={comp.display_name}
        description={comp.description}
        alpha={Boolean(comp.alpha)}
        installed={comp.installed}
        standalone={comp.standalone}
        instanceCount={comp.instance_count}
      />
    {/each}
  </div>
</div>

<style>
  .page {
    max-width: 900px;
  }

  .page-header {
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

  .catalog-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
    gap: var(--spacing-xl);
  }
</style>