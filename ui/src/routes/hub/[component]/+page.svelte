<script lang="ts">
  import { page } from '$app/stores';
  import { goto } from '$app/navigation';
  import WizardRenderer from '$lib/components/WizardRenderer.svelte';
  import { api } from '$lib/api/client';

  let componentName = $derived($page.params.component);
  let wizardData = $state<any>(null);
  let wizardError = $state('');

  $effect(() => {
    const comp = componentName;
    wizardData = null;
    wizardError = '';
    api.getWizard(comp).then((data) => {
      if (data?.error) {
        wizardError = data.error;
      } else {
        wizardData = data;
      }
    }).catch((e) => {
      wizardError = (e as Error).message;
    });
  });
</script>

<svelte:head>
  <title>Install {componentName} - NullHubX</title>
</svelte:head>

<div class="wizard-page">
  <aside class="wizard-sidebar">
    <a href="/install" class="back-link">
      <span class="back-icon">←</span>
      <span>All Components</span>
    </a>

    <div class="component-info">
      <h1 class="component-name">{componentName}</h1>
      <p class="component-desc">Installation Wizard</p>
    </div>

    <hr class="divider" />

    <nav class="wizard-nav">
      <div class="nav-item active">
        <span class="nav-icon">⚙</span>
        <span class="nav-label">Setup</span>
      </div>
    </nav>

    <div class="sidebar-footer">
      <p class="help-text">Need help? Check the documentation.</p>
    </div>
  </aside>

  <main class="wizard-content">
    {#if wizardError}
      <div class="wizard-error">
        <div class="error-icon">⚠</div>
        <h2>Unable to Load Wizard</h2>
        <p>{wizardError}</p>
        <button class="back-btn" onclick={() => goto('/install')}>Back to Components</button>
      </div>
    {:else if wizardData}
      <WizardRenderer
        component={componentName}
        steps={(wizardData?.wizard?.steps || wizardData?.steps || []).filter((s: any) => s.id !== 'gateway_port' && s.id !== 'port')}
        onComplete={() => goto('/')}
      />
    {:else}
      <div class="loading-state">
        <div class="loading-spinner"></div>
        <p>Loading wizard...</p>
      </div>
    {/if}
  </main>
</div>

<style>
  .wizard-page {
    display: flex;
    min-height: calc(100vh - 60px);
  }

  .wizard-sidebar {
    width: 240px;
    flex-shrink: 0;
    background: white;
    border-right: 1px solid var(--slate-200);
    padding: 20px 16px;
    display: flex;
    flex-direction: column;
  }

  .back-link {
    display: flex;
    align-items: center;
    gap: 6px;
    font-family: var(--font-mono);
    font-size: 11px;
    font-weight: 600;
    color: var(--slate-500);
    text-decoration: none;
    margin-bottom: 20px;
    padding: 8px 10px;
    border-radius: 6px;
    transition: all 0.15s ease;
  }

  .back-link:hover {
    background: var(--slate-100);
    color: var(--slate-700);
  }

  .back-icon {
    font-size: 12px;
  }

  .component-info {
    margin-bottom: 16px;
  }

  .component-name {
    font-family: var(--font-mono);
    font-size: 18px;
    font-weight: 700;
    color: var(--slate-900);
    margin: 0 0 4px 0;
    text-transform: uppercase;
    letter-spacing: 1px;
  }

  .component-desc {
    font-size: 12px;
    color: var(--slate-500);
    margin: 0;
  }

  .divider {
    border: none;
    height: 1px;
    background: var(--slate-200);
    margin: 16px 0;
  }

  .wizard-nav {
    display: flex;
    flex-direction: column;
    gap: 4px;
    flex: 1;
  }

  .nav-item {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 10px 12px;
    border-radius: 6px;
    font-family: var(--font-mono);
    font-size: 12px;
    font-weight: 600;
    color: var(--slate-600);
    transition: all 0.15s ease;
  }

  .nav-item.active {
    background: var(--indigo-50);
    color: var(--indigo-700);
  }

  .nav-icon {
    font-size: 14px;
    width: 16px;
    text-align: center;
  }

  .nav-label {
    letter-spacing: 0.5px;
  }

  .sidebar-footer {
    margin-top: auto;
    padding-top: 16px;
  }

  .help-text {
    font-size: 11px;
    color: var(--slate-400);
    margin: 0;
  }

  .wizard-content {
    flex: 1;
    padding: 24px 32px;
    background: var(--slate-50);
    overflow-y: auto;
  }

  .wizard-error {
    max-width: 400px;
    margin: 60px auto;
    text-align: center;
    background: white;
    border: 1px solid var(--red-200);
    border-radius: 12px;
    padding: 40px 32px;
  }

  .error-icon {
    font-size: 40px;
    margin-bottom: 16px;
  }

  .wizard-error h2 {
    font-family: var(--font-mono);
    font-size: 18px;
    font-weight: 700;
    color: var(--slate-800);
    margin: 0 0 12px 0;
  }

  .wizard-error p {
    color: var(--slate-600);
    font-size: 14px;
    margin: 0 0 20px 0;
  }

  .back-btn {
    padding: 10px 24px;
    background: var(--indigo-600);
    color: white;
    border: none;
    border-radius: 6px;
    font-family: var(--font-mono);
    font-size: 12px;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.15s ease;
  }

  .back-btn:hover {
    background: var(--indigo-700);
  }

  .loading-state {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    min-height: 400px;
    gap: 16px;
  }

  .loading-spinner {
    width: 32px;
    height: 32px;
    border: 2px solid var(--slate-200);
    border-top-color: var(--indigo-500);
    border-radius: 50%;
    animation: spin 0.8s linear infinite;
  }

  @keyframes spin {
    to { transform: rotate(360deg); }
  }

  .loading-state p {
    color: var(--slate-500);
    font-size: 13px;
  }

  @media (max-width: 768px) {
    .wizard-page {
      flex-direction: column;
    }

    .wizard-sidebar {
      width: 100%;
      border-right: none;
      border-bottom: 1px solid var(--slate-200);
      padding: 16px;
    }

    .wizard-nav {
      flex-direction: row;
    }

    .wizard-content {
      padding: 16px;
    }
  }
</style>