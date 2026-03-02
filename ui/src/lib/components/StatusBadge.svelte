<script lang="ts">
  let { status = 'stopped' } = $props();

  const colors: Record<string, string> = {
    running: 'var(--success)',
    stopped: 'var(--text-muted)',
    starting: 'var(--warning)',
    failed: 'var(--error)',
    restarting: 'var(--warning)'
  };
</script>

<span class="badge" style="--badge-color: {colors[status] || 'var(--text-muted)'}">
  {status}
</span>

<style>
  .badge {
    display: inline-flex;
    align-items: center;
    gap: 0.375rem;
    padding: 0.125rem 0.5rem;
    border-radius: var(--radius-sm);
    font-size: 0.75rem;
    font-weight: 500;
    text-transform: capitalize;
    background: color-mix(in srgb, var(--badge-color) 15%, transparent);
    color: var(--badge-color);
  }
  .badge::before {
    content: '';
    width: 6px;
    height: 6px;
    border-radius: 50%;
    background: var(--badge-color);
  }
</style>
