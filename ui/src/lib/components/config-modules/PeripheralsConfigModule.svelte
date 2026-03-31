<script lang="ts">
  import { t } from "$lib/i18n/index.svelte";
  import ObjectListEditor from "../config-editors/ObjectListEditor.svelte";
  import {
    getFieldPath,
    getFieldReadPaths,
    getFieldValue,
    type ConfigFieldDef,
  } from "../configSchemaContract";
  import { getStaticSections } from "../configSchemas";

  type ConfigObject = Record<string, unknown>;

  let {
    config = $bindable({}),
    onchange = () => {},
  }: {
    config?: ConfigObject;
    onchange?: () => void;
  } = $props();

  let open = $state(false);
  let staticSections = $derived(getStaticSections());

  const section = $derived(staticSections.find((entry) => entry.key === "peripherals") ?? null);
  const boardCount = $derived(
    Array.isArray((config.peripherals as Record<string, unknown> | undefined)?.boards)
      ? ((config.peripherals as Record<string, unknown>).boards as unknown[]).length
      : 0,
  );

  function isRecord(input: unknown): input is Record<string, unknown> {
    return typeof input === "object" && input !== null && !Array.isArray(input);
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

  function fieldPath(field: ConfigFieldDef): string {
    return getFieldPath(field);
  }

  function fieldValue(field: ConfigFieldDef): unknown {
    return getFieldValue(config, field);
  }

  function fieldId(path: string): string {
    return `cfg-module-${path.replace(/[^a-zA-Z0-9_-]/g, "-")}`;
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
</script>

{#if section}
  <div class="section">
    <button class="accordion-header" onclick={() => (open = !open)}>
      <span class="accordion-arrow" class:open={open}>&#9654;</span>
      <span>{section.label}</span>
      <span class="module-pill">{boardCount} {t("configEditorUi.peripheralsBoardsLabel")}</span>
    </button>

    {#if open}
      <div class="accordion-body">
        <div class="module-intro">
          <div>
            <h3>{t("configEditorUi.peripheralsTitle")}</h3>
            <p>{t("configEditorUi.peripheralsDesc")}</p>
          </div>
        </div>

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
          {:else if field.type === "text"}
            <div class="field">
              <label for={inputId}>{field.label}</label>
              <input
                id={inputId}
                type="text"
                value={String(value ?? "")}
                oninput={(e) => updateSchemaField(field, e.currentTarget.value)}
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
          {/if}
        {/each}
      </div>
    {/if}
  </div>
{/if}

<style>
  .section {
    border: 1px solid rgba(141, 154, 178, 0.18);
    border-radius: var(--radius-lg);
    background: linear-gradient(180deg, rgba(255, 255, 255, 0.82), rgba(244, 248, 255, 0.72));
    box-shadow: var(--shadow-sm);
    backdrop-filter: blur(16px);
  }

  .accordion-header {
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

  .accordion-header:hover {
    background: rgba(34, 211, 238, 0.05);
  }

  .accordion-arrow {
    font-size: 0.625rem;
    color: var(--cyan-600);
    transition: transform var(--transition-fast);
  }

  .accordion-arrow.open {
    transform: rotate(90deg);
  }

  .accordion-body {
    padding: 0 1.1rem 1.1rem;
    border-top: 1px solid rgba(141, 154, 178, 0.16);
  }

  .module-pill {
    margin-left: auto;
    padding: 0.28rem 0.65rem;
    border-radius: 999px;
    border: 1px solid rgba(34, 211, 238, 0.16);
    background: rgba(34, 211, 238, 0.08);
    color: var(--cyan-700);
    font-size: 0.75rem;
    font-family: var(--font-mono);
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
  .hint {
    margin: 0.35rem 0 0;
    color: var(--slate-500);
    font-size: 0.875rem;
    line-height: 1.5;
  }

  .field {
    margin-bottom: 1rem;
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
    padding: 0.78rem 0.85rem;
    border-radius: var(--radius-md);
    border: 1px solid rgba(141, 154, 178, 0.2);
    background: rgba(255, 255, 255, 0.84);
    color: var(--fg);
    font-family: var(--font-sans);
    font-size: 0.9rem;
    box-sizing: border-box;
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
    margin-bottom: 1rem;
    color: var(--slate-800);
    font-size: 0.92rem;
    font-weight: 600;
  }

  .toggle-field input {
    width: 1rem;
    height: 1rem;
  }
</style>
