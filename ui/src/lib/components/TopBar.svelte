<script lang="ts">
  import { page } from "$app/stores";
  import { onMount, onDestroy } from "svelte";
  import { hubConnected } from "$lib/statusStore";
  import { t, i18n, type Locale } from "$lib/i18n/index.svelte";

  let currentPath = $derived($page.url.pathname);
  let showLangMenu = $state(false);

  let navItems = $derived([
    { href: "/", label: t("nav.dashboard") },
    { href: "/instances", label: t("nav.instances") },
    { href: "/resources", label: t("nav.resources") },
    { href: "/orchestration", label: t("nav.orchestration") },
    { href: "/settings", label: t("nav.settings") }
  ]);

  function isActive(href: string): boolean {
    if (href === "/") return currentPath === "/";
    return currentPath.startsWith(href);
  }

  function toggleLangMenu() {
    showLangMenu = !showLangMenu;
  }

  function setLocale(locale: Locale) {
    i18n.locale = locale;
    showLangMenu = false;
    // Persist to localStorage
    if (typeof window !== 'undefined') {
      localStorage.setItem('nullhubx-locale', locale);
    }
  }

  function getLocaleLabel(locale: Locale): string {
    return locale === 'zh-CN' ? '中文' : 'EN';
  }

  onMount(() => {
    // Restore locale from localStorage
    if (typeof window !== 'undefined') {
      const saved = localStorage.getItem('nullhubx-locale') as Locale | null;
      if (saved && (saved === 'zh-CN' || saved === 'en-US')) {
        i18n.locale = saved;
      }
    }
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
      <span class="sync-dot" class:pulse-dot={$hubConnected}></span>
      <span class="sync-label">{t("topbar.liveSync")}</span>
    </div>

    <!-- Language Switcher -->
    <div class="lang-switcher">
      <button class="lang-btn" onclick={toggleLangMenu}>
        {getLocaleLabel(i18n.locale)}
        <svg xmlns="http://www.w3.org/2000/svg" width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="6 9 12 15 18 9"/></svg>
      </button>
      {#if showLangMenu}
        <div class="lang-menu">
          <button
            class="lang-option"
            class:active={i18n.locale === 'zh-CN'}
            onclick={() => setLocale('zh-CN')}
          >
            中文
          </button>
          <button
            class="lang-option"
            class:active={i18n.locale === 'en-US'}
            onclick={() => setLocale('en-US')}
          >
            English
          </button>
        </div>
      {/if}
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
    min-width: 0;
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
    white-space: nowrap;
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

  .lang-switcher {
    position: relative;
  }

  .lang-btn {
    display: flex;
    align-items: center;
    gap: var(--spacing-xs);
    padding: var(--spacing-xs) var(--spacing-sm);
    background: var(--slate-100);
    border: 1px solid var(--slate-200);
    border-radius: var(--radius-md);
    font-family: var(--font-mono);
    font-size: var(--text-xs);
    font-weight: 600;
    color: var(--slate-600);
    cursor: pointer;
    transition: all var(--transition-fast);
  }

  .lang-btn:hover {
    background: var(--slate-200);
    border-color: var(--slate-300);
  }

  .lang-menu {
    position: absolute;
    top: calc(100% + 4px);
    right: 0;
    background: white;
    border: 1px solid var(--slate-200);
    border-radius: var(--radius-md);
    box-shadow: var(--shadow-lg);
    overflow: hidden;
    min-width: 100px;
  }

  .lang-option {
    display: block;
    width: 100%;
    padding: var(--spacing-sm) var(--spacing-md);
    background: none;
    border: none;
    font-family: var(--font-sans);
    font-size: var(--text-sm);
    color: var(--slate-600);
    text-align: left;
    cursor: pointer;
    transition: all var(--transition-fast);
  }

  .lang-option:hover {
    background: var(--slate-50);
  }

  .lang-option.active {
    background: var(--indigo-50);
    color: var(--indigo-600);
    font-weight: 500;
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

  .pulse-dot {
    animation: pulse 2s ease-in-out infinite;
  }

  @keyframes pulse {
    0%, 100% {
      box-shadow: 0 0 0 0 rgba(16, 185, 129, 0.4);
    }
    50% {
      box-shadow: 0 0 0 6px rgba(16, 185, 129, 0);
    }
  }

  @media (max-width: 1080px) {
    .topbar {
      padding: 0 var(--spacing-2xl);
    }

    .nav-tabs {
      gap: var(--spacing-lg);
    }
  }

  @media (max-width: 820px) {
    .topbar {
      padding: 0 var(--spacing-lg);
      gap: var(--spacing-sm);
    }

    .logo {
      letter-spacing: 1.5px;
    }

    .nav-tabs {
      flex: 1;
      overflow-x: auto;
      scrollbar-width: none;
      -ms-overflow-style: none;
    }

    .nav-tabs::-webkit-scrollbar {
      display: none;
    }

    .live-sync {
      display: none;
    }
  }

  @media (max-width: 620px) {
    .avatar {
      display: none;
    }

    .nav-tab {
      font-size: var(--text-xs);
      padding: var(--spacing-sm) 0;
    }
  }
</style>
