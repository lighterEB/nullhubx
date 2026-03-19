<script lang="ts">
  import { onMount } from "svelte";
  import { api } from "$lib/api/client";
  import ConfigEditorUI from "./ConfigEditorUI.svelte";
  import StructuredConfigEditor from "./StructuredConfigEditor.svelte";
  import { supportsStructuredConfig } from "./componentConfigSchemas";
  import { t } from "$lib/i18n/index.svelte";

  let {
    component = "",
    name = "",
    onAction = async () => {},
  }: {
    component?: string;
    name?: string;
    onAction?: () => void | Promise<void>;
  } = $props();
  let configObj = $state<any>({});
  let configText = $state("");
  let mode = $state<"ui" | "raw">("ui");
  let action = $state<"save" | "save-restart" | null>(null);
  let message = $state("");
  let error = $state(false);
  let loaded = $state(false);
  let supportsUi = $derived(
    component === "nullclaw" || supportsStructuredConfig(component),
  );
  let busy = $derived(action !== null);

  $effect(() => {
    if (!supportsUi && mode === "ui") {
      mode = "raw";
    }
  });

  async function load() {
    try {
      const data = await api.getConfig(component, name);
      configObj = typeof data === "string" ? JSON.parse(data) : data;
      configText = JSON.stringify(configObj, null, 2);
      message = "";
      error = false;
    } catch (e) {
      configObj = {};
      configText = "{}";
      message = t("configEditor.notFound");
      error = false;
    }
    loaded = true;
  }

  function switchMode(newMode: "ui" | "raw") {
    if (newMode === mode) return;
    if (newMode === "raw") {
      configText = JSON.stringify(configObj, null, 2);
    } else {
      try {
        configObj = JSON.parse(configText);
      } catch (e) {
        message = t("configEditor.invalidJson");
        error = true;
        return;
      }
    }
    mode = newMode;
    message = "";
    error = false;
  }

  function onUiChange() {
    message = "";
  }

  function currentConfig() {
    if (mode === "raw") {
      const parsed = JSON.parse(configText);
      configObj = parsed;
      return parsed;
    }
    configText = JSON.stringify(configObj, null, 2);
    return configObj;
  }

  async function save(restartAfterSave = false) {
    action = restartAfterSave ? "save-restart" : "save";
    let saved = false;
    try {
      const toSave = currentConfig();
      await api.putConfig(component, name, toSave);
      saved = true;

      if (restartAfterSave) {
        message = t("configEditor.savedAndRestarting");
        await api.restartInstance(component, name);
      } else {
        message = t("configEditor.saved");
      }

      error = false;
      await onAction();
    } catch (e) {
      const err = (e as Error).message;
      if (saved && restartAfterSave) {
        message = `${t("configEditor.saved")}，${t("common.restart")}：${err}`;
      } else {
        message = `${t("common.error")}：${err}`;
      }
      error = true;
    } finally {
      action = null;
    }
  }

  onMount(() => { load(); });
</script>

<div class="config-editor">
  <div class="editor-header">
    {#if supportsUi}
      <div class="mode-toggle">
        <button class="mode-btn" class:active={mode === 'ui'} onclick={() => switchMode('ui')}>{t("configEditor.uiMode")}</button>
        <button class="mode-btn" class:active={mode === 'raw'} onclick={() => switchMode('raw')}>{t("configEditor.rawMode")}</button>
      </div>
    {:else}
      <div class="mode-toggle">
        <button class="mode-btn active">{t("configEditor.rawMode")}</button>
      </div>
    {/if}
    <div class="action-buttons">
      <button class="save-btn" onclick={() => save()} disabled={busy}>
        {action === "save" ? t("common.saving") : t("common.save")}
      </button>
      <button class="save-btn secondary" onclick={() => save(true)} disabled={busy}>
        {action === "save-restart" ? t("common.restarting") : t("configEditor.saveAndRestart")}
      </button>
    </div>
  </div>
  {#if message}
    <div class="message" class:error>{message}</div>
  {/if}
  {#if loaded}
    {#if supportsUi && mode === 'ui'}
      <div class="ui-content">
        {#if component === 'nullclaw'}
          <ConfigEditorUI bind:config={configObj} onchange={onUiChange} />
        {:else}
          <StructuredConfigEditor {component} bind:config={configObj} onchange={onUiChange} />
        {/if}
      </div>
    {:else}
      <textarea class="raw-editor" bind:value={configText} spellcheck="false"></textarea>
    {/if}
  {/if}
</div>

<style>
  .config-editor {
    display: flex;
    flex-direction: column;
  }
  .editor-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 0.5rem 0;
    margin-bottom: 0.5rem;
    gap: 1rem;
  }
  .mode-toggle {
    display: flex;
    gap: 0;
  }
  .action-buttons {
    display: flex;
    gap: 0.75rem;
    flex-wrap: wrap;
    justify-content: flex-end;
  }
  .mode-btn {
    padding: 0.5rem 1rem;
    border: 1px solid var(--border);
    background: var(--bg-surface);
    color: var(--fg-dim);
    font-size: 0.8125rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 1px;
    cursor: pointer;
    transition: all 0.2s ease;
  }
  .mode-btn:first-child {
    border-radius: var(--radius-sm) 0 0 var(--radius-sm);
  }
  .mode-btn:last-child {
    border-radius: 0 var(--radius-sm) var(--radius-sm) 0;
    border-left: none;
  }
  .mode-btn:hover {
    background: var(--bg-hover);
    border-color: var(--accent-dim);
    color: var(--fg);
  }
  .mode-btn.active {
    background: color-mix(in srgb, var(--accent) 15%, transparent);
    border-color: var(--accent);
    color: var(--accent);

    box-shadow: inset 0 0 5px color-mix(in srgb, var(--accent) 30%, transparent);
  }
  .save-btn {
    padding: 0.5rem 1.25rem;
    background: color-mix(in srgb, var(--accent) 15%, transparent);
    color: var(--accent);
    border: 1px solid var(--accent);
    border-radius: var(--radius-sm);
    cursor: pointer;
    font-size: 0.8125rem;
    font-family: var(--font-mono);
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 1px;
    transition: all 0.2s ease;
    box-shadow: inset 0 0 8px color-mix(in srgb, var(--accent) 30%, transparent);
  }
  .save-btn:hover:not(:disabled) {
    background: color-mix(in srgb, var(--accent) 30%, transparent);
    box-shadow: 0 0 10px var(--border-glow), inset 0 0 10px color-mix(in srgb, var(--accent) 50%, transparent);

  }
  .save-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
    box-shadow: none;
    border-color: var(--border);
    color: var(--fg-dim);
  }
  .save-btn.secondary {
    background: color-mix(in srgb, var(--warning, #f59e0b) 12%, transparent);
    color: var(--warning, #f59e0b);
    border-color: color-mix(in srgb, var(--warning, #f59e0b) 65%, var(--border));
    box-shadow: inset 0 0 8px color-mix(in srgb, var(--warning, #f59e0b) 25%, transparent);
  }
  .save-btn.secondary:hover:not(:disabled) {
    background: color-mix(in srgb, var(--warning, #f59e0b) 24%, transparent);
    box-shadow: 0 0 10px color-mix(in srgb, var(--warning, #f59e0b) 20%, transparent),
      inset 0 0 10px color-mix(in srgb, var(--warning, #f59e0b) 40%, transparent);
  }
  .ui-content {
    max-height: 600px;
    overflow-y: auto;
    padding-right: 0.25rem;
  }
  .ui-content::-webkit-scrollbar {
    width: 6px;
  }
  .ui-content::-webkit-scrollbar-track {
    background: transparent;
  }
  .ui-content::-webkit-scrollbar-thumb {
    background: var(--border);
    border-radius: 3px;
  }
  .ui-content::-webkit-scrollbar-thumb:hover {
    background: var(--accent-dim);
  }
  .raw-editor {
    flex: 1;
    min-height: 400px;
    background: var(--bg-surface);
    color: var(--fg);
    border: 1px solid var(--border);
    border-radius: var(--radius-sm);
    padding: 1rem;
    font-family: var(--font-mono);
    font-size: 0.875rem;
    resize: none;
    line-height: 1.6;
    outline: none;
    transition: all 0.2s ease;
    box-shadow: inset 0 1px 2px rgba(15, 23, 42, 0.08);
  }
  .raw-editor:focus {
    border-color: var(--accent);
    box-shadow: inset 0 1px 2px rgba(15, 23, 42, 0.08), 0 0 0 3px color-mix(in srgb, var(--accent) 16%, transparent);
  }
  .message {
    padding: 0.75rem 1rem;
    margin-bottom: 0.75rem;
    border-radius: var(--radius-sm);
    font-size: 0.8125rem;
    font-family: var(--font-mono);
    text-transform: uppercase;
    letter-spacing: 0.5px;
    background: color-mix(in srgb, var(--success, #22c55e) 15%, transparent);
    color: var(--success, #22c55e);
    border: 1px solid color-mix(in srgb, var(--success, #22c55e) 30%, transparent);
  }
  .message.error {
    background: color-mix(in srgb, var(--error) 15%, transparent);
    color: var(--error);
    border-color: color-mix(in srgb, var(--error) 30%, transparent);
  }

  @media (max-width: 900px) {
    .editor-header {
      flex-direction: column;
      align-items: stretch;
    }

    .action-buttons {
      justify-content: stretch;
    }

    .action-buttons .save-btn {
      flex: 1;
    }
  }

  @media (max-width: 640px) {
    .mode-btn {
      flex: 1;
      text-align: center;
    }
  }
</style>
