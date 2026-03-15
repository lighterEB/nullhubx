<script lang="ts">
  import { t } from "$lib/i18n/index.svelte";
</script>

<div class="page-container">
  <header class="page-header">
    <h1>{t('nav.connections')}</h1>
    <p class="subtitle">统一管理模型提供商 API Key 与通讯渠道 Token</p>
  </header>
  
  <div class="content">
    <div class="empty-state">
      <p>这里将展示 Providers 和 Channels 的配置表单。</p>
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
</style>
