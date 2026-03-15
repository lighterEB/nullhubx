<script lang="ts">
  import { page } from "$app/stores";
  import { onMount } from "svelte";
  import { browser } from "$app/environment";
  import { api } from "$lib/api/client";

  let hubOk = $state(true);
  let currentPath = $derived($page.url.pathname);

  const navItems = [
    { href: "/", label: "Status" },
    { href: "/dashboard", label: "Dashboard" },
    { href: "/install", label: "Components" },
    { href: "/providers", label: "Providers" },
    { href: "/channels", label: "Channels" },
  ];

  function isActive(href: string): boolean {
    if (href === "/") return currentPath === "/";
    return currentPath.startsWith(href);
  }

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
  <a href="/" class="logo">NULLHUBX</a>
  
  <nav class="nav-tabs">
    {#each navItems as item}
      <a 
        href={item.href} 
        class="nav-tab" 
        class:active={isActive(item.href)}
      >
        {item.label}
      </a>
    {/each}
  </nav>
  
  <div class="topbar-right">
    <div class="live-sync">
      <span class="sync-dot" class:pulse-dot={hubOk}></span>
      <span class="sync-label">LIVE SYNC</span>
    </div>
    <div class="avatar">
      <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M19 21v-2a4 4 0 0 0-4-4H9a4 4 0 0 0-4 4v2"/><circle cx="12" cy="7" r="4"/></svg>
    </div>
  </div>
</header>

<style>
  .topbar {
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    height: var(--topbar-height);
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 0 var(--spacing-5xl);
    background: rgba(255, 255, 255, 0.9);
    backdrop-filter: blur(12px);
    -webkit-backdrop-filter: blur(12px);
    border-bottom: 1px solid var(--slate-200);
    z-index: 100;
  }

  .logo {
    font-family: var(--font-mono);
    font-size: var(--text-base);
    font-weight: 700;
    color: var(--indigo-600);
    letter-spacing: 3px;
    text-decoration: none;
  }

  .nav-tabs {
    display: flex;
    align-items: center;
    gap: var(--spacing-xl);
  }

  .nav-tab {
    font-family: var(--font-mono);
    font-size: var(--text-sm);
    font-weight: 500;
    color: var(--slate-400);
    text-decoration: none;
    padding: var(--spacing-md) 0;
    border-bottom: 2px solid transparent;
    transition: all var(--transition-fast);
    letter-spacing: 0.5px;
  }

  .nav-tab:hover {
    color: var(--slate-600);
  }

  .nav-tab.active {
    color: var(--indigo-600);
    border-bottom-color: var(--indigo-600);
  }

  .topbar-right {
    display: flex;
    align-items: center;
    gap: var(--spacing-lg);
  }

  .live-sync {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm);
  }

  .sync-dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: var(--emerald-500);
  }

  .sync-label {
    font-family: var(--font-mono);
    font-size: var(--text-xs);
    font-weight: 600;
    color: var(--slate-500);
    letter-spacing: 1px;
  }

  .avatar {
    width: 32px;
    height: 32px;
    display: flex;
    align-items: center;
    justify-content: center;
    background: var(--slate-100);
    border: 1px solid var(--slate-200);
    border-radius: 50%;
    color: var(--slate-500);
  }

  @keyframes pulse {
    0%, 100% {
      box-shadow: 0 0 0 0 rgba(16, 185, 129, 0.4);
    }
    50% {
      box-shadow: 0 0 0 8px rgba(16, 185, 129, 0);
    }
  }

  .pulse-dot {
    animation: pulse 2s ease-in-out infinite;
  }
</style>