<script lang="ts">
  import { tick } from 'svelte';

  let { events = [] } = $props<{ events: { type: string; data: any; timestamp?: string | number }[] }>();
  let container: HTMLElement;
  let autoScroll = $state(true);

  const typeColors: Record<string, string> = {
    // NullBoiler event types
    values: 'var(--accent)',
    updates: 'var(--accent)',
    task_start: 'var(--accent)',
    task_result: 'var(--success)',
    debug: 'var(--fg-dim)',
    ui_message: 'var(--accent)',
    ui_message_delete: 'var(--warning)',
    // UI-friendly aliases
    state_update: 'var(--accent)',
    step_started: 'var(--accent)',
    step_completed: 'var(--success)',
    step_failed: 'var(--error)',
    agent_event: 'var(--accent)',
    interrupted: 'var(--warning)',
    run_completed: 'var(--success)',
    run_failed: 'var(--error)',
    send_progress: 'var(--accent)',
    message: 'var(--fg-dim)',
  };

  function formatTime(ts: string | number | undefined) {
    if (!ts) return '';
    const d = typeof ts === 'number' ? new Date(ts * 1000) : new Date(ts);
    return d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
  }

  function summarize(data: any): string {
    if (!data) return '';
    if (typeof data === 'string') return data;
    if (data.step) return `step: ${data.step}`;
    if (data.node_id) return `node: ${data.node_id}`;
    if (data.message) return data.message;
    const str = JSON.stringify(data);
    return str.length > 80 ? str.slice(0, 80) + '...' : str;
  }

  $effect(() => {
    events.length;
    if (autoScroll && container) {
      void tick().then(() => {
        container.scrollTop = container.scrollHeight;
      });
    }
  });
</script>

<div class="event-log">
  <div class="log-header">
    <span>Event Log</span>
    <label class="auto-scroll">
      <input type="checkbox" bind:checked={autoScroll} />
      Auto-scroll
    </label>
  </div>
  <div class="log-content" bind:this={container}>
    {#if events.length === 0}
      <div class="log-empty">No events yet</div>
    {/if}
    {#each events as ev}
      <div class="event-row">
        <span class="ev-time">{formatTime(ev.timestamp)}</span>
        <span
          class="ev-type"
          style="--type-color: {typeColors[ev.type] || 'var(--fg-dim)'}"
        >{ev.type}</span>
        <span class="ev-summary">{summarize(ev.data)}</span>
      </div>
    {/each}
  </div>
</div>

<style>
  .event-log {
    display: flex;
    flex-direction: column;
    height: 100%;
    min-height: 200px;
    background:
      linear-gradient(180deg, rgba(7, 12, 22, 0.94), rgba(10, 17, 31, 0.92)),
      radial-gradient(circle at top right, rgba(34, 211, 238, 0.08), transparent 36%);
    border: 1px solid rgba(96, 165, 250, 0.14);
    border-radius: var(--radius-xl);
    box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.03);
  }

  .log-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 0.625rem 1rem;
    border-bottom: 1px solid rgba(96, 165, 250, 0.12);
    font-size: 0.8125rem;
    color: var(--cyan-300);
    text-transform: uppercase;
    letter-spacing: 0.08em;
    font-weight: 700;
  }

  .log-content {
    flex: 1;
    overflow-y: auto;
    padding: 0.65rem;
    font-family: var(--font-mono);
    font-size: 0.75rem;
    line-height: 1.5;
  }

  .log-empty {
    color: rgba(148, 163, 184, 0.72);
    text-align: center;
    padding: 2rem;
    font-style: italic;
    opacity: 0.7;
  }

  .event-row {
    display: flex;
    align-items: baseline;
    gap: 0.625rem;
    padding: 0.35rem 0.55rem;
    border-radius: var(--radius-md);
  }

  .event-row:hover {
    background: rgba(12, 20, 35, 0.88);
  }

  .ev-time {
    color: rgba(148, 163, 184, 0.72);
    white-space: nowrap;
    font-size: 0.6875rem;
    min-width: 5em;
  }

  .ev-type {
    display: inline-block;
    padding: 0.125rem 0.375rem;
    border-radius: 999px;
    font-size: 0.625rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    white-space: nowrap;
    color: var(--type-color);
    background: color-mix(in srgb, var(--type-color) 14%, rgba(7, 12, 22, 0.94));
    border: 1px solid color-mix(in srgb, var(--type-color) 24%, transparent);
  }

  .ev-summary {
    color: rgba(226, 232, 240, 0.88);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    min-width: 0;
  }

  .auto-scroll {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    font-size: 0.6875rem;
    color: rgba(148, 163, 184, 0.72);
    cursor: pointer;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    font-weight: 400;
  }

  .auto-scroll input[type="checkbox"] {
    appearance: none;
    width: 12px;
    height: 12px;
    border: 1px solid rgba(96, 165, 250, 0.18);
    background: rgba(7, 12, 22, 0.92);
    border-radius: 3px;
    position: relative;
    cursor: pointer;
  }

  .auto-scroll input[type="checkbox"]:checked {
    background: rgba(34, 211, 238, 0.18);
    border-color: rgba(34, 211, 238, 0.4);
    box-shadow: inset 0 0 6px rgba(34, 211, 238, 0.22);
  }

  .auto-scroll input[type="checkbox"]:checked::after {
    content: "";
    position: absolute;
    top: 1px;
    left: 1px;
    width: 8px;
    height: 8px;
    background: var(--cyan-300);
    border-radius: 1px;
    box-shadow: 0 0 6px rgba(34, 211, 238, 0.28);
  }
</style>
