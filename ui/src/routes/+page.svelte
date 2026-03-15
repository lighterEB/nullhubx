<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import InstanceCard from "$lib/components/InstanceCard.svelte";
  import { status, statusError, instanceCount, runningCount, subscribeStatus, refreshStatus } from "$lib/statusStore";

  let unsubscribe: (() => void) | null = null;

  onMount(() => {
    unsubscribe = subscribeStatus();
  });

  onDestroy(() => {
    unsubscribe?.();
  });
</script>

<svelte:head>
  <title>大盘图表 - NullHubX</title>
</svelte:head>

<div class="page">
  <header class="page-header">
    <div class="header-left">
      <div class="breadcrumb">
        <span class="breadcrumb-item">监控</span>
        <span class="breadcrumb-sep">/</span>
        <span class="breadcrumb-item active">大盘图表</span>
      </div>
      <h1>
        系统总体 <span class="highlight">运行状态</span>
      </h1>
      <p class="subtitle">监控全局资源占用与活跃实例</p>
    </div>
    <div class="header-right">
      <span class="badge badge-indigo">{$instanceCount} 个管理实例</span>
      <span class="badge badge-emerald">{$runningCount} 正在运行</span>
      <a href="/hub" class="btn-add">
        <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>
        前往应用市场
      </a>
    </div>
  </header>

  <hr class="divider" />

  {#if $statusError}
    <div class="error-banner">
      <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>
      <span>ERR: {$statusError}</span>
    </div>
  {/if}

  {#if $status}
    {#if Object.keys($status.instances || {}).length > 0}
      <div class="instance-grid">
        {#each Object.entries($status.instances || {}) as [component, instances], i}
          {#each Object.entries(instances as Record<string, any>) as [name, info], j}
            <div class="card-wrapper" style="animation-delay: {(i * 3 + j) * 60}ms">
              <InstanceCard
                {component}
                {name}
                version={info.version}
                status={info.status || "stopped"}
                autoStart={info.auto_start}
                port={info.port || 0}
                onAction={refreshStatus}
              />
            </div>
          {/each}
        {/each}
      </div>
    {:else}
      <div class="empty-state">
        <div class="empty-icon-circle">
          <span class="empty-symbol">◉</span>
        </div>
        <h2>暂无运行中的引擎</h2>
        <p>请先在应用市场安装核心组件</p>
        <a href="/hub" class="btn-add-empty">
          <svg xmlns="http://www.w3.org/2000/svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><line x1="12" y1="5" x2="12" y2="19"/><line x1="5" y1="12" x2="19" y2="12"/></svg>
          前往应用市场
        </a>
      </div>
    {/if}
  {/if}
</div>

<style>
  .page {
    padding: var(--spacing-4xl) var(--spacing-5xl);
    max-width: 1400px;
    margin: 0 auto;
  }

  .page-header {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
    margin-bottom: var(--spacing-xl);
  }

  .header-left {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-sm);
  }

  .breadcrumb {
    display: flex;
    align-items: center;
    gap: var(--spacing-xs);
    font-family: var(--font-mono);
    font-size: var(--text-xs);
    color: var(--slate-400);
    letter-spacing: 1px;
  }

  .breadcrumb-sep {
    color: var(--slate-300);
  }

  .breadcrumb-item.active {
    color: var(--slate-600);
  }

  h1 {
    font-family: var(--font-mono);
    font-size: var(--text-3xl);
    font-weight: 700;
    color: var(--slate-900);
    letter-spacing: 3px;
  }

  .highlight {
    color: var(--indigo-600);
  }

  .subtitle {
    font-family: var(--font-sans);
    font-size: var(--text-base);
    color: var(--slate-500);
    margin-top: var(--spacing-xs);
  }

  .header-right {
    display: flex;
    align-items: center;
    gap: var(--spacing-md);
  }

  .btn-add {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm);
    padding: var(--spacing-sm) var(--spacing-lg);
    background: var(--indigo-600);
    color: white;
    font-family: var(--font-mono);
    font-size: var(--text-sm);
    font-weight: 600;
    letter-spacing: 0.5px;
    border-radius: var(--radius-md);
    text-decoration: none;
    transition: all var(--transition-fast);
  }

  .btn-add:hover {
    background: var(--indigo-700);
    transform: translateY(-1px);
  }

  .divider {
    border: none;
    height: 1px;
    background: var(--slate-200);
    margin: var(--spacing-xl) 0;
  }

  .error-banner {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm);
    padding: var(--spacing-md) var(--spacing-lg);
    background: rgba(239, 68, 68, 0.08);
    border: 1px solid rgba(239, 68, 68, 0.2);
    border-radius: var(--radius-md);
    color: var(--red-500);
    font-family: var(--font-mono);
    font-size: var(--text-sm);
    margin-bottom: var(--spacing-xl);
  }

  .instance-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(340px, 1fr));
    gap: var(--spacing-xl);
  }

  .card-wrapper {
    opacity: 0;
    animation: fadeUp 0.4s ease forwards;
  }

  @keyframes fadeUp {
    from {
      opacity: 0;
      transform: translateY(20px);
    }
    to {
      opacity: 1;
      transform: translateY(0);
    }
  }

  .empty-state {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    padding-top: 120px;
    gap: 16px;
  }

  .empty-icon-circle {
    width: 64px;
    height: 64px;
    display: flex;
    align-items: center;
    justify-content: center;
    background: #eef2ff;
    border: 1px solid #c7d2fe;
    border-radius: 50%;
  }

  .empty-symbol {
    font-size: 24px;
    color: #4f46e5;
  }

  .empty-state h2 {
    font-family: var(--font-mono);
    font-size: 18px;
    font-weight: 700;
    color: #1e1b4b;
    letter-spacing: 1px;
    margin: 0;
  }

  .empty-state p {
    font-family: var(--font-sans);
    font-size: 14px;
    color: #64748b;
    margin: -4px 0 0 0;
  }

  .btn-add-empty {
    display: flex;
    align-items: center;
    gap: var(--spacing-sm);
    padding: var(--spacing-sm) var(--spacing-lg);
    background: var(--indigo-600);
    color: white;
    font-family: var(--font-mono);
    font-size: var(--text-sm);
    font-weight: 600;
    letter-spacing: 0.5px;
    border-radius: var(--radius-md);
    text-decoration: none;
    transition: all var(--transition-fast);
    margin-top: 8px;
  }

  .btn-add-empty:hover {
    background: var(--indigo-700);
    transform: translateY(-1px);
  }

  @media (max-width: 768px) {
    .page {
      padding: var(--spacing-xl);
    }
    
    .page-header {
      flex-direction: column;
      gap: var(--spacing-lg);
    }
    
    .header-right {
      width: 100%;
      justify-content: flex-start;
    }
  }
</style>
