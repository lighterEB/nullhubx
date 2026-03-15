<script lang="ts">
  import { onMount } from "svelte";
  import { api } from "$lib/api/client";

  let status = $state<any>(null);

  onMount(async () => {
    try {
      status = await api.getStatus();
    } catch {
      // ignore
    }
  });
</script>

<footer class="statusbar">
  <div class="statusbar-left">
    <span class="status-item">NODE <span class="status-value">null-01</span></span>
    <span class="divider">|</span>
    <span class="status-item">REGION <span class="status-value">us-west-2</span></span>
    <span class="divider">|</span>
    <span class="status-item">STACK <span class="status-value">v0.4.2-beta</span></span>
  </div>
  <div class="statusbar-right">
    <span class="status-nominal">SYS NOMINAL</span>
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
</style>