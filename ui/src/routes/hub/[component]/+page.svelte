<script lang="ts">
  import { page } from '$app/stores';
  import { goto } from '$app/navigation';
  import WizardRenderer from '$lib/components/WizardRenderer.svelte';
  import {
    api,
    type WizardOptionPayload,
    type WizardPayload,
    type WizardStepPayload,
  } from '$lib/api/client';
  import { t } from '$lib/i18n/index.svelte';

  let componentName = $derived($page.params.component);
  let wizardData = $state<WizardPayload | null>(null);
  let wizardError = $state('');
  const wizardSteps = $derived(
    (wizardData?.wizard?.steps || wizardData?.steps || [])
      .filter((step: WizardStepPayload) => step.id !== 'gateway_port' && step.id !== 'port')
      .map((step: WizardStepPayload) => ({
        ...step,
        title: step.title ?? step.id,
        type: step.type ?? 'text',
        options: Array.isArray(step.options)
          ? step.options.map((option: WizardOptionPayload) => ({
              ...option,
              label: option.label ?? option.value,
            }))
          : undefined,
      })),
  );

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
  <title>{t('wizardPage.title').replace('{component}', componentName)} - NullHubX</title>
</svelte:head>

<div class="wizard-page">
  <aside class="wizard-sidebar">
    <a href="/hub" class="back-link">
      <span class="back-icon">←</span>
      <span>{t('wizardPage.allComponents')}</span>
    </a>

    <div class="component-info">
      <h1 class="component-name">{componentName}</h1>
      <p class="component-desc">{t('wizardPage.installationWizard')}</p>
    </div>

    <hr class="divider" />

    <nav class="wizard-nav">
      <div class="nav-item active">
        <span class="nav-icon">⚙</span>
        <span class="nav-label">{t('wizardPage.setup')}</span>
      </div>
    </nav>

    <div class="sidebar-footer">
      <p class="help-text">{t('wizardPage.helpText')}</p>
    </div>
  </aside>

  <main class="wizard-content">
    {#if wizardError}
      <div class="wizard-error">
        <div class="error-icon">⚠</div>
        <h2>{t('wizardPage.unableToLoad')}</h2>
        <p>{wizardError}</p>
        <button class="back-btn" onclick={() => goto('/hub')}>{t('wizardPage.backToComponents')}</button>
      </div>
    {:else if wizardData}
      <WizardRenderer
        component={componentName}
        steps={wizardSteps}
        onComplete={() => goto('/')}
      />
    {:else}
      <div class="loading-state">
        <div class="loading-spinner"></div>
        <p>{t('wizardPage.loading')}</p>
      </div>
    {/if}
  </main>
</div>

<style>
  .wizard-page {
    display: flex;
    min-height: calc(100vh - 60px);
    background:
      radial-gradient(circle at top right, rgba(34, 211, 238, 0.08), transparent 30%),
      linear-gradient(180deg, rgba(248, 250, 252, 0.96), rgba(241, 245, 249, 0.92));
  }

  .wizard-sidebar {
    width: 240px;
    flex-shrink: 0;
    background: linear-gradient(180deg, rgba(255, 255, 255, 0.88), rgba(244, 248, 255, 0.82));
    border-right: 1px solid rgba(141, 154, 178, 0.16);
    padding: 20px 16px;
    display: flex;
    flex-direction: column;
    backdrop-filter: blur(16px);
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
    background: rgba(34, 211, 238, 0.08);
    color: var(--cyan-700);
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
    background: rgba(34, 211, 238, 0.08);
    color: var(--cyan-700);
    border: 1px solid rgba(34, 211, 238, 0.16);
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
    overflow-y: auto;
  }

  .wizard-error {
    max-width: 400px;
    margin: 60px auto;
    text-align: center;
    background: linear-gradient(180deg, rgba(255, 255, 255, 0.92), rgba(254, 242, 242, 0.88));
    border: 1px solid rgba(248, 113, 113, 0.2);
    border-radius: var(--radius-xl);
    padding: 40px 32px;
    box-shadow: var(--shadow-lg);
    backdrop-filter: blur(14px);
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
    padding: 0.72rem 1.2rem;
    background: linear-gradient(135deg, var(--cyan-600), var(--cyan-500));
    color: white;
    border: 1px solid rgba(8, 145, 178, 0.22);
    border-radius: 999px;
    font-family: var(--font-sans);
    font-size: 0.82rem;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.2s ease;
    box-shadow: 0 12px 24px rgba(8, 145, 178, 0.18);
  }

  .back-btn:hover {
    transform: translateY(-1px);
    filter: brightness(1.04);
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
    border-top-color: var(--cyan-500);
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
      border-bottom: 1px solid rgba(141, 154, 178, 0.16);
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
