<script lang="ts">
  let { value = $bindable(''), onerror = (_msg: string) => {} } = $props();
  let valid = $state(true);
  let errorMsg = $state('');

  function handleInput(e: Event) {
    const target = e.target as HTMLTextAreaElement;
    value = target.value;
    try {
      JSON.parse(value);
      valid = true;
      errorMsg = '';
      onerror('');
    } catch (err) {
      valid = false;
      errorMsg = (err as Error).message;
      onerror(errorMsg);
    }
  }
</script>

<div class="editor-wrap">
  <textarea
    class="json-editor"
    class:invalid={!valid}
    spellcheck="false"
    {value}
    oninput={handleInput}
  ></textarea>
  {#if !valid}
    <div class="error-line">{errorMsg}</div>
  {/if}
</div>

<style>
  .editor-wrap {
    display: flex;
    flex-direction: column;
    height: 100%;
  }

  .json-editor {
    flex: 1;
    width: 100%;
    min-height: 300px;
    padding: 1rem;
    background:
      linear-gradient(180deg, rgba(7, 12, 22, 0.94), rgba(10, 17, 31, 0.92)),
      radial-gradient(circle at top right, rgba(34, 211, 238, 0.06), transparent 36%);
    color: rgba(226, 232, 240, 0.88);
    border: 1px solid rgba(96, 165, 250, 0.14);
    border-radius: var(--radius-xl);
    font-family: var(--font-mono);
    font-size: 0.8125rem;
    line-height: 1.6;
    resize: vertical;
    outline: none;
    transition: border-color 0.2s ease;
    tab-size: 2;
  }

  .json-editor:focus {
    border-color: rgba(34, 211, 238, 0.26);
    box-shadow: 0 0 0 3px rgba(34, 211, 238, 0.12);
  }

  .json-editor.invalid {
    border-color: rgba(244, 63, 94, 0.34);
    box-shadow: 0 0 0 3px rgba(244, 63, 94, 0.12);
  }

  .error-line {
    padding: 0.375rem 0.75rem;
    font-size: 0.75rem;
    font-family: var(--font-mono);
    color: #fda4af;
    background: rgba(159, 18, 57, 0.16);
    border: 1px solid rgba(244, 63, 94, 0.28);
    border-top: none;
    border-radius: 0 0 var(--radius-xl) var(--radius-xl);
  }
</style>
