<script lang="ts">
  import { page } from "$app/stores";
  import { onMount } from "svelte";
  import { hubConnected } from "$lib/statusStore";
  import { t, i18n, type Locale } from "$lib/i18n/index.svelte";
  import { setErrorLocale } from "$lib/api/errorMessages";

  let currentPath = $derived($page.url.pathname);
  let showLangMenu = $state(false);

  let navItems = $derived([
    { href: "/", label: t("nav.dashboard") },
    { href: "/instances", label: t("nav.instances") },
    { href: "/connections", label: t("nav.resources") },
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
    setErrorLocale(locale);
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
        setErrorLocale(saved);
      }
    }
  });
</script>

<header class="topbar">
  <a href="/" class="logo">
    <span class="logo-mark">NULLHUBX</span>
    <span class="logo-tag">CONTROL PLANE</span>
  </a>

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
    gap: var(--spacing-xl);
    background:
      linear-gradient(180deg, rgba(9, 16, 29, 0.96), rgba(13, 20, 36, 0.9));
    backdrop-filter: blur(20px);
    -webkit-backdrop-filter: blur(20px);
    border-bottom: 1px solid var(--shell-border);
    box-shadow: 0 12px 40px rgba(9, 16, 29, 0.26);
    z-index: 120;
  }

  .logo {
    text-decoration: none;
    display: inline-flex;
    flex-direction: column;
    gap: 2px;
    min-width: 164px;
  }

  .logo-mark {
    font-family: var(--font-display);
    font-size: var(--text-sm);
    font-weight: 600;
    color: var(--shell-text);
    letter-spacing: 0.22em;
  }

  .logo-tag {
    font-family: var(--font-mono);
    font-size: 11px;
    color: var(--shell-muted);
    letter-spacing: 0.16em;
  }

  .nav-tabs {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm);
    min-width: 0;
    padding: 6px;
    border-radius: 999px;
    border: 1px solid rgba(120, 150, 204, 0.18);
    background: rgba(17, 24, 39, 0.46);
    box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.02);
  }

  .nav-tab {
    font-family: var(--font-sans);
    font-size: var(--text-sm);
    font-weight: 500;
    color: var(--shell-muted);
    text-decoration: none;
    padding: 10px 14px;
    border-radius: 999px;
    border: 1px solid transparent;
    transition: all var(--transition-fast);
    letter-spacing: 0.01em;
    white-space: nowrap;
  }

  .nav-tab:hover {
    color: var(--shell-text);
    background: rgba(34, 211, 238, 0.06);
  }

  .nav-tab.active {
    color: var(--shell-text);
    border-color: rgba(34, 211, 238, 0.24);
    background: linear-gradient(135deg, rgba(34, 211, 238, 0.12), rgba(139, 92, 246, 0.08));
    box-shadow: var(--glow-cyan);
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
    box-shadow: 0 0 16px rgba(16, 185, 129, 0.35);
  }

  .sync-label {
    font-family: var(--font-sans);
    font-size: var(--text-xs);
    font-weight: 500;
    color: var(--shell-text-dim);
    letter-spacing: 0.04em;
  }

  .lang-switcher {
    position: relative;
  }

  .lang-btn {
    display: flex;
    align-items: center;
    gap: var(--spacing-xs);
    padding: 8px 10px;
    background: rgba(255, 255, 255, 0.03);
    border: 1px solid rgba(120, 150, 204, 0.18);
    border-radius: var(--radius-md);
    font-family: var(--font-sans);
    font-size: var(--text-xs);
    font-weight: 500;
    color: var(--shell-text-dim);
    cursor: pointer;
    transition: all var(--transition-fast);
  }

  .lang-btn:hover {
    color: var(--shell-text);
    border-color: rgba(34, 211, 238, 0.22);
    box-shadow: var(--glow-cyan);
  }

  .lang-menu {
    position: absolute;
    top: calc(100% + 4px);
    right: 0;
    background: rgba(13, 20, 36, 0.96);
    border: 1px solid var(--shell-border-strong);
    border-radius: var(--radius-md);
    box-shadow: var(--shadow-lg), var(--glow-cyan);
    overflow: hidden;
    min-width: 100px;
    backdrop-filter: blur(18px);
  }

  .lang-option {
    display: block;
    width: 100%;
    padding: var(--spacing-sm) var(--spacing-md);
    background: none;
    border: none;
    font-family: var(--font-sans);
    font-size: var(--text-sm);
    color: var(--shell-text-dim);
    text-align: left;
    cursor: pointer;
    transition: all var(--transition-fast);
  }

  .lang-option:hover {
    background: rgba(34, 211, 238, 0.08);
    color: var(--shell-text);
  }

  .lang-option.active {
    background: linear-gradient(135deg, rgba(34, 211, 238, 0.12), rgba(139, 92, 246, 0.1));
    color: var(--shell-text);
    font-weight: 500;
  }

  .avatar {
    width: 32px;
    height: 32px;
    display: flex;
    align-items: center;
    justify-content: center;
    background: rgba(255, 255, 255, 0.04);
    border: 1px solid rgba(120, 150, 204, 0.18);
    border-radius: 50%;
    color: var(--shell-text-dim);
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

    .logo {
      min-width: 136px;
    }
  }

  @media (max-width: 820px) {
    .topbar {
      padding: 0 var(--spacing-lg);
      gap: var(--spacing-sm);
    }

    .logo {
      min-width: 112px;
    }

    .logo-tag {
      display: none;
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
      padding: 8px 10px;
    }
  }
</style>
