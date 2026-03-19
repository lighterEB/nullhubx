<script lang="ts">
  import { api } from "$lib/api/client";

  let {
    name = "",
    displayName = "",
    description = "",
    alpha = false,
    installed = false,
    standalone = false,
    instanceCount = 0,
  } = $props();

  let importing = $state(false);
  let imported = $state(false);
  let comingSoon = $derived(alpha && !installed && !standalone);

  async function handleImport(e: MouseEvent) {
    e.preventDefault();
    e.stopPropagation();
    importing = true;
    try {
      await api.importInstance(name);
      imported = true;
      standalone = false;
      installed = true;
      instanceCount = 1;
    } catch (err) {
      console.error("Import failed:", err);
    } finally {
      importing = false;
    }
  }

  const iconMap: Record<string, string> = {
    nullclaw: "⬡",
    nullboiler: "⊗",
    nulltickets: "⊞",
  };

  const colorMap: Record<string, "indigo" | "violet" | "amber"> = {
    nullclaw: "indigo",
    nullboiler: "violet",
    nulltickets: "amber",
  };
</script>

{#if comingSoon}
<div class="component-card disabled">
  <div class="accent-bar {colorMap[name] || 'indigo'}"></div>

  <div class="card-top">
    <div class="icon-box {colorMap[name] || 'indigo'}">
      {iconMap[name] || "◈"}
    </div>
    <div class="badges">
      <span class="alpha-badge">ALPHA</span>
      <span class="badge badge-slate">COMING SOON</span>
    </div>
  </div>

  <h3 class="card-name">{displayName}</h3>
  <p class="card-description">{description}</p>

  <div class="card-footer">
    <div class="tag-row">
      <span class="tag">{name === "nullboiler" ? "orchestrator" : "tracker"}</span>
      <span class="tag">{name === "nullboiler" ? "dag" : "api"}</span>
    </div>
    <button class="btn-notify" disabled>
      Notify me
    </button>
  </div>
</div>
{:else}
<article class="component-card featured">
  <a href="/hub/{name}" class="card-link">
    <div class="accent-bar {colorMap[name] || 'indigo'}"></div>

    <div class="card-top">
      <div class="icon-box {colorMap[name] || 'indigo'}">
        {iconMap[name] || "◈"}
      </div>
      <div class="badges">
        {#if imported}
          <span class="import-badge">IMPORTED</span>
        {:else if standalone}
          <span class="instance-badge">STANDALONE</span>
        {:else if installed}
          <span class="instance-badge">{instanceCount} instance{instanceCount !== 1 ? "s" : ""}</span>
        {:else}
          <span class="import-badge">AVAILABLE</span>
        {/if}
      </div>
    </div>

    <h3 class="card-name">{displayName}</h3>
    <p class="card-description">{description}</p>
  </a>

  <div class="card-footer">
    <div class="tag-row">
      <span class="tag">runtime</span>
      <span class="tag">stable</span>
      <span class="tag">v2.4.1</span>
    </div>
    {#if !installed && !standalone}
      <span class="btn-install passive">Install →</span>
    {:else if standalone && !imported}
      <button class="btn-install" onclick={handleImport} disabled={importing}>
        {importing ? "Importing..." : "Import →"}
      </button>
    {:else}
      <div class="installed-status">
        <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="color: var(--emerald-500)"><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><polyline points="22 4 12 14.01 9 11.01"/></svg>
        <span>Installed</span>
      </div>
    {/if}
  </div>
</article>
{/if}

<style>
  .component-card {
    position: relative;
    display: flex;
    flex-direction: column;
    gap: 12px;
    padding: var(--spacing-xl);
    padding-left: calc(var(--spacing-xl) + 3px);
    background: white;
    border-radius: var(--radius-lg);
    text-decoration: none;
    color: inherit;
    transition: all var(--transition-base);
    overflow: hidden;
  }

  .component-card.featured {
    border: 1px solid var(--indigo-200);
    box-shadow: var(--shadow-indigo);
  }

  .component-card:not(.featured) {
    border: 1px solid var(--slate-200);
    box-shadow: var(--shadow-sm);
  }

  .component-card:not(.disabled):hover {
    transform: translateY(-3px);
    box-shadow: var(--shadow-md);
  }

  .component-card.disabled {
    opacity: 0.72;
    cursor: default;
    pointer-events: none;
  }

  .accent-bar {
    position: absolute;
    left: 0;
    top: 0;
    bottom: 0;
    width: 3px;
    background: linear-gradient(to bottom, var(--indigo-500), var(--indigo-600));
  }

  .accent-bar.violet {
    background: linear-gradient(to bottom, var(--violet-500), color-mix(in srgb, var(--violet-500) 75%, black));
  }

  .accent-bar.amber {
    background: linear-gradient(to bottom, var(--amber-500), var(--amber-600));
  }

  .card-top {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
  }

  .card-link {
    display: flex;
    flex-direction: column;
    gap: 12px;
    text-decoration: none;
    color: inherit;
  }

  .icon-box {
    width: 36px;
    height: 36px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 18px;
    border-radius: var(--radius-md);
    background: var(--indigo-50);
    border: 1px solid var(--indigo-200);
    color: var(--indigo-600);
  }

  .icon-box.violet {
    background: rgba(139, 92, 246, 0.1);
    border-color: rgba(139, 92, 246, 0.2);
    color: var(--violet-500);
  }

  .icon-box.amber {
    background: rgba(245, 158, 11, 0.1);
    border-color: rgba(245, 158, 11, 0.2);
    color: var(--amber-500);
  }

  .badges {
    display: flex;
    gap: var(--spacing-xs);
    align-items: center;
  }

  .alpha-badge {
    font-family: var(--font-mono);
    font-size: 10px;
    font-weight: 700;
    padding: var(--spacing-xs) var(--spacing-sm);
    border-radius: var(--radius-sm);
    background: rgba(245, 158, 11, 0.15);
    color: var(--amber-600);
    letter-spacing: 0.5px;
  }

  .import-badge {
    font-family: var(--font-mono);
    font-size: 10px;
    font-weight: 700;
    padding: var(--spacing-xs) var(--spacing-sm);
    border-radius: var(--radius-sm);
    background: var(--indigo-600);
    color: white;
    letter-spacing: 0.5px;
  }

  .instance-badge {
    font-family: var(--font-mono);
    font-size: 10px;
    font-weight: 500;
    padding: var(--spacing-xs) var(--spacing-sm);
    border-radius: var(--radius-sm);
    background: var(--slate-100);
    color: var(--slate-600);
  }

  .import-btn {
    font-family: var(--font-mono);
    font-size: 10px;
    font-weight: 700;
    padding: var(--spacing-xs) var(--spacing-sm);
    border-radius: var(--radius-sm);
    background: var(--indigo-600);
    color: white;
    border: none;
    cursor: pointer;
    letter-spacing: 0.5px;
  }

  .import-btn:hover:not(:disabled) {
    background: var(--indigo-700);
  }

  .import-btn:disabled {
    opacity: 0.6;
  }

  .card-name {
    font-family: var(--font-mono);
    font-size: var(--text-lg);
    font-weight: 700;
    color: var(--slate-900);
    letter-spacing: 2px;
    margin: 0;
  }

  .disabled .card-name {
    color: var(--slate-700);
  }

  .card-description {
    font-family: var(--font-sans);
    font-size: var(--text-sm);
    color: var(--slate-500);
    line-height: 1.8;
    margin: 0;
  }

  .disabled .card-description {
    color: var(--slate-400);
  }

  .card-footer {
    margin-top: auto;
    display: flex;
    flex-direction: column;
    gap: 12px;
  }

  .tag-row {
    display: flex;
    gap: var(--spacing-xs);
    flex-wrap: wrap;
  }

  .tag {
    font-family: var(--font-mono);
    font-size: 10px;
    font-weight: 500;
    padding: var(--spacing-xs) var(--spacing-sm);
    border-radius: var(--radius-sm);
    background: var(--indigo-50);
    color: var(--indigo-500);
    border: 1px solid var(--indigo-200);
  }

  .disabled .tag {
    background: var(--slate-100);
    color: var(--slate-500);
    border-color: var(--slate-200);
  }

  .btn-install {
    width: 100%;
    padding: var(--spacing-md);
    background: var(--indigo-600);
    color: white;
    font-family: var(--font-mono);
    font-size: var(--text-sm);
    font-weight: 600;
    letter-spacing: 1.5px;
    border: none;
    border-radius: var(--radius-md);
    cursor: pointer;
    transition: all var(--transition-fast);
  }

  .btn-install.passive {
    cursor: default;
    user-select: none;
  }

  .btn-install:hover:not(:disabled) {
    background: var(--indigo-700);
    box-shadow: var(--shadow-indigo);
    transform: translateY(-1px);
  }

  .btn-install:active:not(:disabled) {
    transform: translateY(0) scale(0.98);
  }

  .btn-install:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  .btn-notify {
    width: 100%;
    padding: var(--spacing-md);
    background: var(--slate-100);
    color: var(--slate-500);
    font-family: var(--font-sans);
    font-size: var(--text-sm);
    font-weight: 500;
    border: 1px solid var(--slate-200);
    border-radius: var(--radius-md);
    cursor: not-allowed;
  }

  .installed-status {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm);
    padding: var(--spacing-md);
    background: rgba(16, 185, 129, 0.08);
    border-radius: var(--radius-md);
    font-family: var(--font-sans);
    font-size: var(--text-sm);
    font-weight: 500;
    color: var(--emerald-600);
  }

  @media (max-width: 640px) {
    .component-card {
      padding: var(--spacing-lg);
      padding-left: calc(var(--spacing-lg) + 3px);
    }

    .card-name {
      letter-spacing: 1px;
      font-size: var(--text-base);
    }
  }
</style>
