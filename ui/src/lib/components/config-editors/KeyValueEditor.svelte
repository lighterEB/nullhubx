<script lang="ts">
  import { t } from "$lib/i18n/index.svelte";
  import type { ConfigFieldDef } from "../configSchemaContract";

  interface PairRow {
    id: string;
    key: string;
    value: string;
  }

  let {
    value = {},
    fields = [],
    addLabel = "",
    emptyLabel = "",
    onchange = (_next: Record<string, string>) => {},
  }: {
    value?: unknown;
    fields?: ConfigFieldDef[];
    addLabel?: string;
    emptyLabel?: string;
    onchange?: (next: Record<string, string>) => void;
  } = $props();

  let rows = $state<PairRow[]>([]);
  let suppressNextSync = $state(false);

  const keyField = $derived(fields[0]);
  const valueField = $derived(fields[1]);
  const normalizedRows = $derived(normalizeRows(value));

  function isPairObject(input: unknown): input is { key?: unknown; value?: unknown } {
    return typeof input === "object" && input !== null && !Array.isArray(input);
  }

  function buildStableId(index: number, key: string): string {
    return `pair-${index}-${key || "draft"}`;
  }

  function normalizeRows(input: unknown): PairRow[] {
    if (Array.isArray(input)) {
      return input
        .filter(isPairObject)
        .map((entry, index) => ({
          id: buildStableId(index, String(entry.key ?? "")),
          key: String(entry.key ?? ""),
          value: String(entry.value ?? ""),
        }));
    }

    if (typeof input === "object" && input !== null) {
      return Object.entries(input as Record<string, unknown>).map(([entryKey, entryValue], index) => ({
        id: buildStableId(index, entryKey),
        key: entryKey,
        value: String(entryValue ?? ""),
      }));
    }

    return [];
  }

  $effect(() => {
    if (suppressNextSync) {
      suppressNextSync = false;
      return;
    }

    rows = normalizedRows;
  });

  function emit(nextRows: PairRow[]) {
    rows = nextRows;
    suppressNextSync = true;

    const output: Record<string, string> = {};
    for (const row of nextRows) {
      const trimmedKey = row.key.trim();
      if (!trimmedKey) continue;
      output[trimmedKey] = row.value;
    }

    onchange(output);
  }

  function updateRow(index: number, field: "key" | "value", nextValue: string) {
    const nextRows = rows.map((row, rowIndex) => (
      rowIndex === index ? { ...row, [field]: nextValue } : row
    ));
    emit(nextRows);
  }

  function addRow() {
    emit([...rows, { id: `pair-draft-${rows.length}`, key: "", value: "" }]);
  }

  function removeRow(index: number) {
    emit(rows.filter((_, rowIndex) => rowIndex !== index));
  }

  function moveRow(index: number, delta: -1 | 1) {
    const nextIndex = index + delta;
    if (nextIndex < 0 || nextIndex >= rows.length) return;

    const nextRows = [...rows];
    const [row] = nextRows.splice(index, 1);
    nextRows.splice(nextIndex, 0, row);
    emit(nextRows);
  }
</script>

<div class="key-value-editor">
  {#if rows.length === 0}
    <div class="empty-state">{emptyLabel || t("configEditorUi.noEntries")}</div>
  {/if}

  {#each rows as row, index (row.id)}
    <div class="pair-row">
      <input
        type="text"
        class="pair-input"
        placeholder={keyField?.label ?? "Key"}
        aria-label={keyField?.label ?? "Key"}
        value={row.key}
        oninput={(e) => updateRow(index, "key", e.currentTarget.value)}
      />
      <input
        type={valueField?.type === "password" ? "password" : "text"}
        class="pair-input"
        placeholder={valueField?.label ?? "Value"}
        aria-label={valueField?.label ?? "Value"}
        value={row.value}
        oninput={(e) => updateRow(index, "value", e.currentTarget.value)}
      />
      <div class="pair-actions">
        <button
          type="button"
          class="icon-btn"
          title={t("configEditorUi.moveUp")}
          aria-label={t("configEditorUi.moveUp")}
          onclick={() => moveRow(index, -1)}
          disabled={index === 0}
        >↑</button>
        <button
          type="button"
          class="icon-btn"
          title={t("configEditorUi.moveDown")}
          aria-label={t("configEditorUi.moveDown")}
          onclick={() => moveRow(index, 1)}
          disabled={index === rows.length - 1}
        >↓</button>
        <button
          type="button"
          class="icon-btn danger"
          title={t("configEditorUi.removeEntry")}
          aria-label={t("configEditorUi.removeEntry")}
          onclick={() => removeRow(index)}
        >×</button>
      </div>
    </div>
  {/each}

  <button type="button" class="add-btn" onclick={addRow}>
    + {addLabel || t("configEditorUi.addPair")}
  </button>
</div>

<style>
  .key-value-editor {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
  }

  .empty-state {
    padding: 0.9rem 1rem;
    border: 1px dashed rgba(141, 154, 178, 0.28);
    border-radius: var(--radius-md);
    color: var(--slate-500);
    font-size: 0.875rem;
    background: rgba(255, 255, 255, 0.5);
  }

  .pair-row {
    display: grid;
    grid-template-columns: minmax(0, 1fr) minmax(0, 1.4fr) auto;
    gap: 0.65rem;
    align-items: center;
  }

  .pair-input,
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

  .pair-input:focus {
    outline: none;
    border-color: rgba(34, 211, 238, 0.24);
    box-shadow: var(--focus-ring);
  }

  .pair-actions {
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

  .add-btn {
    color: var(--cyan-600);
    background: rgba(34, 211, 238, 0.08);
    border-style: dashed;
    font-weight: 600;
  }

  @media (max-width: 720px) {
    .pair-row {
      grid-template-columns: 1fr;
    }

    .pair-actions {
      justify-content: flex-end;
    }
  }
</style>
