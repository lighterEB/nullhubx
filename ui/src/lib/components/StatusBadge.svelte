<script lang="ts">
  let { status = "stopped" } = $props();

  const statusConfig: Record<string, { color: string; bg: string }> = {
    running: { color: "var(--status-running)", bg: "var(--badge-success)" },
    stopped: { color: "var(--status-stopped)", bg: "var(--bg-elevated)" },
    starting: { color: "var(--status-warning)", bg: "var(--badge-warning)" },
    stopping: { color: "var(--status-warning)", bg: "var(--badge-warning)" },
    failed: { color: "var(--status-error)", bg: "rgba(239, 68, 68, 0.1)" },
    restarting: { color: "var(--status-warning)", bg: "var(--badge-warning)" },
  };

  let config = $derived(statusConfig[status] || statusConfig.stopped);
</script>

<span
  class="status-badge"
  class:running={status === "running"}
  style="--status-color: {config.color}; --status-bg: {config.bg}"
>
  <span class="status-indicator"></span>
  {status}
</span>

<style>
  .status-badge {
    display: inline-flex;
    align-items: center;
    gap: var(--spacing-sm);
    padding: var(--spacing-xs) var(--spacing-sm);
    border-radius: var(--radius-sm);
    font-size: var(--text-xs);
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    background: var(--status-bg);
    color: var(--status-color);
  }

  .status-indicator {
    display: inline-block;
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: var(--status-color);
  }

  .status-badge.running .status-indicator {
    box-shadow: 0 0 6px var(--status-running);
  }
</style>