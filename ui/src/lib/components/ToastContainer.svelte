<script lang="ts">
  import { toast } from '$lib/toastStore.svelte';
  import { t } from '$lib/i18n/index.svelte';
  import { fade, fly } from 'svelte/transition';
</script>

<div class="toast-container">
  {#each toast.toasts as item (item.id)}
    <div
      class="toast toast-{item.type}"
      in:fly={{ y: 20, duration: 250 }}
      out:fade={{ duration: 200 }}
      role="alert"
    >
      <div class="icon">
        {#if item.type === 'error'}
          <svg viewBox="0 0 24 24" fill="none" class="w-5 h-5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" /></svg>
        {:else if item.type === 'success'}
          <svg viewBox="0 0 24 24" fill="none" class="w-5 h-5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z" /></svg>
        {:else if item.type === 'warning'}
          <svg viewBox="0 0 24 24" fill="none" class="w-5 h-5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4h.01m-6.938 4h13.856c1.54 0 2.502-1.667 1.732-3L13.732 4c-.77-1.333-2.694-1.333-3.464 0L3.34 16c-.77 1.333.192 3 1.732 3z" /></svg>
        {:else}
          <svg viewBox="0 0 24 24" fill="none" class="w-5 h-5" stroke="currentColor"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" /></svg>
        {/if}
      </div>
      <span class="message">{item.message}</span>
      <button class="close-btn" onclick={() => toast.remove(item.id)} aria-label={t('common.close')}>
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M6 18L18 6M6 6l12 12" /></svg>
      </button>
    </div>
  {/each}
</div>

<style>
  .toast-container {
    position: fixed;
    top: var(--topbar-height, 60px);
    right: 1rem;
    z-index: 9999;
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
    pointer-events: none;
    padding-top: 1rem;
  }

  .toast {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    padding: 0.75rem 1rem;
    border-radius: var(--radius-md);
    box-shadow: var(--shadow-lg);
    pointer-events: auto;
    max-width: 24rem;
    word-break: break-word;
    border: 1px solid var(--shell-border);
    background: rgba(13, 20, 36, 0.92);
    color: var(--shell-text);
    backdrop-filter: blur(18px);
  }

  .toast-error {
    border-color: rgba(244, 63, 94, 0.28);
    box-shadow: var(--shadow-lg), 0 0 0 1px rgba(244, 63, 94, 0.12), 0 0 24px rgba(244, 63, 94, 0.14);
  }

  .toast-success {
    border-color: rgba(16, 185, 129, 0.24);
    box-shadow: var(--shadow-lg), 0 0 0 1px rgba(16, 185, 129, 0.1), 0 0 24px rgba(16, 185, 129, 0.14);
  }

  .toast-warning {
    border-color: rgba(245, 158, 11, 0.24);
    box-shadow: var(--shadow-lg), 0 0 0 1px rgba(245, 158, 11, 0.1), 0 0 24px rgba(245, 158, 11, 0.12);
  }

  .toast-info {
    border-color: rgba(34, 211, 238, 0.24);
    box-shadow: var(--shadow-lg), 0 0 0 1px rgba(34, 211, 238, 0.1), 0 0 24px rgba(34, 211, 238, 0.14);
  }

  .icon {
    flex-shrink: 0;
    width: 1.25rem;
    height: 1.25rem;
  }

  .toast-error .icon {
    color: var(--red-300);
  }

  .toast-success .icon {
    color: #4ade80;
  }

  .toast-warning .icon {
    color: #fbbf24;
  }

  .toast-info .icon {
    color: var(--cyan-300);
  }

  .message {
    font-size: var(--text-sm);
    line-height: 1.45;
    flex-grow: 1;
  }

  .close-btn {
    background: transparent;
    border: none;
    color: inherit;
    opacity: 0.6;
    cursor: pointer;
    padding: 0.25rem;
    display: flex;
    align-items: center;
    justify-content: center;
    transition: opacity 0.2s;
  }

  .close-btn:hover {
    opacity: 1;
    background: rgba(255, 255, 255, 0.06);
    border-radius: 999px;
  }

  .close-btn svg {
    width: 1rem;
    height: 1rem;
  }
</style>
