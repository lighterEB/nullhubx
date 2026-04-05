<script lang="ts">
  import { onMount } from 'svelte';
  import {
    api,
    type JsonObject,
    type LinkedInstanceRef,
    type SavedChannel,
    type SavedProvider,
  } from '$lib/api/client';
  import { t } from '$lib/i18n/index.svelte';

  type Tone = 'success' | 'error';
  type EditorMode = 'create' | 'edit';

  type ProviderForm = {
    id: string | null;
    name: string;
    provider: string;
    apiKey: string;
    model: string;
  };

  type ChannelForm = {
    id: string | null;
    name: string;
    channelType: string;
    account: string;
    configText: string;
  };

  const emptyProviderForm = (): ProviderForm => ({
    id: null,
    name: '',
    provider: '',
    apiKey: '',
    model: '',
  });

  const emptyChannelForm = (): ChannelForm => ({
    id: null,
    name: '',
    channelType: '',
    account: '',
    configText: '{\n  \n}',
  });

  let loading = $state(true);
  let error = $state('');
  let message = $state('');
  let messageTone = $state<Tone>('success');
  let providers = $state<SavedProvider[]>([]);
  let channels = $state<SavedChannel[]>([]);

  let providerMode = $state<EditorMode>('create');
  let providerForm = $state<ProviderForm>(emptyProviderForm());
  let providerBusy = $state(false);
  let providerActionBusy = $state<string | null>(null);

  let channelMode = $state<EditorMode>('create');
  let channelForm = $state<ChannelForm>(emptyChannelForm());
  let channelBusy = $state(false);
  let channelActionBusy = $state<string | null>(null);

  const validatedProviders = $derived(
    providers.filter((provider) => provider.last_validation_ok).length,
  );
  const validatedChannels = $derived(
    channels.filter((channel) => Boolean(channel.validated_at)).length,
  );

  function translate(key: string, replacements: Record<string, string | number> = {}): string {
    let message = t(key);
    for (const [name, value] of Object.entries(replacements)) {
      message = message.replace(`{${name}}`, String(value));
    }
    return message;
  }

  function setMessage(text: string, tone: Tone = 'success') {
    message = text;
    messageTone = tone;
  }

  function parseConfigText(raw: string): JsonObject {
    const trimmed = raw.trim();
    if (!trimmed) return {};
    const parsed = JSON.parse(trimmed) as unknown;
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) {
      throw new Error(t('connections.configMustBeObject'));
    }
    return parsed as JsonObject;
  }

  function formatConfig(value: unknown): string {
    if (!value || typeof value !== 'object' || Array.isArray(value)) {
      return '{\n  \n}';
    }
    return JSON.stringify(value, null, 2);
  }

  function providerDisplayName(provider: SavedProvider): string {
    return provider.name || provider.provider || String(provider.id || '-');
  }

  function channelDisplayName(channel: SavedChannel): string {
    return channel.name || channel.account || String(channel.id || '-');
  }

  function linkedInstances(value: LinkedInstanceRef[] | undefined): LinkedInstanceRef[] {
    return Array.isArray(value) ? value : [];
  }

  function orphanedTone(orphaned: boolean | undefined): 'bad' | 'ok' {
    return orphaned ? 'bad' : 'ok';
  }

  function resetProviderForm() {
    providerMode = 'create';
    providerForm = emptyProviderForm();
  }

  function resetChannelForm() {
    channelMode = 'create';
    channelForm = emptyChannelForm();
  }

  function startProviderEdit(provider: SavedProvider) {
    providerMode = 'edit';
    providerForm = {
      id: typeof provider.id === 'string' ? provider.id : null,
      name: typeof provider.name === 'string' ? provider.name : '',
      provider: typeof provider.provider === 'string' ? provider.provider : '',
      apiKey: '',
      model: typeof provider.model === 'string' ? provider.model : '',
    };
  }

  async function startChannelEdit(channel: SavedChannel) {
    channelActionBusy = `edit:${channel.id || channel.account || channel.channel_type || 'channel'}`;
    let editableChannel = channel;
    try {
      if (channel.id) {
        const channelData = await api.getSavedChannels(true);
        const revealed = (channelData?.channels || []).find((item) => item.id === channel.id);
        if (revealed) editableChannel = revealed;
      }
    } catch (e) {
      setMessage((e as Error).message || t('connections.channelLoadFailed'), 'error');
      channelActionBusy = null;
      return;
    }

    channelMode = 'edit';
    channelForm = {
      id: typeof editableChannel.id === 'string' ? editableChannel.id : null,
      name: typeof editableChannel.name === 'string' ? editableChannel.name : '',
      channelType:
        typeof editableChannel.channel_type === 'string' ? editableChannel.channel_type : '',
      account: typeof editableChannel.account === 'string' ? editableChannel.account : '',
      configText: formatConfig(editableChannel.config),
    };
    channelActionBusy = null;
  }

  async function load() {
    loading = true;
    error = '';
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

  async function submitProvider() {
    if (!providerForm.provider.trim()) {
      setMessage(t('connections.providerRequired'), 'error');
      return;
    }

    providerBusy = true;
    try {
      if (providerMode === 'create') {
        await api.createSavedProvider({
          provider: providerForm.provider.trim(),
          api_key: providerForm.apiKey.trim(),
          model: providerForm.model.trim() || undefined,
        });
        setMessage(
          translate('connections.providerCreated', { provider: providerForm.provider.trim() }),
        );
      } else if (providerForm.id) {
        const payload: { name?: string; api_key?: string; model?: string } = {
          name: providerForm.name.trim() || undefined,
          model: providerForm.model.trim() || '',
        };
        if (providerForm.apiKey.trim()) {
          payload.api_key = providerForm.apiKey.trim();
        }
        await api.updateSavedProvider(providerForm.id, payload);
        setMessage(
          translate('connections.providerUpdated', {
            name: providerForm.name.trim() || providerForm.provider.trim(),
          }),
        );
      }

      await load();
      resetProviderForm();
    } catch (e) {
      setMessage((e as Error).message || t('connections.providerSaveFailed'), 'error');
    } finally {
      providerBusy = false;
    }
  }

  async function submitChannel() {
    if (!channelForm.channelType.trim()) {
      setMessage(t('connections.channelTypeRequired'), 'error');
      return;
    }
    if (!channelForm.account.trim()) {
      setMessage(t('connections.accountRequired'), 'error');
      return;
    }

    let config: JsonObject;
    try {
      config = parseConfigText(channelForm.configText);
    } catch (e) {
      setMessage((e as Error).message || t('connections.configInvalid'), 'error');
      return;
    }

    channelBusy = true;
    try {
      if (channelMode === 'create') {
        await api.createSavedChannel({
          channel_type: channelForm.channelType.trim(),
          account: channelForm.account.trim(),
          config,
        });
        setMessage(
          translate('connections.channelCreated', { channel: channelForm.channelType.trim() }),
        );
      } else if (channelForm.id) {
        await api.updateSavedChannel(channelForm.id, {
          name: channelForm.name.trim() || undefined,
          account: channelForm.account.trim(),
          config,
        });
        setMessage(
          translate('connections.channelUpdated', {
            name: channelForm.name.trim() || channelForm.account.trim(),
          }),
        );
      }

      await load();
      resetChannelForm();
    } catch (e) {
      setMessage((e as Error).message || t('connections.channelSaveFailed'), 'error');
    } finally {
      channelBusy = false;
    }
  }

  async function revalidateProvider(provider: SavedProvider) {
    if (!provider.id) return;
    providerActionBusy = `validate:${provider.id}`;
    try {
      const result = await api.revalidateSavedProvider(provider.id);
      const ok = Boolean(result?.live_ok);
      const reason = typeof result?.reason === 'string' ? result.reason : '';
      setMessage(
        ok
          ? translate('connections.providerValidated', { name: providerDisplayName(provider) })
          : translate('connections.providerValidationFailedWithReason', {
              name: providerDisplayName(provider),
              reason: reason || t('connections.validationFailed'),
            }),
        ok ? 'success' : 'error',
      );
      await load();
    } catch (e) {
      setMessage((e as Error).message || t('connections.providerValidationFailed'), 'error');
    } finally {
      providerActionBusy = null;
    }
  }

  async function revalidateChannel(channel: SavedChannel) {
    if (!channel.id) return;
    channelActionBusy = `validate:${channel.id}`;
    try {
      const result = await api.revalidateSavedChannel(channel.id);
      const ok = Boolean(result?.live_ok);
      const reason = typeof result?.reason === 'string' ? result.reason : '';
      setMessage(
        ok
          ? translate('connections.channelValidated', { name: channelDisplayName(channel) })
          : translate('connections.channelValidationFailedWithReason', {
              name: channelDisplayName(channel),
              reason: reason || t('connections.validationFailed'),
            }),
        ok ? 'success' : 'error',
      );
      await load();
    } catch (e) {
      setMessage((e as Error).message || t('connections.channelValidationFailed'), 'error');
    } finally {
      channelActionBusy = null;
    }
  }

  async function deleteProvider(provider: SavedProvider) {
    if (!provider.id) return;
    const confirmed = window.confirm(
      translate('connections.confirmDeleteProvider', { name: providerDisplayName(provider) }),
    );
    if (!confirmed) return;

    providerActionBusy = `delete:${provider.id}`;
    try {
      await api.deleteSavedProvider(provider.id);
      setMessage(translate('connections.providerDeleted', { name: providerDisplayName(provider) }));
      await load();
      if (providerForm.id === provider.id) resetProviderForm();
    } catch (e) {
      setMessage((e as Error).message || t('connections.providerDeleteFailed'), 'error');
    } finally {
      providerActionBusy = null;
    }
  }

  async function deleteChannel(channel: SavedChannel) {
    if (!channel.id) return;
    const confirmed = window.confirm(
      translate('connections.confirmDeleteChannel', { name: channelDisplayName(channel) }),
    );
    if (!confirmed) return;

    channelActionBusy = `delete:${channel.id}`;
    try {
      await api.deleteSavedChannel(channel.id);
      setMessage(translate('connections.channelDeleted', { name: channelDisplayName(channel) }));
      await load();
      if (channelForm.id === channel.id) resetChannelForm();
    } catch (e) {
      setMessage((e as Error).message || t('connections.channelDeleteFailed'), 'error');
    } finally {
      channelActionBusy = null;
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
    <div class="feedback-banner error-banner">
      {t('error.loadFailed').replace('{error}', error)}
    </div>
  {/if}

  {#if message}
    <div class="feedback-banner" class:error-banner={messageTone === 'error'}>
      {message}
    </div>
  {/if}

  <div class="connections-grid">
    <section class="section-shell">
      <div class="section-heading-row">
        <div class="section-heading">
          <span class="section-kicker">{t('nav.resources')}</span>
          <h2 class="section-title">{t('connections.providers')}</h2>
          <p class="section-subtitle">{t('connections.providersDesc')}</p>
        </div>
        <span class="surface-chip">{providers.length}</span>
      </div>

      <div class="editor-card">
        <div class="editor-header">
          <div>
            <h3>
              {providerMode === 'create'
                ? t('connections.addProvider')
                : t('connections.editProvider')}
            </h3>
            <p>
              {providerMode === 'create'
                ? t('connections.providerCreateHint')
                : t('connections.providerEditHint')}
            </p>
          </div>
          {#if providerMode === 'edit'}
            <button class="control-btn secondary small-btn" onclick={resetProviderForm}>
              {t('connections.cancelEdit')}
            </button>
          {/if}
        </div>

        {#if providerMode === 'edit'}
          <div class="field">
            <label for="provider-name">{t('connections.nameLabel')}</label>
            <input id="provider-name" type="text" bind:value={providerForm.name} />
          </div>
        {/if}

        <div class="field-grid">
          <div class="field">
            <label for="provider-type">{t('connections.providerLabel')}</label>
            <input
              id="provider-type"
              type="text"
              bind:value={providerForm.provider}
              disabled={providerMode === 'edit'}
            />
          </div>
          <div class="field">
            <label for="provider-model">{t('connections.defaultModel')}</label>
            <input id="provider-model" type="text" bind:value={providerForm.model} />
          </div>
        </div>

        <div class="field">
          <label for="provider-api-key">{t('connections.apiKey')}</label>
          <input
            id="provider-api-key"
            type="password"
            bind:value={providerForm.apiKey}
            placeholder={providerMode === 'edit' ? t('connections.providerApiKeyOptional') : ''}
          />
          <p class="hint">
            {providerMode === 'edit'
              ? t('connections.providerApiKeyHintEdit')
              : t('connections.providerApiKeyHintCreate')}
          </p>
        </div>

        <div class="form-actions">
          <button class="control-btn primary" onclick={submitProvider} disabled={providerBusy}>
            {providerBusy
              ? t('common.loading')
              : providerMode === 'create'
                ? t('connections.createProvider')
                : t('connections.saveProvider')}
          </button>
        </div>
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
                <th>{t('connections.lastValidated')}</th>
                <th>{t('connections.linkedInstances')}</th>
                <th>{t('connections.linkStatus')}</th>
                <th>{t('common.actions')}</th>
              </tr>
            </thead>
            <tbody>
              {#each providers as provider}
                <tr>
                  <td class="mono-cell">{providerDisplayName(provider)}</td>
                  <td><span class="surface-chip type-chip">{provider.provider}</span></td>
                  <td class="mono-cell">{provider.model || '-'}</td>
                  <td>
                    {#if provider.last_validation_ok}
                      <span class="table-status ok">{t('connections.validationPassed')}</span>
                    {:else if provider.last_validation_at}
                      <span class="table-status bad">{t('connections.validationFailed')}</span>
                    {:else}
                      <span class="table-status pending">{t('connections.validationPending')}</span>
                    {/if}
                  </td>
                  <td class="mono-cell"
                    >{provider.last_validation_at || provider.validated_at || '-'}</td
                  >
                  <td>
                    <div class="linked-cell">
                      {#if linkedInstances(provider.linked_instances).length > 0}
                        <div class="linked-list">
                          {#each linkedInstances(provider.linked_instances) as item}
                            <a
                              class="toolbar-link"
                              href={`/instances/${item.route || `${item.component}/${item.name}`}`}
                            >
                              {item.route || `${item.component}/${item.name}`}
                            </a>
                          {/each}
                        </div>
                      {:else}
                        <span class="mono-cell">-</span>
                      {/if}
                    </div>
                  </td>
                  <td>
                    <span class={`table-status ${orphanedTone(provider.orphaned)}`}>
                      {provider.orphaned ? t('connections.orphaned') : t('connections.linked')}
                    </span>
                  </td>
                  <td>
                    <div class="action-row">
                      <button
                        class="control-btn secondary small-btn"
                        onclick={() => startProviderEdit(provider)}
                      >
                        {t('connections.edit')}
                      </button>
                      <button
                        class="control-btn secondary small-btn"
                        onclick={() => revalidateProvider(provider)}
                        disabled={providerActionBusy !== null}
                      >
                        {providerActionBusy === `validate:${provider.id}`
                          ? t('common.loading')
                          : t('connections.validate')}
                      </button>
                      <button
                        class="control-btn secondary small-btn danger-btn"
                        onclick={() => deleteProvider(provider)}
                        disabled={providerActionBusy !== null}
                      >
                        {providerActionBusy === `delete:${provider.id}`
                          ? t('common.loading')
                          : t('connections.delete')}
                      </button>
                    </div>
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

      <div class="editor-card">
        <div class="editor-header">
          <div>
            <h3>
              {channelMode === 'create'
                ? t('connections.addChannel')
                : t('connections.editChannel')}
            </h3>
            <p>
              {channelMode === 'create'
                ? t('connections.channelCreateHint')
                : t('connections.channelEditHint')}
            </p>
          </div>
          {#if channelMode === 'edit'}
            <button class="control-btn secondary small-btn" onclick={resetChannelForm}>
              {t('connections.cancelEdit')}
            </button>
          {/if}
        </div>

        {#if channelMode === 'edit'}
          <div class="field">
            <label for="channel-name">{t('connections.nameLabel')}</label>
            <input id="channel-name" type="text" bind:value={channelForm.name} />
          </div>
        {/if}

        <div class="field-grid">
          <div class="field">
            <label for="channel-type">{t('connections.channelType')}</label>
            <input
              id="channel-type"
              type="text"
              bind:value={channelForm.channelType}
              disabled={channelMode === 'edit'}
            />
          </div>
          <div class="field">
            <label for="channel-account">{t('connections.accountLabel')}</label>
            <input id="channel-account" type="text" bind:value={channelForm.account} />
          </div>
        </div>

        <div class="field">
          <label for="channel-config">{t('connections.channelConfig')}</label>
          <textarea id="channel-config" rows="10" bind:value={channelForm.configText}></textarea>
          <p class="hint">{t('connections.channelConfigHint')}</p>
        </div>

        <div class="form-actions">
          <button class="control-btn primary" onclick={submitChannel} disabled={channelBusy}>
            {channelBusy
              ? t('common.loading')
              : channelMode === 'create'
                ? t('connections.createChannel')
                : t('connections.saveChannel')}
          </button>
        </div>
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
                <th>{t('connections.linkedInstances')}</th>
                <th>{t('connections.linkStatus')}</th>
                <th>{t('common.actions')}</th>
              </tr>
            </thead>
            <tbody>
              {#each channels as channel}
                <tr>
                  <td class="mono-cell">{channelDisplayName(channel)}</td>
                  <td><span class="surface-chip type-chip">{channel.channel_type}</span></td>
                  <td class="mono-cell">{channel.account}</td>
                  <td class="mono-cell"
                    >{channel.validated_at || t('connections.validationPending')}</td
                  >
                  <td>
                    <div class="linked-cell">
                      {#if linkedInstances(channel.linked_instances).length > 0}
                        <div class="linked-list">
                          {#each linkedInstances(channel.linked_instances) as item}
                            <a
                              class="toolbar-link"
                              href={`/instances/${item.route || `${item.component}/${item.name}`}`}
                            >
                              {item.route || `${item.component}/${item.name}`}
                            </a>
                          {/each}
                        </div>
                      {:else}
                        <span class="mono-cell">-</span>
                      {/if}
                    </div>
                  </td>
                  <td>
                    <span class={`table-status ${orphanedTone(channel.orphaned)}`}>
                      {channel.orphaned ? t('connections.orphaned') : t('connections.linked')}
                    </span>
                  </td>
                  <td>
                    <div class="action-row">
                      <button
                        class="control-btn secondary small-btn"
                        onclick={() => void startChannelEdit(channel)}
                        disabled={channelActionBusy !== null}
                      >
                        {channelActionBusy === `edit:${channel.id}`
                          ? t('common.loading')
                          : t('connections.edit')}
                      </button>
                      <button
                        class="control-btn secondary small-btn"
                        onclick={() => revalidateChannel(channel)}
                        disabled={channelActionBusy !== null}
                      >
                        {channelActionBusy === `validate:${channel.id}`
                          ? t('common.loading')
                          : t('connections.validate')}
                      </button>
                      <button
                        class="control-btn secondary small-btn danger-btn"
                        onclick={() => deleteChannel(channel)}
                        disabled={channelActionBusy !== null}
                      >
                        {channelActionBusy === `delete:${channel.id}`
                          ? t('common.loading')
                          : t('connections.delete')}
                      </button>
                    </div>
                  </td>
                </tr>
              {/each}
            </tbody>
          </table>
        </div>
      {/if}
    </section>
  </div>
</div>

<style>
  .hero-shell {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-xl);
  }

  .connections-grid {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: var(--spacing-lg);
    align-items: start;
  }

  .feedback-banner {
    padding: var(--spacing-md) var(--spacing-lg);
    border-radius: var(--radius-lg);
    border: 1px solid rgba(16, 185, 129, 0.16);
    background: rgba(236, 253, 245, 0.82);
    color: var(--emerald-700);
    box-shadow: var(--shadow-sm);
  }

  .error-banner {
    border-color: rgba(244, 63, 94, 0.16);
    background: rgba(255, 241, 245, 0.82);
    color: var(--red-700);
  }

  .editor-card {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-md);
    padding: var(--spacing-lg);
    margin-bottom: var(--spacing-lg);
    border-radius: var(--radius-xl);
    border: 1px solid rgba(141, 154, 178, 0.16);
    background: rgba(255, 255, 255, 0.68);
  }

  .editor-header {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
    gap: var(--spacing-md);
  }

  .editor-header h3 {
    margin: 0;
    color: var(--slate-900);
    font-size: var(--text-lg);
  }

  .editor-header p {
    margin: 4px 0 0;
    color: var(--slate-500);
    font-size: var(--text-sm);
    line-height: 1.6;
  }

  .field,
  .field-grid {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-xs);
  }

  .field-grid {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: var(--spacing-md);
  }

  .field label {
    color: var(--slate-700);
    font-size: var(--text-sm);
    font-weight: 600;
  }

  .field input,
  .field textarea {
    width: 100%;
    font-family: var(--font-sans);
  }

  .field textarea {
    font-family: var(--font-mono);
    resize: vertical;
  }

  .hint {
    margin: 0;
    color: var(--slate-500);
    font-size: var(--text-xs);
    line-height: 1.5;
  }

  .form-actions {
    display: flex;
    justify-content: flex-end;
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

  .action-row {
    display: flex;
    flex-wrap: wrap;
    gap: var(--spacing-sm);
  }

  .linked-cell {
    min-width: 200px;
  }

  .linked-list {
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  .toolbar-link {
    color: var(--cyan-700);
    font-size: var(--text-sm);
    text-decoration: none;
  }

  .toolbar-link:hover {
    text-decoration: underline;
  }

  .small-btn {
    min-height: 36px;
    padding: 0.55rem 0.85rem;
    font-size: var(--text-xs);
  }

  .danger-btn {
    border-color: rgba(244, 63, 94, 0.16);
    color: var(--red-600);
  }

  @media (max-width: 1100px) {
    .connections-grid {
      grid-template-columns: 1fr;
    }
  }

  @media (max-width: 780px) {
    .field-grid {
      grid-template-columns: 1fr;
    }

    .editor-header,
    .form-actions {
      flex-direction: column;
    }

    .form-actions :global(.control-btn),
    .action-row :global(.control-btn) {
      width: 100%;
    }
  }
</style>
