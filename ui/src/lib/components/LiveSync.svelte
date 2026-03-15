<script lang="ts">
  interface Props {
    connected: boolean;
  }

  let { connected }: Props = $props();
</script>

<div class="livesync" class:connected={connected}>
  <span class="livesync-dot"></span>
  <span class="livesync-text">LIVE SYNC</span>
</div>

<style>
  .livesync {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm);
    padding: var(--spacing-xs) var(--spacing-md);
    border-radius: var(--radius-lg);
    background: rgba(34, 197, 94, 0.1);
    border: 1px solid rgba(34, 197, 94, 0.2);
    transition: all var(--transition-base) ease;
  }

  .livesync:not(.connected) {
    background: rgba(239, 68, 68, 0.1);
    border-color: rgba(239, 68, 68, 0.2);
  }

  .livesync-dot {
    display: inline-block;
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: var(--status-error);
    box-shadow: 0 0 8px var(--status-error);
    transition: all var(--transition-base) ease;
  }

  .livesync.connected .livesync-dot {
    background: var(--status-running);
    animation: breathe 2s ease-in-out infinite;
  }

  .livesync-text {
    font-size: var(--font-size-sm);
    font-weight: 600;
    color: var(--text-secondary);
    text-transform: uppercase;
    letter-spacing: 1px;
  }

  .livesync.connected .livesync-text {
    color: var(--status-running);
  }

  @keyframes breathe {
    0%, 100% {
      box-shadow: 0 0 5px var(--status-running), 0 0 10px var(--status-running);
      opacity: 0.6;
    }
    50% {
      box-shadow: 0 0 15px var(--status-running), 0 0 30px var(--status-running);
      opacity: 1;
    }
  }
</style>