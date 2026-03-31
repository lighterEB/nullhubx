<script lang="ts">
  import { afterNavigate } from "$app/navigation";
  import ComponentCard from "$lib/components/ComponentCard.svelte";
  import { api, type ComponentSummary } from "$lib/api/client";
  import { t } from "$lib/i18n/index.svelte";

  let components = $state<ComponentSummary[]>([]);

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
  let coreEngine = $derived(components.find((c) => c.name === "nullclaw"));
  let extensions = $derived(components.filter((c) => c.name !== "nullclaw"));

  // Split extensions into available and coming soon
  let availableExtensions = $derived(extensions.filter((c) => !c.alpha || c.installed));
  let comingSoonExtensions = $derived(extensions.filter((c) => c.alpha && !c.installed && !c.standalone));
  let installedCount = $derived(components.filter((c) => c.installed).length);
</script>

<svelte:head>
  <title>{t('hub.title')} - NullHubX</title>
</svelte:head>

<div class="page-shell hub-page">
  <section class="section-shell hero-shell">
    <div class="page-hero">
      <div class="page-title-group">
        <span class="page-kicker">NullHubX</span>
        <h1 class="page-title">{t('hub.title')}</h1>
        <p class="page-subtitle">{t('hub.subtitle')}</p>
      </div>
      <div class="page-actions">
        <span class="surface-chip">{t('hub.coreEngine')}</span>
        <span class="surface-chip">{t('hub.extensions')}</span>
      </div>
    </div>

    <div class="metrics-grid">
      <article class="metric-card">
        <span class="metric-label">{t('hub.title')}</span>
        <strong class="metric-value">{components.length}</strong>
        <p class="metric-meta">{t('overview.componentCount')}</p>
      </article>
      <article class="metric-card">
        <span class="metric-label">{t('hub.installed')}</span>
        <strong class="metric-value">{installedCount}</strong>
        <p class="metric-meta">{t('instances.title')}</p>
      </article>
      <article class="metric-card">
        <span class="metric-label">{t('hub.extensions')}</span>
        <strong class="metric-value">{availableExtensions.length}</strong>
        <p class="metric-meta">{t('hub.extensionsDesc')}</p>
      </article>
      <article class="metric-card">
        <span class="metric-label">{t('common.comingSoon')}</span>
        <strong class="metric-value">{comingSoonExtensions.length}</strong>
        <p class="metric-meta">{t('hub.comingSoonDesc')}</p>
      </article>
    </div>
  </section>

  <section class="section-shell section-panel core-panel">
    <div class="section-heading-row">
      <div class="section-heading">
        <span class="section-kicker">{t('hub.title')}</span>
        <h2 class="section-title">{t('hub.coreEngine')}</h2>
        <p class="section-subtitle">{t('hub.coreEngineDesc')}</p>
      </div>
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

  {#if availableExtensions.length > 0}
    <section class="section-shell section-panel">
      <div class="section-heading-row">
        <div class="section-heading">
          <span class="section-kicker">{t('hub.title')}</span>
          <h2 class="section-title">{t('hub.extensions')}</h2>
          <p class="section-subtitle">{t('hub.extensionsDesc')}</p>
        </div>
        <span class="surface-chip">{availableExtensions.length}</span>
      </div>

      <div class="extensions-grid">
        {#each availableExtensions as comp}
          <div class="card-wrapper">
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

  {#if comingSoonExtensions.length > 0}
    <section class="section-shell section-panel">
      <div class="section-heading-row">
        <div class="section-heading">
          <span class="section-kicker">{t('hub.title')}</span>
          <h2 class="section-title">{t('common.comingSoon')}</h2>
          <p class="section-subtitle">{t('hub.comingSoonDesc')}</p>
        </div>
        <span class="surface-chip">{comingSoonExtensions.length}</span>
      </div>

      <div class="extensions-grid coming-soon">
        {#each comingSoonExtensions as comp}
          <div class="card-wrapper">
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
  .hero-shell {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-xl);
  }

  .section-panel {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-lg);
  }

  .core-panel {
    background:
      linear-gradient(180deg, rgba(255, 255, 255, 0.88), rgba(243, 248, 255, 0.74)),
      radial-gradient(circle at top right, rgba(34, 211, 238, 0.12), transparent 28%);
  }

  .core-grid {
    display: grid;
    grid-template-columns: 1fr;
  }

  .extensions-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(300px, 1fr));
    gap: var(--spacing-lg);
  }

  .extensions-grid.coming-soon {
    opacity: 0.78;
  }

  .card-wrapper,
  .core-card-wrapper {
    display: block;
  }

  .loading-card {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: var(--spacing-md);
    padding: var(--spacing-3xl);
    background: rgba(255, 255, 255, 0.7);
    border: 1px solid rgba(141, 154, 178, 0.18);
    border-radius: var(--radius-lg);
    color: var(--slate-500);
    font-size: var(--text-sm);
  }

  .loading-spinner {
    width: 20px;
    height: 20px;
    border: 2px solid rgba(141, 154, 178, 0.24);
    border-top-color: var(--cyan-500);
    border-radius: 50%;
    animation: spin 0.8s linear infinite;
  }

  @keyframes spin {
    to { transform: rotate(360deg); }
  }

  @media (max-width: 768px) {
    .extensions-grid {
      grid-template-columns: 1fr;
    }
  }
</style>
