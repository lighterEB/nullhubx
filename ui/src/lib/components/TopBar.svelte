<script lang="ts">
  import { onMount } from "svelte";
  import { api } from "$lib/api/client";
  import LiveSync from "./LiveSync.svelte";

  let hubOk = $state(true);

  onMount(() => {
    async function check() {
      try {
        await api.getStatus();
        hubOk = true;
      } catch {
        hubOk = false;
      }
    }
    check();
    const interval = setInterval(check, 10000);
    return () => clearInterval(interval);
  });
</script>

<header class="topbar">
  <div class="topbar-right">
    <LiveSync connected={hubOk} />
  </div>
</header>

<style>
  .topbar {
    display: flex;
    align-items: center;
    justify-content: flex-end;
    padding: var(--spacing-md) var(--spacing-xl);
    background: var(--glass-bg);
    border-bottom: 1px solid var(--glass-border);
    backdrop-filter: blur(12px);
    -webkit-backdrop-filter: blur(12px);
    flex-shrink: 0;
  }

  .topbar-right {
    display: flex;
    align-items: center;
    gap: var(--spacing-lg);
  }
</style>
