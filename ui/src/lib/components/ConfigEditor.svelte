<script lang="ts">
  import { onMount } from "svelte";
  import { api } from "$lib/api/client";

  let { component = "", name = "" } = $props();
  let configText = $state("");
  let saving = $state(false);
  let message = $state("");
  let error = $state(false);
  let loaded = $state(false);

  async function load() {
    try {
      const data = await api.getConfig(component, name);
      configText =
        typeof data === "string" ? data : JSON.stringify(data, null, 2);
      message = "";
      error = false;
    } catch (e) {
      configText = "{}";
      message = "No config found, starting with empty object";
      error = false;
    }
    loaded = true;
  }

  async function save() {
    saving = true;
    try {
      JSON.parse(configText); // validate
      await api.putConfig(component, name, JSON.parse(configText));
      message = "Config saved";
      error = false;
    } catch (e) {
      message = `Error: ${(e as Error).message}`;
      error = true;
    } finally {
      saving = false;
    }
  }

  onMount(() => {
    load();
  });
</script>

<div class="config-editor">
  <div class="editor-header">
    <span>Configuration</span>
    <button onclick={save} disabled={saving}>
      {saving ? "Saving..." : "Save"}
    </button>
  </div>
  {#if message}
    <div class="message" class:error>{message}</div>
  {/if}
  <textarea bind:value={configText} spellcheck="false"></textarea>
</div>

<style>
  .config-editor {
    display: flex;
    flex-direction: column;
    height: 400px;
  }
  .editor-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 0.5rem 0;
    font-size: 0.8125rem;
    color: var(--accent);
    text-transform: uppercase;
    letter-spacing: 1px;
    font-weight: 700;
  }
  .editor-header button {
    padding: 0.5rem 1.25rem;
    background: color-mix(in srgb, var(--accent) 15%, transparent);
    color: var(--accent);
    border: 1px solid var(--accent);
    border-radius: 2px;
    cursor: pointer;
    font-size: 0.8125rem;
    font-family: var(--font-mono);
    text-transform: uppercase;
    letter-spacing: 1px;
    transition: all 0.2s ease;
    box-shadow: inset 0 0 8px color-mix(in srgb, var(--accent) 30%, transparent);
  }
  .editor-header button:hover:not(:disabled) {
    background: color-mix(in srgb, var(--accent) 30%, transparent);
    box-shadow:
      0 0 10px var(--border-glow),
      inset 0 0 10px color-mix(in srgb, var(--accent) 50%, transparent);
    text-shadow: var(--text-glow);
  }
  .editor-header button:disabled {
    opacity: 0.5;
    cursor: not-allowed;
    box-shadow: none;
    border-color: var(--border);
    color: var(--fg-dim);
  }
  textarea {
    flex: 1;
    background: var(--bg-surface);
    color: var(--fg);
    border: 1px solid var(--border);
    border-radius: 2px;
    padding: 1rem;
    font-family: var(--font-mono);
    font-size: 0.875rem;
    resize: none;
    line-height: 1.6;
    outline: none;
    transition: all 0.2s ease;
    box-shadow: inset 0 2px 8px rgba(0, 0, 0, 0.5);
  }
  textarea:focus {
    border-color: var(--accent);
    box-shadow:
      inset 0 2px 8px rgba(0, 0, 0, 0.5),
      0 0 8px var(--border-glow);
  }
  .message {
    padding: 0.75rem 1rem;
    margin-bottom: 0.75rem;
    border-radius: 2px;
    font-size: 0.8125rem;
    font-family: var(--font-mono);
    text-transform: uppercase;
    letter-spacing: 0.5px;
    background: color-mix(in srgb, var(--success, #22c55e) 15%, transparent);
    color: var(--success, #22c55e);
    border: 1px solid
      color-mix(in srgb, var(--success, #22c55e) 30%, transparent);
    text-shadow: 0 0 5px var(--success, #22c55e);
  }
  .message.error {
    background: color-mix(in srgb, var(--error) 15%, transparent);
    color: var(--error);
    border-color: color-mix(in srgb, var(--error) 30%, transparent);
    text-shadow: 0 0 5px var(--error);
  }
</style>
