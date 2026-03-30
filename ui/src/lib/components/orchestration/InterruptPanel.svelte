<script lang="ts">
  let {
    message = '',
    onResume = (_updates: any) => {},
    onCancel = () => {},
  } = $props();

  let stateJson = $state('{}');
  let jsonValid = $state(true);

  function handleInput(e: Event) {
    stateJson = (e.target as HTMLTextAreaElement).value;
    try {
      JSON.parse(stateJson);
      jsonValid = true;
    } catch {
      jsonValid = false;
    }
  }

  function approve() {
    try {
      const updates = JSON.parse(stateJson);
      onResume(updates);
    } catch { /* ignore */ }
  }

  function reject() {
    onCancel();
  }
</script>

<!-- svelte-ignore a11y_click_events_have_key_events -->
<div class="overlay" role="button" tabindex="-1" onclick={reject}>
  <div class="panel" role="dialog" aria-label="Run interrupted" tabindex="-1" onclick={(e) => e.stopPropagation()} onkeydown={(e) => { if (e.key === 'Escape') reject(); }}>
    <div class="panel-header">
      <span class="panel-title">Run Interrupted</span>
    </div>

    <div class="panel-body">
      <div class="message">
        <span class="msg-label">Message:</span>
        <p>{message || 'This run requires approval to continue.'}</p>
      </div>

      <div class="state-section">
        <label class="state-label" for="state-updates">State Updates (JSON)</label>
        <textarea
          id="state-updates"
          class="state-editor"
          class:invalid={!jsonValid}
          spellcheck="false"
          value={stateJson}
          oninput={handleInput}
        ></textarea>
        {#if !jsonValid}
          <span class="json-err">Invalid JSON</span>
        {/if}
      </div>
    </div>

    <div class="panel-actions">
      <button class="btn-reject" onclick={reject}>Reject</button>
      <button class="btn-approve" onclick={approve} disabled={!jsonValid}>Approve & Resume</button>
    </div>
  </div>
</div>

<style>
  .overlay {
    position: fixed;
    inset: 0;
    background: rgba(2, 8, 23, 0.72);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 100;
    backdrop-filter: blur(12px);
  }

  .panel {
    background:
      linear-gradient(180deg, rgba(7, 12, 22, 0.96), rgba(10, 17, 31, 0.94)),
      radial-gradient(circle at top right, rgba(245, 158, 11, 0.08), transparent 36%);
    border: 1px solid rgba(245, 158, 11, 0.22);
    border-radius: var(--radius-xl);
    width: 90%;
    max-width: 520px;
    box-shadow: 0 28px 80px rgba(2, 8, 23, 0.44);
  }

  .panel-header {
    padding: 1rem 1.25rem;
    border-bottom: 1px solid rgba(245, 158, 11, 0.14);
  }

  .panel-title {
    font-size: 1rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: #fbbf24;
  }

  .panel-body {
    padding: 1.25rem;
    display: flex;
    flex-direction: column;
    gap: 1rem;
  }

  .message {
    padding: 0.75rem;
    background: rgba(24, 18, 6, 0.84);
    border: 1px solid rgba(245, 158, 11, 0.18);
    border-radius: var(--radius-lg);
  }

  .msg-label {
    font-size: 0.6875rem;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: rgba(148, 163, 184, 0.72);
    display: block;
    margin-bottom: 0.375rem;
  }

  .message p {
    font-size: 0.875rem;
    color: rgba(226, 232, 240, 0.88);
    margin: 0;
  }

  .state-section {
    display: flex;
    flex-direction: column;
    gap: 0.375rem;
  }

  .state-label {
    font-size: 0.6875rem;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: rgba(148, 163, 184, 0.72);
  }

  .state-editor {
    width: 100%;
    min-height: 100px;
    padding: 0.75rem;
    background: rgba(7, 12, 22, 0.92);
    color: rgba(226, 232, 240, 0.88);
    border: 1px solid rgba(96, 165, 250, 0.16);
    border-radius: var(--radius-lg);
    font-family: var(--font-mono);
    font-size: 0.8125rem;
    line-height: 1.5;
    resize: vertical;
    outline: none;
  }

  .state-editor:focus {
    border-color: rgba(34, 211, 238, 0.26);
    box-shadow: 0 0 0 3px rgba(34, 211, 238, 0.12);
  }

  .state-editor.invalid {
    border-color: rgba(244, 63, 94, 0.34);
  }

  .json-err {
    font-size: 0.6875rem;
    color: #fda4af;
    font-family: var(--font-mono);
  }

  .panel-actions {
    display: flex;
    justify-content: flex-end;
    gap: 0.75rem;
    padding: 1rem 1.25rem;
    border-top: 1px solid rgba(96, 165, 250, 0.12);
  }

  .btn-reject,
  .btn-approve {
    padding: 0.5rem 1rem;
    border-radius: 999px;
    font-size: 0.8125rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    cursor: pointer;
    transition: all 0.2s ease;
  }

  .btn-reject {
    background: rgba(59, 12, 24, 0.82);
    color: #fda4af;
    border: 1px solid rgba(244, 63, 94, 0.22);
  }

  .btn-reject:hover {
    border-color: rgba(244, 63, 94, 0.34);
    box-shadow: 0 0 18px rgba(244, 63, 94, 0.14);
  }

  .btn-approve {
    background: rgba(8, 39, 36, 0.84);
    color: #6ee7b7;
    border: 1px solid rgba(16, 185, 129, 0.22);
  }

  .btn-approve:hover:not(:disabled) {
    border-color: rgba(16, 185, 129, 0.34);
    box-shadow: 0 0 18px rgba(16, 185, 129, 0.14);
  }

  .btn-approve:disabled {
    opacity: 0.4;
    cursor: not-allowed;
  }
</style>
