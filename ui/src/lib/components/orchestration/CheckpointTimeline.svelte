<script lang="ts">
  let { checkpoints = [], selected = '', onSelect = (_id: string) => {} } = $props();

  function formatTime(ts: string | number) {
    if (!ts) return '';
    const d = typeof ts === 'number' ? new Date(ts * 1000) : new Date(ts);
    return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
  }
</script>

<div class="timeline">
  {#if checkpoints.length === 0}
    <div class="empty">No checkpoints</div>
  {/if}
  {#each checkpoints as cp, i}
    <button
      class="checkpoint"
      class:selected={cp.id === selected}
      onclick={() => onSelect(cp.id)}
    >
      <div class="dot-col">
        <span class="dot" class:selected={cp.id === selected}></span>
        {#if i < checkpoints.length - 1}
          <span class="line"></span>
        {/if}
      </div>
      <div class="cp-info">
        <span class="cp-version">v{cp.version ?? i + 1}</span>
        <span class="cp-step">{cp.step_name || cp.after_step || 'start'}</span>
        <span class="cp-time">{formatTime(cp.created_at)}</span>
      </div>
    </button>
  {/each}
</div>

<style>
  .timeline {
    display: flex;
    flex-direction: column;
    padding: 0.5rem 0;
  }

  .empty {
    padding: 2rem;
    text-align: center;
    color: rgba(148, 163, 184, 0.72);
    font-size: 0.8125rem;
    font-family: var(--font-mono);
  }

  .checkpoint {
    display: flex;
    align-items: stretch;
    gap: 0.75rem;
    padding: 0.2rem 0.25rem;
    background: none;
    border: none;
    color: rgba(226, 232, 240, 0.88);
    cursor: pointer;
    text-align: left;
    transition: background 0.15s ease;
    border-radius: var(--radius-lg);
  }

  .checkpoint:hover {
    background: rgba(12, 20, 35, 0.88);
  }

  .checkpoint.selected {
    background: rgba(34, 211, 238, 0.12);
  }

  .dot-col {
    display: flex;
    flex-direction: column;
    align-items: center;
    width: 20px;
    padding-top: 0.75rem;
    flex-shrink: 0;
    margin-left: 0.5rem;
  }
  .dot {
    width: 10px;
    height: 10px;
    border-radius: 50%;
    background: rgba(12, 20, 35, 0.96);
    border: 2px solid rgba(148, 163, 184, 0.6);
    flex-shrink: 0;
    transition: all 0.2s ease;
  }

  .dot.selected {
    background: var(--cyan-300);
    border-color: var(--cyan-300);
    box-shadow: 0 0 16px rgba(34, 211, 238, 0.28);
  }

  .line {
    flex: 1;
    width: 2px;
    background: linear-gradient(180deg, rgba(34, 211, 238, 0.24), rgba(59, 130, 246, 0));
    min-height: 12px;
  }

  .cp-info {
    display: flex;
    flex-direction: column;
    gap: 0.125rem;
    padding: 0.625rem 0.75rem 0.625rem 0;
    min-width: 0;
  }
  .cp-version {
    font-family: var(--font-mono);
    font-size: 0.75rem;
    font-weight: 700;
    color: var(--cyan-300);
  }

  .cp-step {
    font-size: 0.8125rem;
    color: var(--shell-text);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .cp-time {
    font-size: 0.6875rem;
    font-family: var(--font-mono);
    color: rgba(148, 163, 184, 0.72);
  }
</style>
