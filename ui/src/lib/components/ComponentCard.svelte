<script lang="ts">
  import { api } from "$lib/api/client";
  import { t } from "$lib/i18n/index.svelte";
  import { toast } from "$lib/toastStore.svelte";

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
      const message = err instanceof Error ? err.message : t("error.requestFailed");
      toast.error(t("hub.importFailed").replace("{error}", message));
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
      <span class="alpha-badge">{t("componentCard.alpha")}</span>
      <span class="badge badge-slate">{t("componentCard.comingSoon")}</span>
    </div>
  </div>

  <h3 class="card-name">{displayName}</h3>
  <p class="card-description">{description}</p>

  <div class="card-footer">
    <div class="tag-row">
      <span class="tag">{name === "nullboiler" ? t("componentCard.orchestrator") : t("componentCard.tracker")}</span>
      <span class="tag">{name === "nullboiler" ? t("componentCard.dag") : t("componentCard.api")}</span>
    </div>
    <button class="btn-notify" disabled>
      {t("componentCard.notify")}
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
          <span class="import-badge">{t("componentCard.imported")}</span>
        {:else if standalone}
          <span class="instance-badge">{t("componentCard.standalone")}</span>
        {:else if installed}
          <span class="instance-badge">{t("componentCard.instanceCount").replace("{count}", String(instanceCount))}</span>
        {:else}
          <span class="import-badge">{t("componentCard.available")}</span>
        {/if}
      </div>
    </div>

    <h3 class="card-name">{displayName}</h3>
    <p class="card-description">{description}</p>
  </a>

  <div class="card-footer">
    <div class="tag-row">
      <span class="tag">{t("componentCard.runtime")}</span>
      <span class="tag">{t("componentCard.stable")}</span>
      <span class="tag">v2.4.1</span>
    </div>
    {#if !installed && !standalone}
      <span class="control-btn primary btn-install passive">{t("componentCard.installCta")}</span>
    {:else if standalone && !imported}
      <button class="control-btn primary btn-install" onclick={handleImport} disabled={importing}>
        {importing ? t("componentCard.importing") : t("componentCard.importCta")}
      </button>
    {:else}
      <div class="installed-status">
        <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" style="color: var(--emerald-500)"><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"/><polyline points="22 4 12 14.01 9 11.01"/></svg>
        <span>{t("componentCard.installed")}</span>
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
    background: linear-gradient(180deg, rgba(255, 255, 255, 0.84), rgba(245, 249, 255, 0.74));
    border-radius: var(--radius-lg);
    text-decoration: none;
    color: inherit;
    transition: all var(--transition-base);
    overflow: hidden;
    backdrop-filter: blur(18px);
  }

  .component-card.featured {
    border: 1px solid rgba(34, 211, 238, 0.18);
    box-shadow: var(--shadow-sm), 0 0 0 1px rgba(34, 211, 238, 0.08);
  }

  .component-card:not(.featured) {
    border: 1px solid rgba(141, 154, 178, 0.2);
    box-shadow: var(--shadow-sm);
  }

  .component-card:not(.disabled):hover {
    transform: translateY(-3px);
    box-shadow: var(--shadow-md), 0 0 0 1px rgba(34, 211, 238, 0.08);
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
    min-width: 0;
  }

  .icon-box {
    width: 40px;
    height: 40px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 18px;
    border-radius: var(--radius-md);
    background: rgba(34, 211, 238, 0.08);
    border: 1px solid rgba(34, 211, 238, 0.18);
    color: var(--cyan-600);
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
    font-size: 11px;
    font-weight: 700;
    padding: 5px 10px;
    border-radius: 999px;
    background: rgba(245, 158, 11, 0.12);
    color: var(--amber-600);
    border: 1px solid rgba(245, 158, 11, 0.2);
    letter-spacing: 0.06em;
  }

  .import-badge {
    font-family: var(--font-mono);
    font-size: 11px;
    font-weight: 700;
    padding: 5px 10px;
    border-radius: 999px;
    background: rgba(34, 211, 238, 0.1);
    color: var(--cyan-600);
    border: 1px solid rgba(34, 211, 238, 0.18);
    letter-spacing: 0.06em;
  }

  .instance-badge {
    font-family: var(--font-mono);
    font-size: 11px;
    font-weight: 500;
    padding: 5px 10px;
    border-radius: 999px;
    background: rgba(255, 255, 255, 0.74);
    color: var(--slate-600);
    border: 1px solid rgba(141, 154, 178, 0.18);
  }

  .card-name {
    font-family: var(--font-display);
    font-size: var(--text-lg);
    font-weight: 600;
    color: var(--slate-900);
    letter-spacing: -0.02em;
    margin: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .disabled .card-name {
    color: var(--slate-700);
  }

  .card-description {
    font-family: var(--font-sans);
    font-size: var(--text-sm);
    color: var(--slate-600);
    line-height: 1.65;
    margin: 0;
    line-clamp: 3;
    display: -webkit-box;
    -webkit-line-clamp: 3;
    -webkit-box-orient: vertical;
    overflow: hidden;
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
    font-size: 11px;
    font-weight: 500;
    padding: 5px 10px;
    border-radius: 999px;
    background: rgba(255, 255, 255, 0.74);
    color: var(--slate-700);
    border: 1px solid rgba(141, 154, 178, 0.18);
  }

  .disabled .tag {
    background: var(--slate-100);
    color: var(--slate-500);
    border-color: var(--slate-200);
  }

  .btn-install {
    width: 100%;
    font-family: var(--font-sans);
    letter-spacing: 0.06em;
  }

  .btn-install.passive {
    cursor: default;
    user-select: none;
    pointer-events: none;
  }

  .btn-notify {
    width: 100%;
    padding: 12px 14px;
    background: rgba(255, 255, 255, 0.72);
    color: var(--slate-500);
    font-family: var(--font-sans);
    font-size: var(--text-sm);
    font-weight: 500;
    border: 1px solid rgba(141, 154, 178, 0.2);
    border-radius: var(--radius-md);
    cursor: not-allowed;
  }

  .installed-status {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm);
    padding: 12px 14px;
    background: rgba(16, 185, 129, 0.08);
    border: 1px solid rgba(16, 185, 129, 0.16);
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
