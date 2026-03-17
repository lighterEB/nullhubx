<script lang="ts">
  import { t } from "$lib/i18n/index.svelte";
</script>

<div class="page-container">
  <header class="page-header">
    <h1>{t('nav.agents')}</h1>
    <p class="subtitle">管理您的专属数字员工和 AI 助手</p>
  </header>

  <div class="content">
    <div class="empty-state">
      <p>这里将展示配置好的 Agents。</p>
    </div>
  </div>
</div>

<style>
  .page-container {
    padding: var(--spacing-2xl);
    max-width: 1200px;
    margin: 0 auto;
  }

  .page-header {
    margin-bottom: var(--spacing-2xl);
  }

  h1 {
    font-size: var(--text-3xl);
    color: var(--slate-900);
    margin-bottom: var(--spacing-sm);
  }

  .subtitle {
    color: var(--slate-500);
    font-size: var(--text-base);
  }

  .empty-state {
    padding: var(--spacing-4xl);
    text-align: center;
    background: var(--slate-50);
    border: 1px dashed var(--slate-300);
    border-radius: var(--radius-xl);
    color: var(--slate-500);
  }

  @media (max-width: 680px) {
    .page-container {
      padding: var(--spacing-lg);
    }

    .empty-state {
      padding: var(--spacing-2xl);
    }
  }
</style>
