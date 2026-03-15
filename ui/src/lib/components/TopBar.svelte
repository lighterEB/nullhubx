<script lang="ts">
  import { onMount } from "svelte";
  import { browser } from "$app/environment";
  import { api } from "$lib/api/client";
  import LiveSync from "./LiveSync.svelte";

  let hubOk = $state(true);
  let theme = $state<"dark" | "light">("dark");

  onMount(() => {
    // 加载保存的主题
    if (browser) {
      const saved = localStorage.getItem("nullhubx-theme") as "dark" | "light" | null;
      if (saved) {
        theme = saved;
        document.documentElement.setAttribute("data-theme", saved);
      }
    }

    // 检查 Hub 状态
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

  function toggleTheme() {
    theme = theme === "dark" ? "light" : "dark";
    document.documentElement.setAttribute("data-theme", theme);
    if (browser) {
      localStorage.setItem("nullhubx-theme", theme);
    }
  }
</script>

<header class="topbar">
  <div class="topbar-right">
    <LiveSync connected={hubOk} />
    <button class="theme-toggle" onclick={toggleTheme} title="切换主题">
      {#if theme === "dark"}
        <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="4"></circle><path d="M12 2v2"></path><path d="M12 20v2"></path><path d="m4.93 4.93 1.41 1.41"></path><path d="m17.66 17.66 1.41 1.41"></path><path d="M2 12h2"></path><path d="M20 12h2"></path><path d="m6.34 17.66-1.41 1.41"></path><path d="m19.07 4.93-1.41 1.41"></path></svg>
      {:else}
        <svg xmlns="http://www.w3.org/2000/svg" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3a6 6 0 0 0 9 9 9 9 0 1 1-9-9Z"></path></svg>
      {/if}
    </button>
  </div>
</header>

<style>
  .topbar {
    display: flex;
    align-items: center;
    justify-content: flex-end;
    padding: var(--spacing-md) var(--spacing-xl);
    background: var(--bg-surface);
    border-bottom: 1px solid var(--border);
    flex-shrink: 0;
  }

  .topbar-right {
    display: flex;
    align-items: center;
    gap: var(--spacing-lg);
  }

  .theme-toggle {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 36px;
    height: 36px;
    padding: 0;
    background: transparent;
    border: 1px solid var(--border);
    border-radius: var(--radius-md);
    color: var(--text-secondary);
    cursor: pointer;
    transition: all var(--transition-base);
  }

  .theme-toggle:hover {
    background: var(--bg-hover);
    border-color: var(--border-hover);
    color: var(--color-primary);
  }
</style>