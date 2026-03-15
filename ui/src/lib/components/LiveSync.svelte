<script lang="ts">
  interface Props {
    connected: boolean;
  }

  let { connected }: Props = $props();
</script>

<div class="livesync" class:connected={connected}>
  <span class="livesync-dot"></span>
  <span class="livesync-text">{connected ? "LIVE" : "OFFLINE"}</span>
</div>

<style>
  .livesync {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm);
    padding: var(--spacing-xs) var(--spacing-md);
    border-radius: var(--radius-md);
    background: var(--bg-elevated);
    border: 1px solid var(--border);
    transition: all var(--transition-base);
  }

  .livesync-dot {
    display: inline-block;
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: var(--status-error);
    transition: all var(--transition-base);
  }

  .livesync.connected .livesync-dot {
    background: var(--status-running);
    animation: breathe 2s ease-in-out infinite;
  }

  .livesync-text {
    font-size: var(--text-xs);
    font-weight: 600;
    color: var(--text-secondary);
    text-transform: uppercase;
    letter-spacing: 0.5px;
  }

  .livesync.connected .livesync-text {
    color: var(--status-running);
  }

  @keyframes breathe {
    0%, 100% {
      box-shadow: 0 0 4px var(--status-running);
      opacity: 0.7;
    }
    50% {
      box-shadow: 0 0 12px var(--status-running);
      opacity: 1;
    }
  }
</style>