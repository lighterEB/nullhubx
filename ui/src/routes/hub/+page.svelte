<script lang="ts">
  import { afterNavigate } from "$app/navigation";
  import ComponentCard from "$lib/components/ComponentCard.svelte";
  import { api } from "$lib/api/client";
  import { t } from "$lib/i18n/index.svelte";

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

  // Separate core engine (nullclaw) from extensions
  let coreEngine = $derived(components.find(c => c.name === "nullclaw"));
  let extensions = $derived(components.filter(c => c.name !== "nullclaw"));
  
  // Split extensions into available and coming soon
  let availableExtensions = $derived(extensions.filter(c => !c.alpha || c.installed));
  let comingSoonExtensions = $derived(extensions.filter(c => c.alpha && !c.installed && !c.standalone));
</script>

<svelte:head>
  <title>{t('hub.title')} - NullHubX</title>
</svelte:head>

<div class="page">
  <header class="page-header">
    <div class="header-left">
      <div class="breadcrumb">
        <span class="breadcrumb-item">NullHubX</span>
        <span class="breadcrumb-sep">/</span>
        <span class="breadcrumb-item active">{t('hub.title')}</span>
      </div>
      <h1>
        {t('hub.title')}
      </h1>
      <p class="subtitle">{t('hub.subtitle')}</p>
    </div>
  </header>

  <hr class="divider" />

  <!-- Core Engine Section -->
  <section class="section">
    <div class="section-header">
      <h2 class="section-title">
        <span class="section-icon">⬡</span>
        {t('hub.coreEngine')}
      </h2>
      <p class="section-desc">{t('hub.coreEngineDesc')}</p>
    </div>
    
    <div class="core-grid">
      {#if coreEngine}
        <div class="core-card-wrapper">
          <ComponentCard
            name={coreEngine.name}
            displayName={coreEngine.display_name}
            description={coreEngine.description}
            alpha={coreEngine.alpha}
            installed={coreEngine.installed}
            standalone={coreEngine.standalone}
            instanceCount={coreEngine.instance_count}
          />
        </div>
      {:else}
        <div class="loading-card">
          <div class="loading-spinner"></div>
          <span>{t('common.loading')}</span>
        </div>
      {/if}
    </div>
  </section>

  <!-- Extensions Section -->
  {#if availableExtensions.length > 0}
    <section class="section">
      <div class="section-header">
        <h2 class="section-title">
          <span class="section-icon">⊕</span>
          {t('hub.extensions')}
        </h2>
        <p class="section-desc">{t('hub.extensionsDesc')}</p>
      </div>
      
      <div class="extensions-grid">
        {#each availableExtensions as comp, i}
          <div class="card-wrapper" style="animation-delay: {i * 60}ms">
            <ComponentCard
              name={comp.name}
              displayName={comp.display_name}
              description={comp.description}
              alpha={comp.alpha}
              installed={comp.installed}
              standalone={comp.standalone}
              instanceCount={comp.instance_count}
            />
          </div>
        {/each}
      </div>
    </section>
  {/if}

  <!-- Coming Soon Section -->
  {#if comingSoonExtensions.length > 0}
    <section class="section">
      <div class="section-header">
        <h2 class="section-title">
          <span class="section-icon">◦</span>
          {t('common.comingSoon')}
        </h2>
        <p class="section-desc">{t('hub.comingSoonDesc')}</p>
      </div>
      
      <div class="extensions-grid coming-soon">
        {#each comingSoonExtensions as comp, i}
          <div class="card-wrapper" style="animation-delay: {i * 60}ms">
            <ComponentCard
              name={comp.name}
              displayName={comp.display_name}
              description={comp.description}
              alpha={comp.alpha}
              installed={comp.installed}
              standalone={comp.standalone}
              instanceCount={comp.instance_count}
            />
          </div>
        {/each}
      </div>
    </section>
  {/if}
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

  .section {
    margin-bottom: var(--spacing-3xl);
  }

  .section-header {
    margin-bottom: var(--spacing-xl);
  }

  .section-title {
    font-family: var(--font-mono);
    font-size: var(--text-lg);
    font-weight: 600;
    color: var(--slate-800);
    letter-spacing: 1px;
    display: flex;
    align-items: center;
    gap: var(--spacing-sm);
    margin: 0 0 var(--spacing-xs) 0;
  }

  .section-icon {
    font-size: var(--text-xl);
    color: var(--indigo-500);
  }

  .section-desc {
    font-family: var(--font-sans);
    font-size: var(--text-sm);
    color: var(--slate-500);
    margin: 0;
  }

  .core-grid {
    display: grid;
    grid-template-columns: 1fr;
    gap: var(--spacing-xl);
  }

  .extensions-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(320px, 1fr));
    gap: var(--spacing-lg);
  }

  .extensions-grid.coming-soon {
    opacity: 0.7;
  }

  .card-wrapper {
    opacity: 0;
    animation: fadeUp 0.4s ease forwards;
  }

  .core-card-wrapper {
    opacity: 0;
    animation: fadeUp 0.5s ease forwards;
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

  .loading-card {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: var(--spacing-md);
    padding: var(--spacing-3xl);
    background: white;
    border: 1px solid var(--slate-200);
    border-radius: var(--radius-lg);
    color: var(--slate-500);
    font-family: var(--font-sans);
    font-size: var(--text-sm);
  }

  .loading-spinner {
    width: 20px;
    height: 20px;
    border: 2px solid var(--slate-200);
    border-top-color: var(--indigo-500);
    border-radius: 50%;
    animation: spin 0.8s linear infinite;
  }

  @keyframes spin {
    to { transform: rotate(360deg); }
  }

  @media (max-width: 768px) {
    .page {
      padding: var(--spacing-xl);
    }

    .extensions-grid {
      grid-template-columns: 1fr;
    }
  }
</style>
