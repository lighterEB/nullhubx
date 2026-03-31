<script lang="ts">
  import {
    getFieldPath,
    getFieldReadPaths,
    getFieldValue,
    type ConfigFieldDef
  } from './configSchemaContract';
  import { channelSchemas, staticSections } from './configSchemas';
  import KeyValueEditor from './config-editors/KeyValueEditor.svelte';
  import ObjectListEditor from './config-editors/ObjectListEditor.svelte';
  import MemoryConfigModule from './config-modules/MemoryConfigModule.svelte';
  import PeripheralsConfigModule from './config-modules/PeripheralsConfigModule.svelte';
  import { t } from '$lib/i18n/index.svelte';

  let { config = $bindable({}), onchange = () => {} }: {
    config: any;
    onchange: () => void;
  } = $props();

  let openSections = $state<Record<string, boolean>>({});
  let addChannelOpen = $state(false);
  let drafts = $state<Record<string, string>>({});
  let fieldErrors = $state<Record<string, string>>({});

  function toggle(key: string) {
    openSections[key] = !openSections[key];
  }

  function getPath(obj: any, path: string): any {
    return path.split('.').reduce((o, k) => o?.[k], obj);
  }

  function setPath(obj: any, path: string, value: any): any {
    const clone = JSON.parse(JSON.stringify(obj));
    const keys = path.split('.');
    let cur = clone;
    for (let i = 0; i < keys.length - 1; i++) {
      if (cur[keys[i]] === undefined || cur[keys[i]] === null) cur[keys[i]] = {};
      cur = cur[keys[i]];
    }
    cur[keys[keys.length - 1]] = value;
    return clone;
  }

  function removePath(obj: any, path: string): any {
    const clone = JSON.parse(JSON.stringify(obj ?? {}));
    const keys = path.split('.');
    let cur = clone;
    for (let i = 0; i < keys.length - 1; i++) {
      if (cur[keys[i]] === undefined || cur[keys[i]] === null) return clone;
      cur = cur[keys[i]];
    }
    delete cur[keys[keys.length - 1]];
    return clone;
  }

  function removePaths(obj: any, paths: string[]): any {
    let next = obj;
    for (const path of paths) {
      next = removePath(next, path);
    }
    return next;
  }

  function updateField(path: string, value: any) {
    config = setPath(config, path, value);
    onchange();
  }

  function updateSchemaField(field: ConfigFieldDef, value: unknown) {
    const primaryPath = fieldPath(field);
    const legacyPaths = getFieldReadPaths(field).filter((path) => path !== primaryPath);
    const baseConfig = removePaths(config, legacyPaths);
    config = setPath(baseConfig, primaryPath, value);
    onchange();
  }

  function clearSchemaField(field: ConfigFieldDef) {
    config = removePaths(config, getFieldReadPaths(field));
    onchange();
  }

  let providers = $derived(Object.keys(config?.models?.providers || {}));

  let configuredChannels = $derived(Object.keys(config?.channels || {}));

  function getChannelAccounts(channelType: string): string[] {
    const ch = config?.channels?.[channelType];
    if (!ch) return [];
    if (ch.accounts) return Object.keys(ch.accounts);
    return [];
  }

  function addChannel(type: string) {
    const schema = channelSchemas[type];
    if (!schema) return;
    if (type === 'cli') {
      updateField('channels.cli', true);
    } else if (schema.hasAccounts) {
      const defaults: Record<string, any> = { account_id: 'default' };
      for (const f of schema.fields) {
        if (f.default !== undefined) {
          const parts = fieldPath(f).split('.');
          if (parts.length === 1) {
            defaults[parts[0]] = f.default;
          } else {
            let cur: any = defaults;
            for (let i = 0; i < parts.length - 1; i++) {
              if (!cur[parts[i]]) cur[parts[i]] = {};
              cur = cur[parts[i]];
            }
            cur[parts[parts.length - 1]] = f.default;
          }
        }
      }
      updateField(`channels.${type}`, { accounts: { default: defaults } });
    } else {
      const defaults: Record<string, any> = {};
      for (const f of schema.fields) {
        if (f.default !== undefined) defaults[fieldPath(f)] = f.default;
      }
      updateField(`channels.${type}`, defaults);
    }
    addChannelOpen = false;
    openSections[`channel-${type}`] = true;
  }

  function removeChannel(type: string) {
    const clone = JSON.parse(JSON.stringify(config));
    if (clone.channels) delete clone.channels[type];
    config = clone;
    onchange();
  }

  function parseList(value: any): string {
    if (Array.isArray(value)) return value.join('\n');
    return '';
  }

  function toList(text: string): string[] {
    return text.split('\n').map(s => s.trim()).filter(Boolean);
  }

  function fieldId(path: string): string {
    return `cfg-${path.replace(/[^a-zA-Z0-9_-]/g, '-')}`;
  }

  function fieldPath(field: ConfigFieldDef): string {
    return getFieldPath(field);
  }

  function fieldValue(field: ConfigFieldDef): any {
    return getFieldValue(config, field);
  }

  function displayJson(path: string, value: any, fallback: unknown): string {
    if (drafts[path] !== undefined) return drafts[path];
    if (value === undefined) {
      return JSON.stringify(fallback ?? {}, null, 2);
    }
    return JSON.stringify(value, null, 2);
  }

  function updateSchemaJson(field: ConfigFieldDef, raw: string) {
    const path = fieldPath(field);
    drafts[path] = raw;
    if (!raw.trim()) {
      delete fieldErrors[path];
      clearSchemaField(field);
      return;
    }
    try {
      const parsed = JSON.parse(raw);
      delete fieldErrors[path];
      updateSchemaField(field, parsed);
    } catch {
      fieldErrors[path] = 'Invalid JSON';
    }
  }

  let availableChannels = $derived(
    Object.entries(channelSchemas)
      .filter(([key]) => !configuredChannels.includes(key))
      .map(([key, schema]) => ({ key, label: schema.label }))
  );

  let standardSections = $derived(
    staticSections.slice(1).filter((section) => section.key !== 'peripherals' && section.group !== 'memory')
  );
</script>

<div class="config-ui">
  <!-- Models & Providers section (staticSections[0]) -->
  <div class="section">
    <button class="accordion-header" onclick={() => toggle('models')}>
      <span class="accordion-arrow" class:open={openSections['models']}>&#9654;</span>
      <span>{staticSections[0].label}</span>
    </button>
    {#if openSections['models']}
      <div class="accordion-body">
        {#each staticSections[0].fields as field}
          {@const path = fieldPath(field)}
          {@const value = fieldValue(field)}
          {@const inputId = fieldId(path)}
          {#if field.type === 'toggle'}
            <label class="toggle-field">
              <input
                id={inputId}
                type="checkbox"
                checked={!!value}
                onchange={(e) => updateSchemaField(field, e.currentTarget.checked)}
              />
              <span>{field.label}</span>
            </label>
          {:else if field.editorKind === 'object-list'}
            <div class="field">
              <div class="field-title">{field.label}</div>
              <ObjectListEditor
                value={value}
                fields={field.itemFields ?? []}
                addLabel={field.addLabel}
                emptyLabel={field.emptyLabel}
                onchange={(nextValue) => updateSchemaField(field, nextValue)}
              />
              {#if field.hint}
                <p class="hint">{field.hint}</p>
              {/if}
            </div>
          {:else if field.editorKind === 'key-value'}
            <div class="field">
              <div class="field-title">{field.label}</div>
              <KeyValueEditor
                value={value}
                fields={field.itemFields ?? []}
                addLabel={field.addLabel}
                emptyLabel={field.emptyLabel}
                onchange={(nextValue) => updateSchemaField(field, nextValue)}
              />
              {#if field.hint}
                <p class="hint">{field.hint}</p>
              {/if}
            </div>
          {:else if field.type === 'number'}
            <div class="field">
              <label for={inputId}>{field.label}</label>
              <input
                id={inputId}
                type="number"
                value={value ?? field.default ?? ''}
                step={field.step}
                min={field.min}
                max={field.max}
                oninput={(e) => updateSchemaField(field, Number(e.currentTarget.value))}
              />
              {#if field.hint}
                <p class="hint">{field.hint}</p>
              {/if}
            </div>
          {:else if field.type === 'text'}
            <div class="field">
              <label for={inputId}>{field.label}</label>
              <input
                id={inputId}
                type="text"
                value={value ?? ''}
                oninput={(e) => updateSchemaField(field, e.currentTarget.value)}
              />
              {#if field.hint}
                <p class="hint">{field.hint}</p>
              {/if}
            </div>
          {:else if field.type === 'password'}
            <div class="field">
              <label for={inputId}>{field.label}</label>
              <input
                id={inputId}
                type="password"
                value={value ?? ''}
                oninput={(e) => updateSchemaField(field, e.currentTarget.value)}
              />
              {#if field.hint}
                <p class="hint">{field.hint}</p>
              {/if}
            </div>
          {:else if field.type === 'select'}
            <div class="field">
              <label for={inputId}>{field.label}</label>
              <select id={inputId} onchange={(e) => updateSchemaField(field, e.currentTarget.value)}>
                {#each field.options ?? [] as opt}
                  <option value={opt} selected={value === opt}>{opt}</option>
                {/each}
              </select>
              {#if field.hint}
                <p class="hint">{field.hint}</p>
              {/if}
            </div>
          {:else if field.type === 'list'}
            <div class="field">
              <label for={inputId}>{field.label}</label>
              <textarea
                id={inputId}
                value={parseList(value)}
                oninput={(e) => updateSchemaField(field, toList(e.currentTarget.value))}
                rows="3"
              ></textarea>
              {#if field.hint}
                <p class="hint">{field.hint}</p>
              {/if}
            </div>
          {:else if field.type === 'textarea'}
            <div class="field">
              <label for={inputId}>{field.label}</label>
              <textarea
                id={inputId}
                rows={field.rows ?? 4}
                value={value ?? field.default ?? ''}
                oninput={(e) => updateSchemaField(field, e.currentTarget.value)}
              ></textarea>
              {#if field.hint}
                <p class="hint">{field.hint}</p>
              {/if}
            </div>
          {:else if field.type === 'json'}
            <div class="field">
              <label for={inputId}>{field.label}</label>
              <textarea
                id={inputId}
                rows={field.rows ?? 6}
                value={displayJson(path, value, field.default)}
                oninput={(e) => updateSchemaJson(field, e.currentTarget.value)}
              ></textarea>
              {#if field.hint}
                <p class="hint">{field.hint}</p>
              {/if}
              {#if fieldErrors[path]}
                <p class="error">{fieldErrors[path]}</p>
              {/if}
            </div>
          {/if}
        {/each}

        <!-- Dynamic provider settings -->
        {#each providers as provider}
          {@const apiKeyId = fieldId(`models.providers.${provider}.api_key`)}
          {@const baseUrlId = fieldId(`models.providers.${provider}.base_url`)}
          {@const userAgentId = fieldId(`models.providers.${provider}.user_agent`)}
          {@const nativeToolsId = fieldId(`models.providers.${provider}.native_tools`)}
          <div class="provider-row">
            <div class="provider-name">{provider}</div>
            <div class="field">
              <label for={apiKeyId}>API Key</label>
              <input
                id={apiKeyId}
                type="password"
                value={getPath(config, `models.providers.${provider}.api_key`) ?? ''}
                oninput={(e) => updateField(`models.providers.${provider}.api_key`, e.currentTarget.value)}
              />
            </div>
            <div class="field">
              <label for={baseUrlId}>Base URL</label>
              <input
                id={baseUrlId}
                type="text"
                value={getPath(config, `models.providers.${provider}.base_url`) ?? ''}
                oninput={(e) => updateField(`models.providers.${provider}.base_url`, e.currentTarget.value)}
              />
            </div>
            <div class="field">
              <label for={userAgentId}>User-Agent</label>
              <input
                id={userAgentId}
                type="text"
                value={getPath(config, `models.providers.${provider}.user_agent`) ?? ''}
                oninput={(e) => updateField(`models.providers.${provider}.user_agent`, e.currentTarget.value)}
              />
            </div>
            <label class="toggle-field" for={nativeToolsId}>
              <input
                id={nativeToolsId}
                type="checkbox"
                checked={getPath(config, `models.providers.${provider}.native_tools`) ?? true}
                onchange={(e) => updateField(`models.providers.${provider}.native_tools`, e.currentTarget.checked)}
              />
              <span>Native Tools</span>
            </label>
          </div>
        {/each}
      </div>
    {/if}
  </div>

  <!-- Channels heading -->
  <div class="channels-heading">{t('configEditorUi.channelsHeading')}</div>

  <!-- Configured channels -->
  {#each configuredChannels as channelType}
    {@const schema = channelSchemas[channelType]}
    {#if schema}
      <div class="section">
        <div class="accordion-header channel-header" role="button" tabindex="0" onclick={() => toggle(`channel-${channelType}`)} onkeydown={(e) => { if (e.key === 'Enter' || e.key === ' ') toggle(`channel-${channelType}`); }}>
          <div class="accordion-left">
            <span class="accordion-arrow" class:open={openSections[`channel-${channelType}`]}>&#9654;</span>
            <span>{schema.label}</span>
          </div>
          <button
            class="remove-btn"
            onclick={(e) => { e.stopPropagation(); removeChannel(channelType); }}
          >&#10005;</button>
        </div>
    {#if openSections[`channel-${channelType}`]}
          <div class="accordion-body">
            {#if channelType === 'cli'}
              <p class="cli-note">CLI channel enabled</p>
            {:else if schema.hasAccounts}
              {#each getChannelAccounts(channelType) as accountId}
                <div class="account-label">Account: {accountId}</div>
                {#each schema.fields as field}
                  {@const path = `channels.${channelType}.accounts.${accountId}.${fieldPath(field)}`}
                  {@const value = getPath(config, path)}
                  {@const inputId = fieldId(path)}
                  {#if field.type === 'toggle'}
                    <label class="toggle-field">
                      <input
                        type="checkbox"
                        checked={!!value}
                        onchange={(e) => updateField(path, e.currentTarget.checked)}
                      />
                      <span>{field.label}</span>
                    </label>
                  {:else if field.editorKind === 'object-list'}
                    <div class="field">
                      <div class="field-title">{field.label}</div>
                      <ObjectListEditor
                        value={value}
                        fields={field.itemFields ?? []}
                        addLabel={field.addLabel}
                        emptyLabel={field.emptyLabel}
                        onchange={(nextValue) => updateField(path, nextValue)}
                      />
                      {#if field.hint}
                        <p class="hint">{field.hint}</p>
                      {/if}
                    </div>
                  {:else if field.editorKind === 'key-value'}
                    <div class="field">
                      <div class="field-title">{field.label}</div>
                      <KeyValueEditor
                        value={value}
                        fields={field.itemFields ?? []}
                        addLabel={field.addLabel}
                        emptyLabel={field.emptyLabel}
                        onchange={(nextValue) => updateField(path, nextValue)}
                      />
                      {#if field.hint}
                        <p class="hint">{field.hint}</p>
                      {/if}
                    </div>
                  {:else if field.type === 'number'}
                    <div class="field">
                      <label for={inputId}>{field.label}</label>
                      <input
                        id={inputId}
                        type="number"
                        value={value ?? field.default ?? ''}
                        step={field.step}
                        min={field.min}
                        max={field.max}
                        oninput={(e) => updateField(path, Number(e.currentTarget.value))}
                      />
                      {#if field.hint}
                        <p class="hint">{field.hint}</p>
                      {/if}
                    </div>
                  {:else if field.type === 'text'}
                    <div class="field">
                      <label for={inputId}>{field.label}</label>
                      <input
                        id={inputId}
                        type="text"
                        value={value ?? ''}
                        oninput={(e) => updateField(path, e.currentTarget.value)}
                      />
                      {#if field.hint}
                        <p class="hint">{field.hint}</p>
                      {/if}
                    </div>
                  {:else if field.type === 'password'}
                    <div class="field">
                      <label for={inputId}>{field.label}</label>
                      <input
                        id={inputId}
                        type="password"
                        value={value ?? ''}
                        oninput={(e) => updateField(path, e.currentTarget.value)}
                      />
                      {#if field.hint}
                        <p class="hint">{field.hint}</p>
                      {/if}
                    </div>
                  {:else if field.type === 'select'}
                    <div class="field">
                      <label for={inputId}>{field.label}</label>
                      <select id={inputId} onchange={(e) => updateField(path, e.currentTarget.value)}>
                        {#each field.options ?? [] as opt}
                          <option value={opt} selected={value === opt}>{opt}</option>
                        {/each}
                      </select>
                      {#if field.hint}
                        <p class="hint">{field.hint}</p>
                      {/if}
                    </div>
                  {:else if field.type === 'list'}
                    <div class="field">
                      <label for={inputId}>{field.label}</label>
                      <textarea
                        id={inputId}
                        value={parseList(value)}
                        oninput={(e) => updateField(path, toList(e.currentTarget.value))}
                        rows="3"
                      ></textarea>
                      {#if field.hint}
                        <p class="hint">{field.hint}</p>
                      {/if}
                    </div>
                  {/if}
                {/each}
              {/each}
            {:else}
              {#each schema.fields as field}
                {@const path = `channels.${channelType}.${fieldPath(field)}`}
                {@const value = getPath(config, path)}
                {@const inputId = fieldId(path)}
                {#if field.type === 'toggle'}
                  <label class="toggle-field">
                    <input
                      type="checkbox"
                      checked={!!value}
                      onchange={(e) => updateField(path, e.currentTarget.checked)}
                    />
                    <span>{field.label}</span>
                  </label>
                {:else if field.editorKind === 'object-list'}
                  <div class="field">
                    <div class="field-title">{field.label}</div>
                    <ObjectListEditor
                      value={value}
                      fields={field.itemFields ?? []}
                      addLabel={field.addLabel}
                      emptyLabel={field.emptyLabel}
                      onchange={(nextValue) => updateField(path, nextValue)}
                    />
                    {#if field.hint}
                      <p class="hint">{field.hint}</p>
                    {/if}
                  </div>
                {:else if field.editorKind === 'key-value'}
                  <div class="field">
                    <div class="field-title">{field.label}</div>
                    <KeyValueEditor
                      value={value}
                      fields={field.itemFields ?? []}
                      addLabel={field.addLabel}
                      emptyLabel={field.emptyLabel}
                      onchange={(nextValue) => updateField(path, nextValue)}
                    />
                    {#if field.hint}
                      <p class="hint">{field.hint}</p>
                    {/if}
                  </div>
                {:else if field.type === 'number'}
                  <div class="field">
                    <label for={inputId}>{field.label}</label>
                    <input
                      id={inputId}
                      type="number"
                      value={value ?? field.default ?? ''}
                      step={field.step}
                      min={field.min}
                      max={field.max}
                      oninput={(e) => updateField(path, Number(e.currentTarget.value))}
                    />
                    {#if field.hint}
                      <p class="hint">{field.hint}</p>
                    {/if}
                  </div>
                {:else if field.type === 'text'}
                  <div class="field">
                    <label for={inputId}>{field.label}</label>
                    <input
                      id={inputId}
                      type="text"
                      value={value ?? ''}
                      oninput={(e) => updateField(path, e.currentTarget.value)}
                    />
                    {#if field.hint}
                      <p class="hint">{field.hint}</p>
                    {/if}
                  </div>
                {:else if field.type === 'password'}
                  <div class="field">
                    <label for={inputId}>{field.label}</label>
                    <input
                      id={inputId}
                      type="password"
                      value={value ?? ''}
                      oninput={(e) => updateField(path, e.currentTarget.value)}
                    />
                    {#if field.hint}
                      <p class="hint">{field.hint}</p>
                    {/if}
                  </div>
                {:else if field.type === 'select'}
                  <div class="field">
                    <label for={inputId}>{field.label}</label>
                    <select id={inputId} onchange={(e) => updateField(path, e.currentTarget.value)}>
                      {#each field.options ?? [] as opt}
                        <option value={opt} selected={value === opt}>{opt}</option>
                      {/each}
                    </select>
                    {#if field.hint}
                      <p class="hint">{field.hint}</p>
                    {/if}
                  </div>
                {:else if field.type === 'list'}
                  <div class="field">
                    <label for={inputId}>{field.label}</label>
                    <textarea
                      id={inputId}
                      value={parseList(value)}
                      oninput={(e) => updateField(path, toList(e.currentTarget.value))}
                      rows="3"
                    ></textarea>
                    {#if field.hint}
                      <p class="hint">{field.hint}</p>
                    {/if}
                  </div>
                {/if}
              {/each}
            {/if}
          </div>
        {/if}
      </div>
    {/if}
  {/each}

  <!-- Add Channel button + dropdown -->
  <div class="add-channel" class:open={addChannelOpen}>
    <button class="add-channel-btn" onclick={() => addChannelOpen = !addChannelOpen}>
      + {t('configEditorUi.addChannel')}
    </button>
    {#if addChannelOpen}
      <div class="add-channel-dropdown">
        {#each availableChannels as ch}
          <button onclick={() => addChannel(ch.key)}>{ch.label}</button>
        {/each}
        {#if availableChannels.length === 0}
          <button disabled>{t('configEditorUi.allChannelsConfigured')}</button>
        {/if}
      </div>
    {/if}
  </div>

  <MemoryConfigModule bind:config={config} onchange={onchange} />
  <PeripheralsConfigModule bind:config={config} onchange={onchange} />

  {#each standardSections as section}
    <div class="section">
      <button class="accordion-header" onclick={() => toggle(section.key)}>
        <span class="accordion-arrow" class:open={openSections[section.key]}>&#9654;</span>
        <span>{section.label}</span>
      </button>
      {#if openSections[section.key]}
        <div class="accordion-body">
          {#each section.fields as field}
            {@const path = fieldPath(field)}
            {@const value = fieldValue(field)}
            {@const inputId = fieldId(path)}
            {#if field.type === 'toggle'}
              <label class="toggle-field">
                <input
                  type="checkbox"
                  checked={!!value}
                  onchange={(e) => updateSchemaField(field, e.currentTarget.checked)}
                />
                <span>{field.label}</span>
              </label>
            {:else if field.editorKind === 'object-list'}
              <div class="field">
                <div class="field-title">{field.label}</div>
                <ObjectListEditor
                  value={value}
                  fields={field.itemFields ?? []}
                  addLabel={field.addLabel}
                  emptyLabel={field.emptyLabel}
                  onchange={(nextValue) => updateSchemaField(field, nextValue)}
                />
                {#if field.hint}
                  <p class="hint">{field.hint}</p>
                {/if}
              </div>
            {:else if field.editorKind === 'key-value'}
              <div class="field">
                <div class="field-title">{field.label}</div>
                <KeyValueEditor
                  value={value}
                  fields={field.itemFields ?? []}
                  addLabel={field.addLabel}
                  emptyLabel={field.emptyLabel}
                  onchange={(nextValue) => updateSchemaField(field, nextValue)}
                />
                {#if field.hint}
                  <p class="hint">{field.hint}</p>
                {/if}
              </div>
            {:else if field.type === 'number'}
              <div class="field">
                <label for={inputId}>{field.label}</label>
                <input
                  id={inputId}
                  type="number"
                  value={value ?? field.default ?? ''}
                  step={field.step}
                  min={field.min}
                  max={field.max}
                  oninput={(e) => updateSchemaField(field, Number(e.currentTarget.value))}
                />
                {#if field.hint}
                  <p class="hint">{field.hint}</p>
                {/if}
              </div>
            {:else if field.type === 'text'}
              <div class="field">
                <label for={inputId}>{field.label}</label>
                <input
                  id={inputId}
                  type="text"
                  value={value ?? ''}
                  oninput={(e) => updateSchemaField(field, e.currentTarget.value)}
                />
                {#if field.hint}
                  <p class="hint">{field.hint}</p>
                {/if}
              </div>
            {:else if field.type === 'password'}
              <div class="field">
                <label for={inputId}>{field.label}</label>
                <input
                  id={inputId}
                  type="password"
                  value={value ?? ''}
                  oninput={(e) => updateSchemaField(field, e.currentTarget.value)}
                />
                {#if field.hint}
                  <p class="hint">{field.hint}</p>
                {/if}
              </div>
            {:else if field.type === 'select'}
              <div class="field">
                <label for={inputId}>{field.label}</label>
                <select id={inputId} onchange={(e) => updateSchemaField(field, e.currentTarget.value)}>
                  {#each field.options ?? [] as opt}
                    <option value={opt} selected={value === opt}>{opt}</option>
                  {/each}
                </select>
                {#if field.hint}
                  <p class="hint">{field.hint}</p>
                {/if}
              </div>
            {:else if field.type === 'list'}
              <div class="field">
                <label for={inputId}>{field.label}</label>
                <textarea
                  id={inputId}
                  value={parseList(value)}
                  oninput={(e) => updateSchemaField(field, toList(e.currentTarget.value))}
                  rows="3"
                ></textarea>
                {#if field.hint}
                  <p class="hint">{field.hint}</p>
                {/if}
              </div>
            {:else if field.type === 'textarea'}
              <div class="field">
                <label for={inputId}>{field.label}</label>
                <textarea
                  id={inputId}
                  rows={field.rows ?? 4}
                  value={value ?? field.default ?? ''}
                  oninput={(e) => updateSchemaField(field, e.currentTarget.value)}
                ></textarea>
                {#if field.hint}
                  <p class="hint">{field.hint}</p>
                {/if}
              </div>
            {:else if field.type === 'json'}
              <div class="field">
                <label for={inputId}>{field.label}</label>
                <textarea
                  id={inputId}
                  rows={field.rows ?? 6}
                  value={displayJson(path, value, field.default)}
                  oninput={(e) => updateSchemaJson(field, e.currentTarget.value)}
                ></textarea>
                {#if field.hint}
                  <p class="hint">{field.hint}</p>
                {/if}
                {#if fieldErrors[path]}
                  <p class="error">{fieldErrors[path]}</p>
                {/if}
              </div>
            {/if}
          {/each}
        </div>
      {/if}
    </div>
  {/each}
</div>

<style>
  .config-ui {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-md);
  }

  .section {
    border: 1px solid rgba(141, 154, 178, 0.18);
    border-radius: var(--radius-lg);
    background: linear-gradient(180deg, rgba(255, 255, 255, 0.82), rgba(244, 248, 255, 0.72));
    box-shadow: var(--shadow-sm);
    backdrop-filter: blur(8px);
  }

  .accordion-header {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    width: 100%;
    padding: 1rem 1.1rem;
    background: none;
    border: none;
    cursor: pointer;
    color: var(--slate-900);
    font-family: var(--font-display);
    font-size: var(--text-sm);
    font-weight: 600;
    letter-spacing: -0.01em;
    transition:
      color var(--transition-fast),
      background-color var(--transition-fast);
  }
  .accordion-header:hover {
    background: rgba(34, 211, 238, 0.05);
  }

  .accordion-arrow {
    font-size: 0.625rem;
    transition: transform var(--transition-fast);
    color: var(--cyan-600);
  }
  .accordion-arrow.open {
    transform: rotate(90deg);
  }

  .accordion-body {
    padding: 0 1.1rem 1.1rem;
    border-top: 1px solid rgba(141, 154, 178, 0.16);
  }

  .field {
    margin-bottom: 1rem;
  }
  .field label,
  .field-title {
    display: block;
    font-size: 0.8125rem;
    font-weight: 600;
    color: var(--slate-700);
    margin-bottom: 0.4rem;
    letter-spacing: -0.01em;
  }
  .field input[type="text"],
  .field input[type="number"],
  .field input[type="password"],
  .field select,
  .field textarea {
    width: 100%;
    padding: 0.65rem 0.8rem;
    background: rgba(255, 255, 255, 0.8);
    border: 1px solid rgba(141, 154, 178, 0.22);
    border-radius: var(--radius-md);
    color: var(--fg);
    font-size: 0.875rem;
    font-family: var(--font-sans);
    outline: none;
    transition:
      border-color var(--transition-fast),
      box-shadow var(--transition-fast),
      background-color var(--transition-fast),
      color var(--transition-fast);
    box-shadow: inset 0 1px 2px rgba(15, 23, 42, 0.04);
    box-sizing: border-box;
  }
  .field input:focus,
  .field select:focus,
  .field textarea:focus {
    border-color: rgba(34, 211, 238, 0.24);
    box-shadow: var(--focus-ring);
  }
  .field textarea {
    resize: vertical;
    min-height: 60px;
    line-height: 1.5;
  }
  .field select {
    cursor: pointer;
  }

  .toggle-field {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    cursor: pointer;
    margin-bottom: 0.9rem;
    padding: 0.75rem 0.85rem;
    border-radius: var(--radius-md);
    background: rgba(255, 255, 255, 0.56);
    border: 1px solid rgba(141, 154, 178, 0.16);
  }
  .toggle-field input[type="checkbox"] {
    width: 1.25rem;
    height: 1.25rem;
    accent-color: var(--accent);
    cursor: pointer;
  }
  .toggle-field span {
    font-size: 0.875rem;
    color: var(--slate-800);
    letter-spacing: -0.01em;
  }

  .hint {
    font-size: 0.75rem;
    color: var(--slate-500);
    margin-top: 0.25rem;
    font-family: var(--font-sans);
    line-height: 1.45;
  }

  .error {
    margin-top: 0.25rem;
    font-size: 0.75rem;
    color: var(--red-600);
    line-height: 1.45;
  }

  .channel-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    width: 100%;
  }
  .channel-header .accordion-left {
    display: flex;
    align-items: center;
    gap: 0.75rem;
  }

  .remove-btn {
    padding: 0.45rem 0.65rem;
    background: rgba(244, 63, 94, 0.08);
    border: 1px solid rgba(244, 63, 94, 0.18);
    border-radius: var(--radius-md);
    color: var(--red-600);
    font-size: 0.75rem;
    cursor: pointer;
    opacity: 0.75;
    transition:
      opacity var(--transition-fast),
      box-shadow var(--transition-fast),
      background-color var(--transition-fast),
      border-color var(--transition-fast),
      color var(--transition-fast);
  }
  .remove-btn:hover {
    opacity: 1;
    box-shadow: 0 10px 24px rgba(225, 29, 72, 0.12);
  }

  .channels-heading {
    font-family: var(--font-display);
    font-size: var(--text-lg);
    font-weight: 600;
    color: var(--slate-900);
    letter-spacing: -0.02em;
    margin: 0.5rem 0 0;
  }

  .add-channel {
    position: relative;
    margin-top: 0.5rem;
  }
  .add-channel.open {
    margin-bottom: 0.75rem;
  }
  .add-channel-btn {
    padding: 0.8rem 1rem;
    background: rgba(34, 211, 238, 0.08);
    color: var(--cyan-600);
    border: 1px dashed rgba(34, 211, 238, 0.26);
    border-radius: var(--radius-md);
    cursor: pointer;
    font-size: var(--text-sm);
    font-weight: 600;
    transition:
      background-color var(--transition-fast),
      border-color var(--transition-fast),
      color var(--transition-fast);
    width: 100%;
  }
  .add-channel-btn:hover {
    background: rgba(34, 211, 238, 0.12);
    border-color: rgba(34, 211, 238, 0.32);
  }

  .add-channel-dropdown {
    position: relative;
    z-index: 10;
    background: rgba(255, 255, 255, 0.88);
    border: 1px solid rgba(34, 211, 238, 0.22);
    border-radius: var(--radius-md);
    max-height: 300px;
    overflow-y: auto;
    margin-top: 0.25rem;
    box-shadow: var(--shadow-md);
    backdrop-filter: blur(8px);
  }
  .add-channel-dropdown button {
    display: block;
    width: 100%;
    padding: 0.7rem 1rem;
    background: none;
    border: none;
    border-bottom: 1px solid rgba(141, 154, 178, 0.16);
    color: var(--slate-700);
    font-size: var(--text-sm);
    text-align: left;
    cursor: pointer;
    font-family: var(--font-sans);
    transition:
      color var(--transition-fast),
      background-color var(--transition-fast);
  }
  .add-channel-dropdown button:hover {
    background: rgba(34, 211, 238, 0.08);
    color: var(--slate-900);
  }
  .add-channel-dropdown button:last-child {
    border-bottom: none;
  }

  .account-label {
    font-size: 0.75rem;
    color: var(--cyan-600);
    letter-spacing: 0.05em;
    margin: 0.75rem 0 0.5rem;
    padding-bottom: 0.25rem;
    border-bottom: 1px dashed rgba(141, 154, 178, 0.18);
  }

  .provider-row {
    margin-bottom: 0.75rem;
  }
  .provider-name {
    font-size: 0.75rem;
    color: var(--slate-700);
    letter-spacing: 0.04em;
    margin-bottom: 0.35rem;
    font-weight: 600;
  }

  .cli-note {
    font-size: var(--text-sm);
    color: var(--slate-600);
    padding: 0.5rem 0;
  }

  @media (max-width: 760px) {
    .accordion-header {
      padding: 0.75rem;
    }

    .accordion-body {
      padding: 0 0.75rem 0.75rem;
    }

    .channel-header {
      flex-direction: column;
      align-items: flex-start;
      gap: 0.5rem;
    }

    .field input[type="text"],
    .field input[type="number"],
    .field input[type="password"],
    .field select,
    .field textarea {
      font-size: 0.8125rem;
    }
  }
</style>
