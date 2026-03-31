<script lang="ts">
  import StatusBadge from "./StatusBadge.svelte";
  import { api } from "$lib/api/client";
  import { t } from "$lib/i18n/index.svelte";
  import { toast } from "$lib/toastStore.svelte";

  let {
    component = "",
    name = "",
    version = "",
    status = "stopped",
    port = 0,
    onAction = () => {},
  } = $props();

  let loading = $state(false);
  let localStatus = $state("stopped");
  let displayVersion = $derived(
    !version ? "-" : version.startsWith("v") || version.startsWith("dev-") ? version : `v${version}`,
  );

  $effect(() => {
    localStatus = status || "stopped";
  });

  async function start(e: Event) {
    e.preventDefault();
    e.stopPropagation();
    if (loading || localStatus === "starting" || localStatus === "restarting") return;
    loading = true;
    localStatus = "starting";
    try {
      await api.startInstance(component, name);
      onAction();
    } catch (err) {
      localStatus = "stopped";
      toast.error(err instanceof Error ? err.message : t("error.requestFailed"));
    } finally {
      loading = false;
    }
  }

  async function stop(e: Event) {
    e.preventDefault();
    e.stopPropagation();
    if (loading || localStatus === "stopping") return;
    loading = true;
    localStatus = "stopping";
    try {
      await api.stopInstance(component, name);
      onAction();
    } catch (err) {
      localStatus = "running";
      toast.error(err instanceof Error ? err.message : t("error.requestFailed"));
    } finally {
      loading = false;
    }
  }

  async function remove(e: Event) {
    e.preventDefault();
    e.stopPropagation();
    if (loading || localStatus === "starting" || localStatus === "stopping") return;
    const confirmMsg = t("instanceCard.confirmDelete")
      .replace("{component}", component)
      .replace("{name}", name);
    if (!confirm(confirmMsg)) return;
    loading = true;
    try {
      await api.deleteInstance(component, name);
      onAction();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("error.requestFailed"));
    } finally {
      loading = false;
    }
  }

  const colorMap: Record<string, "indigo" | "violet" | "amber"> = {
    nullclaw: "indigo",
    nullboiler: "violet",
    nulltickets: "amber",
  };

  const iconMap: Record<string, string> = {
    nullclaw: "⬡",
    nullboiler: "⊗",
    nulltickets: "⊞",
  };
</script>

<article class="instance-card">
  <a href="/instances/{component}/{name}" class="card-link">
    <div class="accent-bar {colorMap[component] || 'indigo'}"></div>

    <div class="card-top">
      <div class="icon-box {colorMap[component] || 'indigo'}">
        {iconMap[component] || "◈"}
      </div>
      <StatusBadge status={localStatus} />
    </div>

    <h3 class="card-name">{name}</h3>

    <div class="card-meta">
      <span class="component-tag">{component}</span>
      <span class="version">{displayVersion}</span>
    </div>

    {#if localStatus === "running" && port > 0}
      <div class="gateway-info">
        <span class="gateway-label">{t("instanceCard.gateway")}:</span>
        <code class="gateway-addr">127.0.0.1:{port}</code>
      </div>
    {/if}
  </a>

  <div class="card-actions">
    {#if localStatus === "running" || localStatus === "stopping"}
      <button class="control-btn secondary btn-stop" onclick={stop} disabled={loading || localStatus === "stopping"}>
        {loading || localStatus === "stopping" ? t("instanceCard.stopping") : t("instanceCard.stop")}
      </button>
    {:else}
      <button
        class="control-btn primary btn-start"
        onclick={start}
        disabled={loading || localStatus === "starting" || localStatus === "restarting"}
      >
        {loading || localStatus === "starting" || localStatus === "restarting"
          ? t("instanceCard.starting")
          : t("instanceCard.start")}
      </button>
    {/if}
    <button
      class="control-btn danger btn-delete"
      onclick={remove}
      disabled={loading || localStatus === "starting" || localStatus === "stopping"}
    >
      {t("instanceCard.delete")}
    </button>
  </div>
</article>

<style>
  .instance-card {
    position: relative;
    display: flex;
    flex-direction: column;
    gap: var(--spacing-md);
    padding: var(--spacing-xl);
    padding-left: calc(var(--spacing-xl) + 3px);
    background: linear-gradient(180deg, rgba(255, 255, 255, 0.84), rgba(245, 249, 255, 0.74));
    border: 1px solid rgba(141, 154, 178, 0.2);
    border-radius: var(--radius-lg);
    box-shadow: var(--shadow-sm);
    transition:
      background-color var(--transition-base),
      border-color var(--transition-base),
      box-shadow var(--transition-base),
      transform var(--transition-base);
    overflow: hidden;
    backdrop-filter: blur(18px);
  }

  .instance-card:hover {
    transform: translateY(-3px);
    box-shadow: var(--shadow-md), 0 0 0 1px rgba(34, 211, 238, 0.08);
    border-color: rgba(34, 211, 238, 0.24);
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
    gap: var(--spacing-md);
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
    box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.2);
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

  .card-meta {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm);
    min-width: 0;
    flex-wrap: wrap;
  }

  .component-tag {
    font-family: var(--font-mono);
    font-size: 11px;
    font-weight: 500;
    padding: 5px 10px;
    border-radius: 999px;
    background: rgba(34, 211, 238, 0.08);
    color: var(--cyan-600);
    border: 1px solid rgba(34, 211, 238, 0.18);
    text-transform: uppercase;
    letter-spacing: 0.06em;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    max-width: 100%;
  }

  .version {
    font-family: var(--font-mono);
    font-size: var(--text-xs);
    color: var(--slate-500);
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .gateway-info {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm);
    padding: 10px 12px;
    background: rgba(34, 211, 238, 0.07);
    border: 1px solid rgba(34, 211, 238, 0.16);
    border-radius: var(--radius-md);
    min-width: 0;
  }

  .gateway-label {
    font-family: var(--font-mono);
    font-size: var(--text-xs);
    color: var(--slate-600);
    letter-spacing: 0.04em;
  }

  .gateway-addr {
    font-family: var(--font-mono);
    font-size: var(--text-xs);
    font-weight: 600;
    color: var(--cyan-500);
    background: none;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    min-width: 0;
  }

  .card-actions {
    display: flex;
    gap: var(--spacing-sm);
    margin-top: auto;
  }

  .btn-start,
  .btn-stop {
    flex: 1;
  }

  .btn-stop {
    background: rgba(255, 255, 255, 0.84);
  }

  .btn-delete {
    min-width: 92px;
  }

  @media (max-width: 640px) {
    .instance-card {
      padding: var(--spacing-lg);
      padding-left: calc(var(--spacing-lg) + 3px);
    }

    .card-name {
      letter-spacing: 1px;
      font-size: var(--text-base);
    }

    .card-actions {
      flex-direction: column;
    }
  }
</style>
