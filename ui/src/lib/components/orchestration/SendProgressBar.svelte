<script lang="ts">
  let { current = 0, total = 0, label = '' } = $props();
  let pct = $derived(total > 0 ? Math.round((current / total) * 100) : 0);
</script>

<div class="progress-wrap">
  {#if label}
    <span class="progress-label">{label}</span>
  {/if}
  <div class="progress-track">
    <div class="progress-fill" style="width: {pct}%"></div>
  </div>
  <span class="progress-text">{current}/{total}</span>
</div>

<style>
  .progress-wrap {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    font-size: 0.6875rem;
    font-family: var(--font-mono);
    color: rgba(148, 163, 184, 0.72);
  }

  .progress-label {
    text-transform: uppercase;
    letter-spacing: 0.06em;
    white-space: nowrap;
  }

  .progress-track {
    flex: 1;
    min-width: 40px;
    height: 6px;
    background: rgba(12, 20, 35, 0.84);
    border-radius: 999px;
    overflow: hidden;
    border: 1px solid rgba(96, 165, 250, 0.14);
  }

  .progress-fill {
    height: 100%;
    background: linear-gradient(90deg, rgba(34, 211, 238, 0.92), rgba(59, 130, 246, 0.84));
    border-radius: 999px;
    transition: width 0.3s ease;
    box-shadow: 0 0 14px rgba(34, 211, 238, 0.2);
  }

  .progress-text {
    white-space: nowrap;
    min-width: 2.5em;
    text-align: right;
  }
</style>
