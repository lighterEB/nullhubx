<script lang="ts">
  import ModuleFrame from './ModuleFrame.svelte';

  let { port = 0, moduleName = '', moduleVersion = '' } = $props();

  const wsUrl = $derived(
    port > 0 ? `ws://127.0.0.1:${port}/ws` : ''
  );
  const hasModule = $derived(moduleName.length > 0 && moduleVersion.length > 0);
</script>

<div class="chat-panel">
  {#if hasModule && wsUrl}
    <ModuleFrame
      {moduleName}
      {moduleVersion}
      instanceUrl={wsUrl}
      moduleProps={{ wsUrl, pairingCode: '123456' }}
    />
  {:else if !hasModule}
    <div class="chat-unavailable">
      Chat UI module not installed. Reinstall this instance to add it.
    </div>
  {:else}
    <div class="chat-unavailable">Waiting for web channel port...</div>
  {/if}
</div>

<style>
  .chat-panel {
    height: 600px;
    border: 1px solid var(--border);
    border-radius: var(--radius);
    overflow: hidden;
  }
  .chat-unavailable {
    display: flex;
    align-items: center;
    justify-content: center;
    height: 100%;
    color: var(--text-muted);
    font-size: 0.875rem;
  }
</style>
