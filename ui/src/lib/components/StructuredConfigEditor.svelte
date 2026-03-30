<script lang="ts">
  import { getFieldPath, getFieldValue } from "./configSchemaContract";
  import {
    getComponentConfigSchema,
    type GenericFieldDef,
  } from "./componentConfigSchemas";

  let {
    component = "",
    config = $bindable({}),
    onchange = () => {},
  }: {
    component: string;
    config: any;
    onchange: () => void;
  } = $props();

  let openSections = $state<Record<string, boolean>>({});
  let drafts = $state<Record<string, string>>({});
  let errors = $state<Record<string, string>>({});

  let sections = $derived(getComponentConfigSchema(component));

  function setPath(obj: any, path: string, value: any): any {
    const clone = JSON.parse(JSON.stringify(obj ?? {}));
    const keys = path.split(".");
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
    const keys = path.split(".");
    let cur = clone;
    for (let i = 0; i < keys.length - 1; i++) {
      if (cur[keys[i]] === undefined || cur[keys[i]] === null) return clone;
      cur = cur[keys[i]];
    }
    delete cur[keys[keys.length - 1]];
    return clone;
  }

  function updateField(path: string, value: any) {
    config = setPath(config, path, value);
    onchange();
  }

  function clearField(path: string) {
    config = removePath(config, path);
    onchange();
  }

  function toggleSection(key: string) {
    openSections[key] = !openSections[key];
  }

  function fieldId(sectionKey: string, fieldKey: string): string {
    return `${component}-${sectionKey}-${fieldKey.replaceAll(".", "-")}`;
  }

  function displayJson(field: GenericFieldDef): string {
    const path = getFieldPath(field);
    if (drafts[path] !== undefined) return drafts[path];
    const value = getFieldValue(config, field);
    if (value === undefined) {
      return JSON.stringify(field.default ?? {}, null, 2);
    }
    return JSON.stringify(value, null, 2);
  }

  function displayList(field: GenericFieldDef): string {
    const value = getFieldValue(config, field);
    if (Array.isArray(value)) return value.join("\n");
    if (value === undefined && Array.isArray(field.default)) return field.default.join("\n");
    return "";
  }

  function updateJson(field: GenericFieldDef, raw: string) {
    const path = getFieldPath(field);
    drafts[path] = raw;
    if (!raw.trim()) {
      delete errors[path];
      clearField(path);
      return;
    }
    try {
      const parsed = JSON.parse(raw);
      delete errors[path];
      updateField(path, parsed);
    } catch {
      errors[path] = "Invalid JSON";
    }
  }

  function updateList(field: GenericFieldDef, raw: string) {
    const items = raw
      .split("\n")
      .map((item) => item.trim())
      .filter(Boolean);
    updateField(getFieldPath(field), items);
  }

  function updateNumber(field: GenericFieldDef, raw: string) {
    if (!raw.trim()) {
      clearField(getFieldPath(field));
      return;
    }
    const value = Number(raw);
    if (!Number.isNaN(value)) updateField(getFieldPath(field), value);
  }
</script>

<div class="structured-editor">
  {#each sections as section}
    <div class="section">
      <button class="section-header" onclick={() => toggleSection(section.key)}>
        <span class="section-arrow" class:open={openSections[section.key]}>▶</span>
        <span>{section.label}</span>
      </button>

      {#if openSections[section.key] !== false}
        <div class="section-body">
          {#if section.description}
            <p class="section-description">{section.description}</p>
          {/if}

          {#each section.fields as field}
            {@const fieldPath = getFieldPath(field)}
            {@const id = fieldId(section.key, fieldPath)}
            <div class="field">
              <label for={id}>{field.label}</label>

              {#if field.type === "toggle"}
                <label class="toggle-field" for={id}>
                  <input
                    id={id}
                    type="checkbox"
                    checked={!!getFieldValue(config, field)}
                    onchange={(e) => updateField(fieldPath, e.currentTarget.checked)}
                  />
                  <span>{getFieldValue(config, field) ? "Enabled" : "Disabled"}</span>
                </label>
              {:else if field.type === "select"}
                <select
                  id={id}
                  value={getFieldValue(config, field) ?? field.default ?? ""}
                  onchange={(e) => updateField(fieldPath, e.currentTarget.value)}
                >
                  {#each field.options ?? [] as option}
                    <option value={option}>{option}</option>
                  {/each}
                </select>
              {:else if field.type === "number"}
                <input
                  id={id}
                  type="number"
                  value={getFieldValue(config, field) ?? field.default ?? ""}
                  min={field.min}
                  max={field.max}
                  step={field.step}
                  oninput={(e) => updateNumber(field, e.currentTarget.value)}
                />
              {:else if field.type === "password"}
                <input
                  id={id}
                  type="password"
                  value={getFieldValue(config, field) ?? ""}
                  oninput={(e) => updateField(fieldPath, e.currentTarget.value)}
                />
              {:else if field.type === "textarea"}
                <textarea
                  id={id}
                  rows={field.rows ?? 4}
                  oninput={(e) => updateField(fieldPath, e.currentTarget.value)}
                >{getFieldValue(config, field) ?? field.default ?? ""}</textarea>
              {:else if field.type === "list"}
                <textarea
                  id={id}
                  rows={field.rows ?? 4}
                  value={displayList(field)}
                  oninput={(e) => updateList(field, e.currentTarget.value)}
                ></textarea>
              {:else if field.type === "json"}
                <textarea
                  id={id}
                  rows={field.rows ?? 6}
                  value={displayJson(field)}
                  oninput={(e) => updateJson(field, e.currentTarget.value)}
                ></textarea>
              {:else}
                <input
                  id={id}
                  type="text"
                  value={getFieldValue(config, field) ?? field.default ?? ""}
                  oninput={(e) => updateField(fieldPath, e.currentTarget.value)}
                />
              {/if}

              {#if field.hint}
                <p class="hint">{field.hint}</p>
              {/if}
              {#if errors[fieldPath]}
                <p class="error">{errors[fieldPath]}</p>
              {/if}
            </div>
          {/each}
        </div>
      {/if}
    </div>
  {/each}
</div>

<style>
  .structured-editor {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-md);
  }

  .section {
    border: 1px solid rgba(141, 154, 178, 0.18);
    border-radius: var(--radius-lg);
    background: linear-gradient(180deg, rgba(255, 255, 255, 0.82), rgba(244, 248, 255, 0.72));
    box-shadow: var(--shadow-sm);
    backdrop-filter: blur(16px);
  }

  .section-header {
    width: 100%;
    background: none;
    border: none;
    color: var(--slate-900);
    display: flex;
    align-items: center;
    gap: 0.5rem;
    padding: 1rem 1.1rem;
    cursor: pointer;
    font-family: var(--font-display);
    font-size: var(--text-sm);
    font-weight: 600;
    letter-spacing: -0.01em;
  }

  .section-arrow {
    font-size: 0.7rem;
    transition: transform var(--transition-fast);
    color: var(--cyan-600);
  }

  .section-arrow.open {
    transform: rotate(90deg);
  }

  .section-body {
    padding: 0 1.1rem 1.1rem;
    border-top: 1px solid rgba(141, 154, 178, 0.16);
  }

  .section-description {
    margin: 0 0 1rem;
    color: var(--slate-600);
    font-size: 0.875rem;
    line-height: 1.6;
  }

  .field {
    display: flex;
    flex-direction: column;
    gap: 0.35rem;
    margin-bottom: 1rem;
  }

  .field label {
    font-size: 0.8125rem;
    font-weight: 600;
    color: var(--slate-700);
    letter-spacing: -0.01em;
  }

  .field input,
  .field select,
  .field textarea {
    width: 100%;
    background: rgba(255, 255, 255, 0.8);
    border: 1px solid rgba(141, 154, 178, 0.22);
    border-radius: var(--radius-md);
    padding: 0.65rem 0.8rem;
    color: var(--fg);
    font-size: 0.875rem;
    font-family: var(--font-sans);
    outline: none;
    transition: all var(--transition-fast);
  }

  .field input:focus,
  .field select:focus,
  .field textarea:focus {
    border-color: rgba(34, 211, 238, 0.24);
    box-shadow: var(--focus-ring);
  }

  .field textarea {
    resize: vertical;
    line-height: 1.5;
  }

  .field textarea[id*="json"],
  .field textarea[id*="list"] {
    font-family: var(--font-mono);
  }

  .toggle-field {
    display: flex;
    align-items: center;
    gap: 0.6rem;
    padding: 0.75rem 0.85rem;
    border-radius: var(--radius-md);
    border: 1px solid rgba(141, 154, 178, 0.16);
    background: rgba(255, 255, 255, 0.56);
    color: var(--slate-800);
    font-size: 0.875rem;
  }

  .toggle-field input {
    width: auto;
    margin: 0;
  }

  .hint {
    margin: 0;
    color: var(--slate-500);
    font-size: 0.75rem;
    line-height: 1.4;
    font-family: var(--font-sans);
  }

  .error {
    margin: 0;
    color: var(--red-600);
    font-size: 0.75rem;
    font-weight: 600;
  }
</style>
