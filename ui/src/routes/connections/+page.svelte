<script lang="ts">
  import { onMount } from "svelte";
  import { api, type SavedChannel, type SavedProvider } from "$lib/api/client";
  import { t } from "$lib/i18n/index.svelte";

  let loading = $state(true);
  let error = $state("");
  let providers = $state<SavedProvider[]>([]);
  let channels = $state<SavedChannel[]>([]);
  const validatedProviders = $derived(providers.filter((provider) => provider.last_validation_ok).length);
  const validatedChannels = $derived(channels.filter((channel) => Boolean(channel.validated_at)).length);

  async function load() {
    loading = true;
    error = "";
    try {
      const [providerData, channelData] = await Promise.all([
        api.getSavedProviders(),
        api.getSavedChannels(),
      ]);
      providers = providerData?.providers || [];
      channels = channelData?.channels || [];
    } catch (e) {
      error = e instanceof Error ? e.message : t('common.error');
    } finally {
      loading = false;
    }
  }

  onMount(() => {
    void load();
  });
</script>

<svelte:head>
  <title>{t('connections.title')} - NullHubX</title>
</svelte:head>

<div class="page-shell connections-page">
  <section class="section-shell hero-shell">
    <div class="page-hero">
      <div class="page-title-group">
        <span class="page-kicker">NullHubX</span>
        <h1 class="page-title">{t('connections.title')}</h1>
        <p class="page-subtitle">{t('connections.subtitle')}</p>
      </div>
      <div class="page-actions">
        <button class="control-btn primary" onclick={load} disabled={loading}>
          {loading ? t('common.loading') : t('common.refresh')}
        </button>
      </div>
    </div>

    <div class="metrics-grid">
      <article class="metric-card">
        <span class="metric-label">{t('connections.providers')}</span>
        <strong class="metric-value">{providers.length}</strong>
        <p class="metric-meta">{t('connections.providersDesc')}</p>
      </article>
      <article class="metric-card">
        <span class="metric-label">{t('connections.validationStatus')}</span>
        <strong class="metric-value">{validatedProviders}</strong>
        <p class="metric-meta">{t('connections.validationPassed')}</p>
      </article>
      <article class="metric-card">
        <span class="metric-label">{t('connections.channels')}</span>
        <strong class="metric-value">{channels.length}</strong>
        <p class="metric-meta">{t('connections.channelsDesc')}</p>
      </article>
      <article class="metric-card">
        <span class="metric-label">{t('connections.lastValidated')}</span>
        <strong class="metric-value">{validatedChannels}</strong>
        <p class="metric-meta">{t('connections.validated')}</p>
      </article>
    </div>
  </section>

  {#if error}
    <div class="feedback-banner error-banner">{t('error.loadFailed').replace('{error}', error)}</div>
  {/if}

  <section class="section-shell">
    <div class="section-heading-row">
      <div class="section-heading">
        <span class="section-kicker">{t('nav.resources')}</span>
        <h2 class="section-title">{t('connections.providers')}</h2>
        <p class="section-subtitle">{t('connections.providersDesc')}</p>
      </div>
      <span class="surface-chip">{providers.length}</span>
    </div>

    {#if providers.length === 0}
      <p class="empty-panel">{t('common.noData')}</p>
    {:else}
      <div class="table-shell">
        <table class="data-table">
          <thead>
            <tr>
              <th>{t('connections.nameLabel')}</th>
              <th>{t('connections.providerLabel')}</th>
              <th>{t('connections.defaultModel')}</th>
              <th>{t('connections.validationStatus')}</th>
            </tr>
          </thead>
          <tbody>
            {#each providers as provider}
              <tr>
                <td class="mono-cell">{provider.name}</td>
                <td><span class="surface-chip type-chip">{provider.provider}</span></td>
                <td class="mono-cell">{provider.model || "-"}</td>
                <td>
                  {#if provider.last_validation_ok}
                    <span class="table-status ok">{t('connections.validationPassed')}</span>
                  {:else if provider.last_validation_at}
                    <span class="table-status bad">{t('connections.validationFailed')}</span>
                  {:else}
                    <span class="table-status pending">{t('connections.validationPending')}</span>
                  {/if}
                </td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    {/if}
  </section>

  <section class="section-shell">
    <div class="section-heading-row">
      <div class="section-heading">
        <span class="section-kicker">{t('nav.resources')}</span>
        <h2 class="section-title">{t('connections.channels')}</h2>
        <p class="section-subtitle">{t('connections.channelsDesc')}</p>
      </div>
      <span class="surface-chip">{channels.length}</span>
    </div>

    {#if channels.length === 0}
      <p class="empty-panel">{t('common.noData')}</p>
    {:else}
      <div class="table-shell">
        <table class="data-table">
          <thead>
            <tr>
              <th>{t('connections.nameLabel')}</th>
              <th>{t('connections.channelType')}</th>
              <th>{t('connections.accountLabel')}</th>
              <th>{t('connections.lastValidated')}</th>
            </tr>
          </thead>
          <tbody>
            {#each channels as channel}
              <tr>
                <td class="mono-cell">{channel.name}</td>
                <td><span class="surface-chip type-chip">{channel.channel_type}</span></td>
                <td class="mono-cell">{channel.account}</td>
                <td class="mono-cell">{channel.validated_at || t('connections.validationPending')}</td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    {/if}
  </section>
</div>

<style>
  .hero-shell {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-xl);
  }

  .feedback-banner {
    padding: var(--spacing-md) var(--spacing-lg);
    border-radius: var(--radius-lg);
    border: 1px solid rgba(244, 63, 94, 0.16);
    background: rgba(255, 241, 245, 0.82);
    color: var(--red-700);
    box-shadow: var(--shadow-sm);
  }

  .mono-cell {
    font-family: var(--font-mono);
  }

  .type-chip {
    text-transform: uppercase;
  }

  .table-status {
    display: inline-flex;
    align-items: center;
    padding: 5px 10px;
    border-radius: 999px;
    font-size: var(--text-xs);
    font-weight: 600;
    letter-spacing: 0.04em;
  }

  .table-status.ok {
    background: rgba(16, 185, 129, 0.12);
    color: var(--emerald-700);
    border: 1px solid rgba(16, 185, 129, 0.18);
  }

  .table-status.bad {
    background: rgba(244, 63, 94, 0.1);
    color: var(--red-600);
    border: 1px solid rgba(244, 63, 94, 0.16);
  }

  .table-status.pending {
    background: rgba(255, 255, 255, 0.82);
    color: var(--slate-500);
    border: 1px solid rgba(141, 154, 178, 0.18);
  }

  @media (max-width: 780px) {
    .type-chip {
      white-space: nowrap;
    }
  }
</style>
