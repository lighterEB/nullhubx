<script lang="ts">
  import { api } from "$lib/api/client";
  import ConfigEditorUI from "./ConfigEditorUI.svelte";
  import StructuredConfigEditor from "./StructuredConfigEditor.svelte";
  import { getConfigUiKind } from "./configSchemaRegistry";
  import { t } from "$lib/i18n/index.svelte";

  let {
    component = "",
    name = "",
    active = false,
    onAction = async () => {},
  }: {
    component?: string;
    name?: string;
    active?: boolean;
    onAction?: () => void | Promise<void>;
  } = $props();
  let configObj = $state<any>({});
  let configText = $state("");
  let mode = $state<"ui" | "raw">("ui");
  let action = $state<"save" | "save-restart" | null>(null);
  let message = $state("");
  let error = $state(false);
  let loaded = $state(false);
  let loadedKey = $state("");
  let configUiKind = $derived(getConfigUiKind(component));
  let supportsUi = $derived(configUiKind !== "raw");
  let busy = $derived(action !== null);
  const configKey = $derived(component && name ? `${component}/${name}` : "");

  $effect(() => {
    if (!supportsUi && mode === "ui") {
      mode = "raw";
    }
  });

  async function load(force = false) {
    if (!configKey) return;
    if (!force && loaded && loadedKey === configKey) return;

    loaded = false;
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
    loadedKey = configKey;
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
        message = `${t("configEditor.saved")}, ${t("common.restart")}: ${err}`;
      } else {
        message = `${t("common.error")}: ${err}`;
      }
      error = true;
    } finally {
      action = null;
    }
  }

  $effect(() => {
    if (!active || !configKey) return;
    void load();
  });
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
      <button class="control-btn primary save-btn" onclick={() => save()} disabled={busy}>
        {action === "save" ? t("common.saving") : t("common.save")}
      </button>
      <button class="control-btn warning save-btn secondary" onclick={() => save(true)} disabled={busy}>
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
        {#if configUiKind === 'nullclaw'}
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
    gap: var(--spacing-md);
  }

  .editor-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: var(--spacing-lg);
    gap: 1rem;
    border-radius: var(--radius-lg);
    border: 1px solid rgba(141, 154, 178, 0.18);
    background: linear-gradient(180deg, rgba(255, 255, 255, 0.84), rgba(244, 248, 255, 0.76));
    box-shadow: var(--shadow-sm);
    backdrop-filter: blur(8px);
  }

  .mode-toggle {
    display: flex;
    gap: var(--spacing-xs);
    padding: 4px;
    border-radius: 999px;
    border: 1px solid rgba(141, 154, 178, 0.16);
    background: rgba(255, 255, 255, 0.42);
  }

  .action-buttons {
    display: flex;
    gap: 0.75rem;
    flex-wrap: wrap;
    justify-content: flex-end;
  }

  .mode-btn {
    padding: 10px 14px;
    border: 1px solid transparent;
    background: transparent;
    color: var(--slate-600);
    font-size: var(--text-sm);
    font-family: var(--font-sans);
    font-weight: 600;
    cursor: pointer;
    border-radius: 999px;
    transition:
      color var(--transition-fast),
      background-color var(--transition-fast),
      border-color var(--transition-fast),
      box-shadow var(--transition-fast);
  }

  .mode-btn:hover {
    color: var(--slate-900);
    background: rgba(34, 211, 238, 0.08);
  }

  .mode-btn.active {
    background: linear-gradient(135deg, rgba(34, 211, 238, 0.12), rgba(139, 92, 246, 0.08));
    border-color: rgba(34, 211, 238, 0.18);
    color: var(--cyan-600);
    box-shadow: 0 0 0 1px rgba(34, 211, 238, 0.08);
  }

  .save-btn {
    min-width: 124px;
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
    background: rgba(255, 255, 255, 0.78);
    color: var(--fg);
    border: 1px solid rgba(141, 154, 178, 0.18);
    border-radius: var(--radius-lg);
    padding: 1rem 1.1rem;
    font-family: var(--font-mono);
    font-size: 0.875rem;
    resize: none;
    line-height: 1.6;
    outline: none;
    transition:
      border-color var(--transition-fast),
      box-shadow var(--transition-fast),
      background-color var(--transition-fast),
      color var(--transition-fast);
    box-shadow: var(--shadow-sm);
    backdrop-filter: blur(8px);
  }

  .raw-editor:focus {
    border-color: rgba(34, 211, 238, 0.24);
    box-shadow: var(--focus-ring);
  }

  .message {
    padding: 12px 14px;
    border-radius: var(--radius-md);
    background: rgba(16, 185, 129, 0.08);
    color: var(--emerald-600);
    border: 1px solid rgba(16, 185, 129, 0.16);
    font-size: var(--text-sm);
    box-shadow: var(--shadow-sm);
  }

  .message.error {
    background: rgba(244, 63, 94, 0.08);
    color: var(--red-600);
    border-color: rgba(244, 63, 94, 0.16);
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
