<script lang="ts">
  import { t } from "$lib/i18n/index.svelte";

  let { status = "stopped" } = $props();

  const statusConfig: Record<string, { bg: string; border: string; color: string; glow: string; textKey: string }> = {
    running: {
      bg: "rgba(16, 185, 129, 0.11)",
      border: "rgba(16, 185, 129, 0.22)",
      color: "var(--emerald-600)",
      glow: "0 0 18px rgba(16, 185, 129, 0.14)",
      textKey: "status.running",
    },
    stopped: {
      bg: "rgba(255, 255, 255, 0.72)",
      border: "rgba(141, 154, 178, 0.22)",
      color: "var(--slate-600)",
      glow: "none",
      textKey: "status.stopped",
    },
    starting: {
      bg: "rgba(34, 211, 238, 0.1)",
      border: "rgba(34, 211, 238, 0.22)",
      color: "var(--cyan-600)",
      glow: "0 0 18px rgba(34, 211, 238, 0.14)",
      textKey: "status.starting",
    },
    stopping: {
      bg: "rgba(141, 154, 178, 0.12)",
      border: "rgba(141, 154, 178, 0.22)",
      color: "var(--slate-600)",
      glow: "none",
      textKey: "status.stopping",
    },
    failed: {
      bg: "rgba(244, 63, 94, 0.1)",
      border: "rgba(244, 63, 94, 0.22)",
      color: "var(--red-600)",
      glow: "0 0 18px rgba(244, 63, 94, 0.12)",
      textKey: "status.failed",
    },
    restarting: {
      bg: "rgba(245, 158, 11, 0.1)",
      border: "rgba(245, 158, 11, 0.22)",
      color: "var(--amber-600)",
      glow: "0 0 18px rgba(245, 158, 11, 0.1)",
      textKey: "status.restarting",
    },
  };

  let config = $derived(statusConfig[status] || statusConfig.stopped);
  let statusText = $derived(t(config.textKey));
</script>

<span
  class="status-badge"
  class:pulse={status === "running" || status === "starting" || status === "restarting"}
  style="--bg: {config.bg}; --border-color: {config.border}; --color: {config.color}; --glow: {config.glow}"
>
  <span class="dot"></span>
  {statusText}
</span>

<style>
  .status-badge {
    display: inline-flex;
    align-items: center;
    gap: 7px;
    padding: 6px 10px;
    border-radius: 999px;
    background: var(--bg);
    border: 1px solid var(--border-color);
    font-family: var(--font-mono);
    font-size: 11px;
    font-weight: 600;
    color: var(--color);
    letter-spacing: 0.06em;
    box-shadow: var(--glow);
  }

  .dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: var(--color);
  }

  .pulse .dot {
    animation: pulse 2s ease-in-out infinite;
  }

  @keyframes pulse {
    0%, 100% {
      box-shadow: 0 0 0 0 color-mix(in srgb, var(--color) 42%, transparent);
    }
    50% {
      box-shadow: 0 0 0 6px color-mix(in srgb, var(--color) 0%, transparent);
    }
  }
</style>
