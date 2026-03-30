<script lang="ts">
  import { runningCount, hubVersion, statusError } from "$lib/statusStore";
  import { t } from "$lib/i18n/index.svelte";

  let error = $derived($statusError !== null);
</script>

<footer class="statusbar">
  <div class="statusbar-left">
    <span class="status-item">NULLHUBX <span class="status-value">v{$hubVersion}</span></span>
    <span class="divider">|</span>
    <span class="status-item">{t("statusBar.instances")} <span class="status-value">{$runningCount} {t("statusBar.running")}</span></span>
  </div>
  <div class="statusbar-right">
    {#if error}
      <span class="status-error">{t("statusBar.connectionError")}</span>
    {:else if $runningCount > 0}
      <span class="status-nominal">{t("statusBar.operational")}</span>
    {:else}
      <span class="status-idle">{t("statusBar.idle")}</span>
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
    background: linear-gradient(180deg, rgba(10, 16, 29, 0.95), rgba(7, 12, 22, 0.98));
    border-top: 1px solid var(--shell-border);
    box-shadow: 0 -10px 32px rgba(9, 16, 29, 0.2);
    z-index: 120;
    overflow: hidden;
    backdrop-filter: blur(18px);
  }

  .statusbar-left {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm);
  }

  .status-item {
    font-family: var(--font-mono);
    font-size: 11px;
    font-weight: 500;
    color: var(--shell-muted);
    letter-spacing: 0.08em;
  }

  .status-value {
    color: var(--shell-text);
    font-weight: 600;
  }

  .divider {
    color: rgba(123, 138, 167, 0.6);
    font-size: 10px;
  }

  .statusbar-right {
    display: flex;
    align-items: center;
  }

  .status-nominal {
    font-family: var(--font-mono);
    font-size: 11px;
    font-weight: 600;
    color: var(--emerald-600);
    letter-spacing: 0.08em;
    text-shadow: 0 0 14px rgba(16, 185, 129, 0.28);
  }

  .status-idle {
    font-family: var(--font-mono);
    font-size: 11px;
    font-weight: 600;
    color: var(--amber-600);
    letter-spacing: 0.08em;
  }

  .status-error {
    font-family: var(--font-mono);
    font-size: 11px;
    font-weight: 600;
    color: var(--red-500);
    letter-spacing: 0.08em;
    text-shadow: 0 0 14px rgba(244, 63, 94, 0.2);
  }

  @media (max-width: 760px) {
    .statusbar {
      padding: 0 var(--spacing-lg);
    }

    .status-item:first-child,
    .divider {
      display: none;
    }
  }

  @media (max-width: 560px) {
    .statusbar-left {
      display: none;
    }
  }
</style>
