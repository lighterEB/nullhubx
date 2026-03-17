<script lang="ts">
  let { status = "stopped" } = $props();

  const statusConfig: Record<string, { bg: string; color: string; text: string }> = {
    running: { bg: "rgba(16, 185, 129, 0.12)", color: "var(--emerald-500)", text: "运行中" },
    stopped: { bg: "var(--slate-100)", color: "var(--slate-500)", text: "已停止" },
    starting: { bg: "rgba(99, 102, 241, 0.12)", color: "var(--indigo-500)", text: "启动中" },
    stopping: { bg: "rgba(99, 102, 241, 0.12)", color: "var(--indigo-500)", text: "停止中" },
    failed: { bg: "rgba(239, 68, 68, 0.12)", color: "var(--red-500)", text: "失败" },
    restarting: { bg: "rgba(245, 158, 11, 0.12)", color: "var(--amber-500)", text: "重启中" },
  };

  let config = $derived(statusConfig[status] || statusConfig.stopped);
</script>

<span
  class="status-badge"
  class:running={status === "running"}
  style="--bg: {config.bg}; --color: {config.color}"
>
  <span class="dot" class:pulse={status === "running"}></span>
  {config.text}
</span>

<style>
  .status-badge {
    display: inline-flex;
    align-items: center;
    gap: var(--spacing-sm);
    padding: var(--spacing-xs) var(--spacing-sm);
    border-radius: var(--radius-sm);
    background: var(--bg);
    font-family: var(--font-mono);
    font-size: 10px;
    font-weight: 600;
    color: var(--color);
    letter-spacing: 0.5px;
  }

  .dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: var(--color);
  }

  .running .dot {
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
</style>
