<script lang="ts">
  import { api } from "$lib/api/client";

  let {
    name = "",
    displayName = "",
    description = "",
    alpha = false,
    installed = false,
    standalone = false,
    instanceCount = 0,
  } = $props();
  let importing = $state(false);
  let imported = $state(false);
  let comingSoon = $derived(alpha && !installed && !standalone);

  async function handleImport(e: MouseEvent) {
    e.preventDefault();
    e.stopPropagation();
    importing = true;
    try {
      await api.importInstance(name);
      imported = true;
      standalone = false;
      installed = true;
      instanceCount = 1;
    } catch (err) {
      console.error("Import failed:", err);
    } finally {
      importing = false;
    }
  }
</script>

{#if comingSoon}
<div class="component-card disabled">
  <div class="card-header">
    <div class="card-title">
      {#if alpha}
        <span class="alpha-badge">Alpha</span>
      {/if}
      <h3>{displayName}</h3>
    </div>
    <span class="coming-soon">Coming Soon</span>
  </div>
  <p class="card-description">{description}</p>
</div>
{:else}
<a href="/install/{name}" class="component-card">
  <div class="card-header">
    <div class="card-title">
      {#if alpha}
        <span class="alpha-badge">Alpha</span>
      {/if}
      <h3>{displayName}</h3>
    </div>
    <div class="card-status">
      {#if imported}
        <span class="badge success">Imported</span>
      {:else if standalone}
        <button class="btn-import" onclick={handleImport} disabled={importing}>
          {importing ? "Importing..." : "Import"}
        </button>
      {:else if installed}
        <span class="instance-count">{instanceCount} instance{instanceCount !== 1 ? "s" : ""}</span>
      {:else}
        <span class="install-hint">Click to install</span>
      {/if}
    </div>
  </div>
  <p class="card-description">{description}</p>
</a>
{/if}

<style>
  .component-card {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-md);
    padding: var(--spacing-xl);
    background: var(--bg-surface);
    border: 1px solid var(--border);
    border-radius: var(--radius-lg);
    color: var(--text-primary);
    text-decoration: none;
    transition: all var(--transition-base);
  }

  .component-card:hover:not(.disabled) {
    border-color: var(--border-hover);
    box-shadow: var(--shadow-md);
  }

  .component-card.disabled {
    opacity: 0.5;
    cursor: not-allowed;
    pointer-events: none;
  }

  .card-header {
    display: flex;
    align-items: flex-start;
    justify-content: space-between;
    gap: var(--spacing-md);
  }

  .card-title {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-xs);
  }

  .alpha-badge {
    display: inline-block;
    font-size: var(--text-xs);
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    padding: var(--spacing-xs) var(--spacing-sm);
    border-radius: var(--radius-sm);
    background: var(--badge-warning);
    color: var(--badge-warning-text);
    width: fit-content;
  }

  h3 {
    font-size: var(--text-lg);
    font-weight: 600;
    color: var(--text-primary);
    letter-spacing: 0.5px;
  }

  .card-status {
    display: flex;
    align-items: center;
  }

  .badge {
    font-size: var(--text-xs);
    font-weight: 500;
    padding: var(--spacing-xs) var(--spacing-sm);
    border-radius: var(--radius-sm);
  }

  .badge.success {
    background: var(--badge-success);
    color: var(--badge-success-text);
  }

  .instance-count {
    font-size: var(--text-xs);
    color: var(--text-secondary);
    background: var(--bg-elevated);
    padding: var(--spacing-xs) var(--spacing-sm);
    border-radius: var(--radius-sm);
  }

  .install-hint {
    font-size: var(--text-xs);
    color: var(--color-primary);
  }

  .coming-soon {
    font-size: var(--text-xs);
    color: var(--text-muted);
    background: var(--bg-elevated);
    padding: var(--spacing-xs) var(--spacing-sm);
    border-radius: var(--radius-sm);
  }

  .btn-import {
    font-size: var(--text-xs);
    font-weight: 600;
    padding: var(--spacing-xs) var(--spacing-md);
    border-radius: var(--radius-md);
    cursor: pointer;
    transition: all var(--transition-base);
    background: var(--color-primary);
    border: 1px solid var(--color-primary);
    color: white;
  }

  .btn-import:hover:not(:disabled) {
    background: var(--color-primary-hover);
  }

  .btn-import:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .card-description {
    font-size: var(--text-sm);
    color: var(--text-secondary);
    line-height: 1.6;
  }
</style>