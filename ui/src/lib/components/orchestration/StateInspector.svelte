<script lang="ts">
  let { currentState = null, previousState = null } = $props<{ currentState: any; previousState?: any }>();

  let diffMode = $state(false);

  function escapeHtml(value: string): string {
    return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  }

  function syntaxHighlight(json: string): string {
    return json.replace(
      /("(\\u[\da-fA-F]{4}|\\[^u]|[^\\"])*"(\s*:)?|\b(true|false|null)\b|-?\d+(?:\.\d*)?(?:[eE][+-]?\d+)?)/g,
      (match) => {
        let cls = 'json-number';
        if (/^"/.test(match)) {
          cls = /:$/.test(match) ? 'json-key' : 'json-string';
        } else if (/true|false/.test(match)) {
          cls = 'json-boolean';
        } else if (/null/.test(match)) {
          cls = 'json-null';
        }
        return `<span class="${cls}">${escapeHtml(match)}</span>`;
      }
    );
  }

  function getDiff(curr: any, prev: any): { added: Set<string>; removed: Set<string>; changed: Set<string> } {
    const added = new Set<string>();
    const removed = new Set<string>();
    const changed = new Set<string>();
    if (!curr || !prev) return { added, removed, changed };
    const currKeys = Object.keys(curr);
    const prevKeys = Object.keys(prev);
    for (const k of currKeys) {
      if (!(k in prev)) added.add(k);
      else if (JSON.stringify(curr[k]) !== JSON.stringify(prev[k])) changed.add(k);
    }
    for (const k of prevKeys) {
      if (!(k in curr)) removed.add(k);
    }
    return { added, removed, changed };
  }

  let diff = $derived(getDiff(currentState, previousState));
  let formatted = $derived(currentState ? JSON.stringify(currentState, null, 2) : 'null');
  let highlighted = $derived(syntaxHighlight(formatted));
</script>

<div class="inspector">
  <div class="inspector-header">
    <span>State</span>
    {#if previousState}
      <button
        class="diff-toggle"
        class:active={diffMode}
        onclick={() => diffMode = !diffMode}
      >Diff</button>
    {/if}
  </div>
  <div class="inspector-body">
    {#if diffMode && previousState}
      <div class="diff-view">
        {#if diff.added.size > 0}
          <div class="diff-section added">
            <span class="diff-label">Added</span>
            {#each [...diff.added] as key}
              <div class="diff-line">+ {key}: {JSON.stringify(currentState[key])}</div>
            {/each}
          </div>
        {/if}
        {#if diff.changed.size > 0}
          <div class="diff-section changed">
            <span class="diff-label">Changed</span>
            {#each [...diff.changed] as key}
              <div class="diff-line old">- {key}: {JSON.stringify(previousState[key])}</div>
              <div class="diff-line new">+ {key}: {JSON.stringify(currentState[key])}</div>
            {/each}
          </div>
        {/if}
        {#if diff.removed.size > 0}
          <div class="diff-section removed">
            <span class="diff-label">Removed</span>
            {#each [...diff.removed] as key}
              <div class="diff-line">- {key}: {JSON.stringify(previousState[key])}</div>
            {/each}
          </div>
        {/if}
        {#if diff.added.size === 0 && diff.changed.size === 0 && diff.removed.size === 0}
          <div class="no-diff">No changes</div>
        {/if}
      </div>
    {:else}
      <!-- eslint-disable-next-line svelte/no-at-html-tags -->
      <pre class="json-pre">{@html highlighted}</pre>
    {/if}
  </div>
</div>

<style>
  .inspector {
    display: flex;
    flex-direction: column;
    height: 100%;
    background:
      linear-gradient(180deg, rgba(7, 12, 22, 0.94), rgba(10, 17, 31, 0.92)),
      radial-gradient(circle at top right, rgba(34, 211, 238, 0.08), transparent 36%);
    border: 1px solid rgba(96, 165, 250, 0.14);
    border-radius: var(--radius-xl);
    box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.03);
  }

  .inspector-header {
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

  .diff-toggle {
    padding: 0.25rem 0.625rem;
    border: 1px solid rgba(96, 165, 250, 0.16);
    border-radius: 999px;
    background: rgba(7, 12, 22, 0.84);
    color: rgba(148, 163, 184, 0.78);
    font-size: 0.6875rem;
    font-family: var(--font-mono);
    text-transform: uppercase;
    letter-spacing: 0.06em;
    cursor: pointer;
    transition: all 0.15s ease;
  }

  .diff-toggle:hover {
    border-color: rgba(34, 211, 238, 0.22);
    color: var(--shell-text);
  }

  .diff-toggle.active {
    color: var(--cyan-300);
    border-color: rgba(34, 211, 238, 0.28);
    background: rgba(34, 211, 238, 0.14);
    box-shadow: 0 0 18px rgba(34, 211, 238, 0.12);
  }

  .inspector-body {
    flex: 1;
    overflow: auto;
    padding: 1rem;
  }

  .json-pre {
    margin: 0;
    white-space: pre-wrap;
    word-break: break-all;
    font-family: var(--font-mono);
    font-size: 0.8125rem;
    line-height: 1.6;
    color: rgba(226, 232, 240, 0.88);
  }

  :global(.json-key) { color: var(--cyan-300); }
  :global(.json-string) { color: #86efac; }
  :global(.json-number) { color: #fbbf24; }
  :global(.json-boolean) { color: #c084fc; }
  :global(.json-null) { color: rgba(148, 163, 184, 0.78); }

  .diff-view {
    font-family: var(--font-mono);
    font-size: 0.8125rem;
    line-height: 1.6;
  }

  .diff-section {
    margin-bottom: 0.75rem;
  }

  .diff-label {
    display: block;
    font-size: 0.6875rem;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: rgba(148, 163, 184, 0.72);
    margin-bottom: 0.25rem;
    font-weight: 700;
  }

  .diff-line {
    padding: 0.125rem 0.5rem;
    border-radius: var(--radius-sm);
  }

  .diff-section.added .diff-line,
  .diff-line.new {
    color: #86efac;
    background: rgba(22, 101, 52, 0.18);
    border-left: 2px solid rgba(34, 197, 94, 0.44);
  }

  .diff-section.removed .diff-line,
  .diff-line.old {
    color: #fda4af;
    background: rgba(159, 18, 57, 0.18);
    border-left: 2px solid rgba(244, 63, 94, 0.42);
  }

  .diff-section.changed .diff-label { color: #fbbf24; }

  .no-diff {
    color: rgba(148, 163, 184, 0.72);
    text-align: center;
    padding: 2rem;
    font-style: italic;
  }
</style>
