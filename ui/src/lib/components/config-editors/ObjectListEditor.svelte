<script lang="ts">
  import { t } from "$lib/i18n/index.svelte";
  import type { ConfigFieldDef } from "../configSchemaContract";

  type ObjectItem = Record<string, unknown>;

  let {
    value = [],
    fields = [],
    addLabel = "",
    emptyLabel = "",
    onchange = (_next: ObjectItem[]) => {},
  }: {
    value?: unknown;
    fields?: ConfigFieldDef[];
    addLabel?: string;
    emptyLabel?: string;
    onchange?: (next: ObjectItem[]) => void;
  } = $props();

  function isObjectItem(input: unknown): input is ObjectItem {
    return typeof input === "object" && input !== null && !Array.isArray(input);
  }

  function cloneValue<T>(input: T): T {
    if (input === undefined) return input;
    return JSON.parse(JSON.stringify(input)) as T;
  }

  function normalizeItems(input: unknown): ObjectItem[] {
    if (!Array.isArray(input)) return [];
    return input.filter(isObjectItem).map((item) => ({ ...item }));
  }

  let items = $derived(normalizeItems(value));

  function defaultValueForField(field: ConfigFieldDef): unknown {
    if (field.default !== undefined) return cloneValue(field.default);

    switch (field.type) {
      case "toggle":
        return false;
      case "list":
        return [];
      case "select":
        return field.options?.[0] ?? "";
      default:
        return undefined;
    }
  }

  function createItem(): ObjectItem {
    const item: ObjectItem = {};
    for (const field of fields) {
      const defaultValue = defaultValueForField(field);
      if (defaultValue !== undefined) {
        item[field.key] = defaultValue;
      }
    }
    return item;
  }

  function getItemValue(item: ObjectItem, field: ConfigFieldDef): unknown {
    return item[field.key];
  }

  function emit(nextItems: ObjectItem[]) {
    onchange(nextItems);
  }

  function updateItemField(index: number, fieldKey: string, nextValue: unknown) {
    const nextItems = items.map((item, itemIndex) => (
      itemIndex === index ? { ...item, [fieldKey]: nextValue } : item
    ));
    emit(nextItems);
  }

  function clearItemField(index: number, fieldKey: string) {
    const nextItems = items.map((item, itemIndex) => {
      if (itemIndex !== index) return item;
      const nextItem = { ...item };
      delete nextItem[fieldKey];
      return nextItem;
    });
    emit(nextItems);
  }

  function addItem() {
    emit([...items, createItem()]);
  }

  function removeItem(index: number) {
    emit(items.filter((_, itemIndex) => itemIndex !== index));
  }

  function moveItem(index: number, delta: -1 | 1) {
    const nextIndex = index + delta;
    if (nextIndex < 0 || nextIndex >= items.length) return;

    const nextItems = [...items];
    const [item] = nextItems.splice(index, 1);
    nextItems.splice(nextIndex, 0, item);
    emit(nextItems);
  }

  function parseList(raw: unknown): string {
    return Array.isArray(raw) ? raw.map(String).join("\n") : "";
  }

  function updateList(index: number, fieldKey: string, raw: string) {
    const items = raw
      .split("\n")
      .map((item) => item.trim())
      .filter(Boolean);
    updateItemField(index, fieldKey, items);
  }

  function updateNumber(index: number, fieldKey: string, raw: string) {
    if (!raw.trim()) {
      clearItemField(index, fieldKey);
      return;
    }

    const numericValue = Number(raw);
    if (!Number.isNaN(numericValue)) {
      updateItemField(index, fieldKey, numericValue);
    }
  }
</script>

<div class="object-list-editor">
  {#if items.length === 0}
    <div class="empty-state">{emptyLabel || t("configEditorUi.noEntries")}</div>
  {/if}

  {#each items as item, index (index)}
    <div class="item-card">
      <div class="item-header">
        <span class="item-title">#{index + 1}</span>
        <div class="item-actions">
          <button
            type="button"
            class="icon-btn"
            title={t("configEditorUi.moveUp")}
            aria-label={t("configEditorUi.moveUp")}
            onclick={() => moveItem(index, -1)}
            disabled={index === 0}
          >↑</button>
          <button
            type="button"
            class="icon-btn"
            title={t("configEditorUi.moveDown")}
            aria-label={t("configEditorUi.moveDown")}
            onclick={() => moveItem(index, 1)}
            disabled={index === items.length - 1}
          >↓</button>
          <button
            type="button"
            class="icon-btn danger"
            title={t("configEditorUi.removeEntry")}
            aria-label={t("configEditorUi.removeEntry")}
            onclick={() => removeItem(index)}
          >×</button>
        </div>
      </div>

      <div class="item-fields">
        {#each fields as field}
          {@const currentValue = getItemValue(item, field)}
          <div class="field">
            <div class="field-title">{field.label}</div>

            {#if field.type === "toggle"}
              <label class="toggle-field">
                <input
                  type="checkbox"
                  checked={!!currentValue}
                  onchange={(e) => updateItemField(index, field.key, e.currentTarget.checked)}
                />
                <span>{field.label}</span>
              </label>
            {:else if field.type === "select"}
              <select
                value={String(currentValue ?? field.default ?? "")}
                onchange={(e) => updateItemField(index, field.key, e.currentTarget.value)}
              >
                {#each field.options ?? [] as option}
                  <option value={option}>{field.optionLabels?.[option] ?? option}</option>
                {/each}
              </select>
            {:else if field.type === "number"}
              <input
                type="number"
                value={String(currentValue ?? field.default ?? "")}
                min={field.min}
                max={field.max}
                step={field.step}
                oninput={(e) => updateNumber(index, field.key, e.currentTarget.value)}
              />
            {:else if field.type === "list"}
              <textarea
                rows={field.rows ?? 4}
                value={parseList(currentValue)}
                oninput={(e) => updateList(index, field.key, e.currentTarget.value)}
              ></textarea>
            {:else if field.type === "textarea"}
              <textarea
                rows={field.rows ?? 4}
                value={String(currentValue ?? field.default ?? "")}
                oninput={(e) => updateItemField(index, field.key, e.currentTarget.value)}
              ></textarea>
            {:else}
              <input
                type={field.type === "password" ? "password" : "text"}
                value={String(currentValue ?? field.default ?? "")}
                oninput={(e) => updateItemField(index, field.key, e.currentTarget.value)}
              />
            {/if}

            {#if field.hint}
              <p class="hint">{field.hint}</p>
            {/if}
          </div>
        {/each}
      </div>
    </div>
  {/each}

  <button type="button" class="add-btn" onclick={addItem}>
    + {addLabel || t("configEditorUi.addEntry")}
  </button>
</div>

<style>
  .object-list-editor {
    display: flex;
    flex-direction: column;
    gap: 0.85rem;
  }

  .empty-state {
    padding: 0.9rem 1rem;
    border: 1px dashed rgba(141, 154, 178, 0.28);
    border-radius: var(--radius-md);
    color: var(--slate-500);
    font-size: 0.875rem;
    background: rgba(255, 255, 255, 0.5);
  }

  .item-card {
    border: 1px solid rgba(141, 154, 178, 0.18);
    border-radius: var(--radius-md);
    background: rgba(255, 255, 255, 0.66);
    box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.55);
  }

  .item-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 0.85rem 0.95rem;
    border-bottom: 1px solid rgba(141, 154, 178, 0.14);
  }

  .item-title {
    color: var(--slate-700);
    font-size: 0.8125rem;
    font-family: var(--font-mono);
  }

  .item-actions {
    display: flex;
    gap: 0.4rem;
  }

  .icon-btn,
  .add-btn {
    border-radius: var(--radius-md);
    border: 1px solid rgba(141, 154, 178, 0.18);
    background: rgba(255, 255, 255, 0.82);
    color: var(--slate-700);
    cursor: pointer;
    transition: all var(--transition-fast);
  }

  .icon-btn {
    width: 2rem;
    height: 2rem;
    font-size: 0.875rem;
  }

  .icon-btn:disabled {
    opacity: 0.45;
    cursor: not-allowed;
  }

  .icon-btn.danger {
    color: var(--red-600);
    border-color: rgba(244, 63, 94, 0.16);
  }

  .icon-btn:not(:disabled):hover,
  .add-btn:hover {
    border-color: rgba(34, 211, 238, 0.28);
    box-shadow: var(--focus-ring);
  }

  .item-fields {
    display: grid;
    gap: 0.9rem;
    padding: 0.95rem;
  }

  .field {
    display: flex;
    flex-direction: column;
    gap: 0.4rem;
  }

  .field label,
  .field-title {
    color: var(--slate-700);
    font-size: 0.8125rem;
    font-weight: 600;
  }

  .field input,
  .field select,
  .field textarea,
  .add-btn {
    width: 100%;
    padding: 0.7rem 0.8rem;
    border: 1px solid rgba(141, 154, 178, 0.22);
    border-radius: var(--radius-md);
    background: rgba(255, 255, 255, 0.8);
    color: var(--fg);
    font-size: 0.875rem;
    font-family: var(--font-sans);
    box-sizing: border-box;
  }

  .field textarea {
    min-height: 72px;
    resize: vertical;
  }

  .field input:focus,
  .field select:focus,
  .field textarea:focus {
    outline: none;
    border-color: rgba(34, 211, 238, 0.24);
    box-shadow: var(--focus-ring);
  }

  .toggle-field {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    padding: 0.75rem 0.85rem;
    border-radius: var(--radius-md);
    background: rgba(255, 255, 255, 0.56);
    border: 1px solid rgba(141, 154, 178, 0.16);
  }

  .toggle-field input[type="checkbox"] {
    width: 1.1rem;
    height: 1.1rem;
    accent-color: var(--accent);
  }

  .hint {
    margin: 0;
    color: var(--slate-500);
    font-size: 0.75rem;
    line-height: 1.45;
  }

  .add-btn {
    color: var(--cyan-600);
    background: rgba(34, 211, 238, 0.08);
    border-style: dashed;
    font-weight: 600;
  }
</style>
