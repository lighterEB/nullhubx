<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import { mount, unmount } from "svelte";
  import { t } from "$lib/i18n/index.svelte";

  let { moduleName = "", moduleVersion = "", instanceUrl = "", token = "", moduleProps = {} } = $props<{
    moduleName?: string;
    moduleVersion?: string;
    instanceUrl?: string;
    token?: string;
    moduleProps?: Record<string, unknown>;
  }>();
  let container: HTMLElement;
  let mountedComponent: { destroy?: () => void } | null = null;
  let error = $state("");
  let loading = $state(true);

  onMount(async () => {
    try {
      const moduleUrl = `/ui/${moduleName}@${moduleVersion}/module.js`;
      const mod = await import(/* @vite-ignore */ moduleUrl);
      const opts = {
        instanceUrl,
        token,
        theme: "dark",
        ...moduleProps,
      };
      if (mod.create && container) {
        mountedComponent = mod.create(container, opts);
      } else if (mod.default && container) {
        mountedComponent = mount(mod.default, {
          target: container,
          props: opts,
        });
      }
    } catch (e) {
      error = (e as Error).message;
    } finally {
      loading = false;
    }
  });

  onDestroy(() => {
    if (mountedComponent) {
      if (mountedComponent.destroy && typeof mountedComponent.destroy === "function") {
        try {
          mountedComponent.destroy();
        } catch {
          // Ignore teardown failures from third-party UI modules.
        }
      } else if (typeof unmount === "function") {
        try {
          unmount(mountedComponent);
        } catch {
          // Ignore teardown failures from dynamically mounted components.
        }
      }
    }
  });
</script>

<div class="module-frame">
  {#if error}
    <div class="module-state error">
      <span class="module-state-label">{t("moduleFrame.failed")}</span>
      <p>{error}</p>
    </div>
  {:else if loading}
    <div class="module-state loading">
      <span class="module-state-label">{t("moduleFrame.loading")}</span>
      <p>{moduleName}@{moduleVersion}</p>
    </div>
  {/if}
  <div bind:this={container} class:hidden={loading || !!error} class="module-container"></div>
</div>

<style>
  .module-frame {
    width: 100%;
    height: 100%;
    min-height: 400px;
    border-radius: calc(var(--radius-xl) - 6px);
    border: 1px solid rgba(96, 165, 250, 0.14);
    background:
      linear-gradient(180deg, rgba(7, 12, 22, 0.94), rgba(10, 17, 31, 0.92)),
      radial-gradient(circle at top right, rgba(34, 211, 238, 0.08), transparent 36%);
    box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.03);
    overflow: hidden;
  }

  .module-container {
    width: 100%;
    height: 100%;
  }

  .module-container.hidden {
    display: none;
  }

  .module-state {
    height: 100%;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 0.5rem;
    padding: 2rem;
    text-align: center;
    font-family: var(--font-mono);
  }

  .module-state-label {
    font-size: 0.74rem;
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }

  .module-state p {
    margin: 0;
    color: rgba(191, 219, 254, 0.72);
    font-size: 0.82rem;
    line-height: 1.6;
  }

  .module-state.loading {
    color: var(--cyan-300);
  }

  .module-state.error {
    color: #fda4af;
    background:
      linear-gradient(180deg, rgba(31, 12, 20, 0.92), rgba(22, 10, 17, 0.88)),
      radial-gradient(circle at top right, rgba(244, 63, 94, 0.08), transparent 36%);
  }
</style>
