<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import { subscribeStatus, runningCount, hubVersion, statusError } from "$lib/statusStore";

  let unsubscribe: (() => void) | null = null;
  let error = $derived($statusError !== null);

  onMount(() => {
    unsubscribe = subscribeStatus();
  });

  onDestroy(() => {
    unsubscribe?.();
  });
</script>

<footer class="statusbar">
  <div class="statusbar-left">
    <span class="status-item">NULLHUBX <span class="status-value">v{$hubVersion}</span></span>
    <span class="divider">|</span>
    <span class="status-item">INSTANCES <span class="status-value">{$runningCount} running</span></span>
  </div>
  <div class="statusbar-right">
    {#if error}
      <span class="status-error">CONNECTION ERROR</span>
    {:else if $runningCount > 0}
      <span class="status-nominal">SYS OPERATIONAL</span>
    {:else}
      <span class="status-idle">SYS IDLE</span>
    {/if}
  </div>
</footer>

<style>
  .statusbar {
    position: fixed;
    bottom: 0;
    left: 0;
    right: 0;
    height: var(--statusbar-height);
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0 var(--spacing-5xl);
    background: white;
    border-top: 1px solid var(--slate-200);
    z-index: 100;
  }

  .statusbar-left {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm);
  }

  .status-item {
    font-family: var(--font-mono);
    font-size: 9px;
    font-weight: 500;
    color: var(--slate-400);
    letter-spacing: 1px;
  }

  .status-value {
    color: var(--slate-600);
    font-weight: 600;
  }

  .divider {
    color: var(--slate-200);
    font-size: 9px;
  }

  .statusbar-right {
    display: flex;
    align-items: center;
  }

  .status-nominal {
    font-family: var(--font-mono);
    font-size: 9px;
    font-weight: 600;
    color: var(--emerald-600);
    letter-spacing: 1px;
  }

  .status-idle {
    font-family: var(--font-mono);
    font-size: 9px;
    font-weight: 600;
    color: var(--amber-600);
    letter-spacing: 1px;
  }

  .status-error {
    font-family: var(--font-mono);
    font-size: 9px;
    font-weight: 600;
    color: var(--red-500);
    letter-spacing: 1px;
  }
</style>
