<script lang="ts">
  import { onMount, onDestroy } from 'svelte';
  import { mount, unmount } from 'svelte';

  let { moduleName = '', moduleVersion = '', instanceUrl = '', token = '' } = $props();
  let container: HTMLElement;
  let mountedComponent: any = null;
  let error = $state('');

  onMount(async () => {
    try {
      const moduleUrl = `/ui/${moduleName}@${moduleVersion}/module.js`;
      const mod = await import(/* @vite-ignore */ moduleUrl);
      if (mod.create && container) {
        mountedComponent = mod.create(container, {
          instanceUrl,
          token,
          theme: 'dark'
        });
      } else if (mod.default && container) {
        mountedComponent = mount(mod.default, {
          target: container,
          props: { instanceUrl, token, theme: 'dark' }
        });
      }
    } catch (e) {
      error = `Failed to load module: ${(e as Error).message}`;
    }
  });

  onDestroy(() => {
    if (mountedComponent && typeof unmount === 'function') {
      try { unmount(mountedComponent); } catch {}
    }
  });
</script>

<div class="module-frame">
  {#if error}
    <div class="module-error">{error}</div>
  {/if}
  <div bind:this={container} class="module-container"></div>
</div>

<style>
  .module-frame { width: 100%; height: 100%; min-height: 400px; }
  .module-container { width: 100%; height: 100%; }
  .module-error { padding: 1rem; color: var(--error); background: color-mix(in srgb, var(--error) 10%, transparent); border-radius: var(--radius); margin-bottom: 1rem; font-size: 0.875rem; }
</style>
