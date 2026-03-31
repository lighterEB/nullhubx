<script lang="ts">
  import { t } from "$lib/i18n/index.svelte";
  import ObjectListEditor from "../config-editors/ObjectListEditor.svelte";
  import {
    getFieldPath,
    getFieldReadPaths,
    getFieldValue,
    type ConfigFieldDef,
  } from "../configSchemaContract";
  import { getMemorySections } from "../configSchemas";

  type ConfigObject = Record<string, unknown>;

  let {
    config = $bindable({}),
    onchange = () => {},
  }: {
    config?: ConfigObject;
    onchange?: () => void;
  } = $props();

  let open = $state(false);
  let openSections = $state<Record<string, boolean>>({});
  let draft = $state("");
  let parseError = $state("");
  let suppressNextSync = $state(false);
  let memorySections = $derived(getMemorySections());

  function isRecord(input: unknown): input is ConfigObject {
    return typeof input === "object" && input !== null && !Array.isArray(input);
  }

  const memoryConfig = $derived(isRecord(config.memory) ? config.memory : {});
  const rawMemory = $derived(JSON.stringify(memoryConfig, null, 2));
  const configuredGroups = $derived(Object.keys(memoryConfig).sort());
  const coveredFieldCount = $derived(memorySections.reduce((count, section) => count + section.fields.length, 0));

  $effect(() => {
    if (suppressNextSync) {
      suppressNextSync = false;
      return;
    }

    draft = rawMemory;
    parseError = "";
  });

  function toggleSection(key: string) {
    openSections[key] = !(openSections[key] ?? true);
  }

  function isSectionOpen(key: string): boolean {
    return openSections[key] ?? true;
  }

  function cloneConfig(): ConfigObject {
    return JSON.parse(JSON.stringify(config ?? {})) as ConfigObject;
  }

  function setPath(obj: ConfigObject, path: string, value: unknown): ConfigObject {
    const clone = JSON.parse(JSON.stringify(obj ?? {})) as ConfigObject;
    const keys = path.split(".");
    let current: Record<string, unknown> = clone;

    for (let index = 0; index < keys.length - 1; index += 1) {
      const key = keys[index];
      if (!isRecord(current[key])) {
        current[key] = {};
      }
      current = current[key] as Record<string, unknown>;
    }

    current[keys[keys.length - 1]] = value;
    return clone;
  }

  function removePath(obj: ConfigObject, path: string): ConfigObject {
    const clone = JSON.parse(JSON.stringify(obj ?? {})) as ConfigObject;
    const keys = path.split(".");
    let current: Record<string, unknown> = clone;

    for (let index = 0; index < keys.length - 1; index += 1) {
      const key = keys[index];
      if (!isRecord(current[key])) {
        return clone;
      }
      current = current[key] as Record<string, unknown>;
    }

    delete current[keys[keys.length - 1]];
    return clone;
  }

  function removePaths(obj: ConfigObject, paths: string[]): ConfigObject {
    let next = obj;
    for (const path of paths) {
      next = removePath(next, path);
    }
    return next;
  }

  function updateMemory(nextValue: ConfigObject | null) {
    const nextConfig = cloneConfig();
    if (nextValue && Object.keys(nextValue).length > 0) {
      nextConfig.memory = nextValue;
    } else {
      delete nextConfig.memory;
    }

    config = nextConfig;
    onchange();
  }

  function fieldPath(field: ConfigFieldDef): string {
    return getFieldPath(field);
  }

  function fieldValue(field: ConfigFieldDef): unknown {
    return getFieldValue(config, field);
  }

  function fieldId(path: string): string {
    return `cfg-memory-${path.replace(/[^a-zA-Z0-9_-]/g, "-")}`;
  }

  function parseList(value: unknown): string {
    return Array.isArray(value) ? value.map(String).join("\n") : "";
  }

  function toList(value: string): string[] {
    return value
      .split("\n")
      .map((item) => item.trim())
      .filter(Boolean);
  }

  function updateSchemaField(field: ConfigFieldDef, value: unknown) {
    const primaryPath = fieldPath(field);
    const legacyPaths = getFieldReadPaths(field).filter((path) => path !== primaryPath);
    const baseConfig = removePaths(config, legacyPaths);
    config = setPath(baseConfig, primaryPath, value);
    onchange();
  }

  function updateDraft(nextRaw: string) {
    draft = nextRaw;

    if (!nextRaw.trim()) {
      parseError = "";
      suppressNextSync = true;
      updateMemory(null);
      return;
    }

    try {
      const parsed = JSON.parse(nextRaw);
      if (!isRecord(parsed)) {
        parseError = t("configEditorUi.memoryObjectError");
        return;
      }

      parseError = "";
      suppressNextSync = true;
      updateMemory(parsed);
    } catch {
      parseError = t("configEditor.invalidJson");
    }
  }
</script>

<div class="section">
  <button class="accordion-header" onclick={() => (open = !open)}>
    <span class="accordion-arrow" class:open={open}>&#9654;</span>
    <span>{t("configEditorUi.memoryTitle")}</span>
    <span class="module-pill">{configuredGroups.length}</span>
  </button>

  {#if open}
    <div class="accordion-body">
      <div class="module-intro">
        <div>
          <h3>{t("configEditorUi.memoryTitle")}</h3>
          <p>{t("configEditorUi.memoryDesc")}</p>
        </div>
      </div>

      <div class="status-grid">
        <div class="status-card">
          <div class="status-label">{t("configEditorUi.memoryConfiguredGroups")}</div>
          {#if configuredGroups.length > 0}
            <div class="chip-row">
              {#each configuredGroups as group}
                <span class="status-chip">{group}</span>
              {/each}
            </div>
          {:else}
            <p class="status-copy">{t("configEditorUi.memoryNoGroups")}</p>
          {/if}
        </div>

        <div class="status-card">
          <div class="status-label">{t("configEditorUi.memoryStructuredCoverage")}</div>
          <p class="status-copy">{coveredFieldCount} {t("configEditorUi.memoryStructuredFields")}</p>
        </div>

        <div class="status-card">
          <div class="status-label">{t("configEditorUi.memoryRawFallbackTitle")}</div>
          <p class="status-copy">{t("configEditorUi.memoryRawFallbackDesc")}</p>
        </div>
      </div>

      <div class="domain-grid">
        {#each memorySections as section}
          <section class="domain-card">
            <button class="domain-header" onclick={() => toggleSection(section.key)}>
              <span class="domain-arrow" class:open={isSectionOpen(section.key)}>&#9654;</span>
              <span>{section.label}</span>
              <span class="domain-count">{section.fields.length}</span>
            </button>

            {#if isSectionOpen(section.key)}
              <div class="domain-body">
                {#each section.fields as field}
                  {@const path = fieldPath(field)}
                  {@const value = fieldValue(field)}
                  {@const inputId = fieldId(path)}
                  {#if field.type === "toggle"}
                    <label class="toggle-field">
                      <input
                        id={inputId}
                        type="checkbox"
                        checked={!!value}
                        onchange={(e) => updateSchemaField(field, e.currentTarget.checked)}
                      />
                      <span>{field.label}</span>
                    </label>
                  {:else if field.editorKind === "object-list"}
                    <div class="field field-span">
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
                  {:else if field.type === "number"}
                    <div class="field">
                      <label for={inputId}>{field.label}</label>
                      <input
                        id={inputId}
                        type="number"
                        value={String(value ?? field.default ?? "")}
                        min={field.min}
                        max={field.max}
                        step={field.step}
                        oninput={(e) => updateSchemaField(field, Number(e.currentTarget.value))}
                      />
                      {#if field.hint}
                        <p class="hint">{field.hint}</p>
                      {/if}
                    </div>
                  {:else if field.type === "password"}
                    <div class="field">
                      <label for={inputId}>{field.label}</label>
                      <input
                        id={inputId}
                        type="password"
                        value={String(value ?? "")}
                        oninput={(e) => updateSchemaField(field, e.currentTarget.value)}
                      />
                      {#if field.hint}
                        <p class="hint">{field.hint}</p>
                      {/if}
                    </div>
                  {:else if field.type === "select"}
                    <div class="field">
                      <label for={inputId}>{field.label}</label>
                      <select id={inputId} onchange={(e) => updateSchemaField(field, e.currentTarget.value)}>
                        {#each field.options ?? [] as option}
                          <option value={option} selected={value === option}>{field.optionLabels?.[option] ?? option}</option>
                        {/each}
                      </select>
                      {#if field.hint}
                        <p class="hint">{field.hint}</p>
                      {/if}
                    </div>
                  {:else if field.type === "list"}
                    <div class="field">
                      <label for={inputId}>{field.label}</label>
                      <textarea
                        id={inputId}
                        rows="3"
                        value={parseList(value)}
                        oninput={(e) => updateSchemaField(field, toList(e.currentTarget.value))}
                      ></textarea>
                      {#if field.hint}
                        <p class="hint">{field.hint}</p>
                      {/if}
                    </div>
                  {:else}
                    <div class="field">
                      <label for={inputId}>{field.label}</label>
                      <input
                        id={inputId}
                        type="text"
                        value={String(value ?? field.default ?? "")}
                        oninput={(e) => updateSchemaField(field, e.currentTarget.value)}
                      />
                      {#if field.hint}
                        <p class="hint">{field.hint}</p>
                      {/if}
                    </div>
                  {/if}
                {/each}
              </div>
            {/if}
          </section>
        {/each}
      </div>

      <div class="field raw-fallback">
        <label for="cfg-memory-raw">{t("configEditorUi.memoryRawLabel")}</label>
        <textarea
          id="cfg-memory-raw"
          rows="18"
          value={draft}
          oninput={(e) => updateDraft(e.currentTarget.value)}
        ></textarea>
        <p class="hint">{t("configEditorUi.memoryRawHint")}</p>
        {#if parseError}
          <p class="error">{parseError}</p>
        {/if}
      </div>
    </div>
  {/if}
</div>

<style>
  .section {
    border: 1px solid rgba(141, 154, 178, 0.18);
    border-radius: var(--radius-lg);
    background: linear-gradient(180deg, rgba(255, 255, 255, 0.82), rgba(244, 248, 255, 0.72));
    box-shadow: var(--shadow-sm);
    backdrop-filter: blur(16px);
  }

  .accordion-header,
  .domain-header {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    width: 100%;
    padding: 1rem 1.1rem;
    border: none;
    background: none;
    color: var(--slate-900);
    cursor: pointer;
    font-family: var(--font-display);
    font-size: var(--text-sm);
    font-weight: 600;
    letter-spacing: -0.01em;
    transition: all var(--transition-fast);
  }

  .accordion-header:hover,
  .domain-header:hover {
    background: rgba(34, 211, 238, 0.05);
  }

  .accordion-arrow,
  .domain-arrow {
    font-size: 0.625rem;
    color: var(--cyan-600);
    transition: transform var(--transition-fast);
  }

  .accordion-arrow.open,
  .domain-arrow.open {
    transform: rotate(90deg);
  }

  .accordion-body {
    padding: 0 1.1rem 1.1rem;
    border-top: 1px solid rgba(141, 154, 178, 0.16);
  }

  .module-pill,
  .domain-count {
    margin-left: auto;
    min-width: 2rem;
    padding: 0.28rem 0.65rem;
    border-radius: 999px;
    font-size: 0.75rem;
    font-family: var(--font-mono);
    text-align: center;
  }

  .module-pill {
    border: 1px solid rgba(139, 92, 246, 0.16);
    background: rgba(139, 92, 246, 0.08);
    color: var(--violet-700);
  }

  .domain-count {
    border: 1px solid rgba(34, 211, 238, 0.16);
    background: rgba(34, 211, 238, 0.08);
    color: var(--cyan-700);
  }

  .module-intro {
    margin-bottom: 1rem;
    padding: 1rem 1.1rem;
    border: 1px solid rgba(141, 154, 178, 0.16);
    border-radius: var(--radius-md);
    background: rgba(255, 255, 255, 0.58);
  }

  .module-intro h3 {
    margin: 0 0 0.35rem;
    font-size: 1rem;
    color: var(--slate-900);
  }

  .module-intro p,
  .status-copy,
  .hint {
    margin: 0.35rem 0 0;
    color: var(--slate-500);
    font-size: 0.875rem;
    line-height: 1.5;
  }

  .status-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
    gap: 0.85rem;
    margin-bottom: 1rem;
  }

  .status-card,
  .domain-card {
    border: 1px solid rgba(141, 154, 178, 0.16);
    border-radius: var(--radius-md);
    background: rgba(255, 255, 255, 0.6);
  }

  .status-card {
    padding: 1rem 1.05rem;
  }

  .status-label {
    color: var(--slate-800);
    font-size: 0.82rem;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.08em;
  }

  .chip-row {
    display: flex;
    flex-wrap: wrap;
    gap: 0.45rem;
    margin-top: 0.75rem;
  }

  .status-chip {
    padding: 0.32rem 0.6rem;
    border-radius: 999px;
    border: 1px solid rgba(34, 211, 238, 0.16);
    background: rgba(34, 211, 238, 0.08);
    color: var(--cyan-700);
    font-size: 0.75rem;
    font-family: var(--font-mono);
  }

  .domain-grid {
    display: flex;
    flex-direction: column;
    gap: 0.85rem;
    margin-bottom: 1rem;
  }

  .domain-body {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(240px, 1fr));
    gap: 0.9rem 1rem;
    padding: 0 1.1rem 1.1rem;
    border-top: 1px solid rgba(141, 154, 178, 0.12);
  }

  .field {
    min-width: 0;
  }

  .field-span {
    grid-column: 1 / -1;
  }

  .field label,
  .field-title {
    display: block;
    margin-bottom: 0.45rem;
    font-size: 0.875rem;
    font-weight: 600;
    color: var(--slate-700);
  }

  .field input,
  .field select,
  .field textarea {
    width: 100%;
    padding: 0.82rem 0.9rem;
    border-radius: var(--radius-md);
    border: 1px solid rgba(141, 154, 178, 0.2);
    background: rgba(248, 250, 252, 0.94);
    color: var(--fg);
    font-family: var(--font-sans);
    font-size: 0.88rem;
    box-sizing: border-box;
  }

  .field textarea {
    resize: vertical;
  }

  .raw-fallback textarea {
    font-family: var(--font-mono);
    font-size: 0.82rem;
    line-height: 1.55;
  }

  .field input:focus,
  .field select:focus,
  .field textarea:focus {
    outline: none;
    box-shadow: var(--focus-ring);
    border-color: rgba(34, 211, 238, 0.24);
  }

  .toggle-field {
    display: inline-flex;
    align-items: center;
    gap: 0.65rem;
    color: var(--slate-800);
    font-size: 0.92rem;
    font-weight: 600;
    min-height: 42px;
  }

  .toggle-field input {
    width: 1rem;
    height: 1rem;
  }

  .error {
    margin: 0.45rem 0 0;
    color: var(--rose-600);
    font-size: 0.85rem;
  }
</style>
