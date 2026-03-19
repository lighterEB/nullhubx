<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import { status, statusError, instanceCount, runningCount, subscribeStatus, refreshStatus } from "$lib/statusStore";

  let unsubscribe: (() => void) | null = null;

  onMount(() => {
    unsubscribe = subscribeStatus();
  });

  onDestroy(() => {
    unsubscribe?.();
  });

  const componentCount = $derived(Object.keys($status?.instances || {}).length);

  const recentInstances = $derived.by(() => {
    const rows: Array<{ component: string; name: string; status: string; version: string }> = [];
    const groups = $status?.instances || {};
    for (const [component, instances] of Object.entries(groups)) {
      for (const [name, info] of Object.entries(instances as Record<string, any>)) {
        rows.push({
          component,
          name,
          status: (info as any)?.status || "stopped",
          version: (info as any)?.version || "-",
        });
      }
    }
    rows.sort((a, b) => `${a.component}/${a.name}`.localeCompare(`${b.component}/${b.name}`));
    return rows.slice(0, 10);
  });
</script>

<svelte:head>
  <title>总览 - NullHubX</title>
</svelte:head>

<div class="page">
  <header class="hero">
    <div>
      <h1>NullHubX 总览</h1>
      <p>后端驱动的多实例管理入口：先看状态，再进工作区。</p>
    </div>
    <button class="refresh-btn" onclick={refreshStatus}>刷新状态</button>
  </header>

  {#if $statusError}
    <div class="error-banner">状态拉取失败：{$statusError}</div>
  {/if}

  <section class="stats-grid">
    <article class="stat-card">
      <span>组件数量</span>
      <strong>{componentCount}</strong>
    </article>
    <article class="stat-card">
      <span>实例总数</span>
      <strong>{$instanceCount}</strong>
    </article>
    <article class="stat-card">
      <span>运行中实例</span>
      <strong>{$runningCount}</strong>
    </article>
    <article class="stat-card">
      <span>管理入口</span>
      <strong>5</strong>
    </article>
  </section>

  <section class="entry-grid">
    <a class="entry-card" href="/instances">
      <h2>实例工作区</h2>
      <p>按组件分组管理实例，执行启动/停止/重启/更新。</p>
    </a>
    <a class="entry-card" href="/resources">
      <h2>资源中心</h2>
      <p>集中管理全局 Providers 与 Channels 共享资源。</p>
    </a>
    <a class="entry-card" href="/orchestration">
      <h2>编排中心</h2>
      <p>查看编排工作流与运行记录，联动 NullBoiler/NullTickets。</p>
    </a>
    <a class="entry-card" href="/hub">
      <h2>应用市场</h2>
      <p>安装或导入组件实例，补齐运行依赖。</p>
    </a>
  </section>

  <section class="recent-card">
    <div class="recent-header">
      <h2>最近实例</h2>
      <a href="/instances">进入实例页</a>
    </div>
    {#if recentInstances.length === 0}
      <p class="empty">暂无实例。可前往应用市场安装组件。</p>
    {:else}
      <ul class="recent-list">
        {#each recentInstances as row}
          <li>
            <a href={`/instances/${row.component}/${row.name}`}>{row.component}/{row.name}</a>
            <span>{row.status}</span>
            <span>{row.version}</span>
          </li>
        {/each}
      </ul>
    {/if}
  </section>
</div>

<style>
  .page {
    max-width: 1240px;
    margin: 0 auto;
    padding: var(--spacing-3xl);
    display: flex;
    flex-direction: column;
    gap: var(--spacing-xl);
  }

  .hero {
    display: flex;
    justify-content: space-between;
    align-items: flex-end;
    gap: var(--spacing-lg);
  }

  h1 {
    margin: 0;
    font-family: var(--font-mono);
    font-size: 2rem;
    color: var(--slate-900);
  }

  .hero p {
    margin: var(--spacing-xs) 0 0 0;
    color: var(--slate-500);
  }

  .refresh-btn {
    border: 1px solid var(--indigo-500);
    background: var(--indigo-600);
    color: white;
    border-radius: var(--radius-md);
    padding: 0.55rem 0.9rem;
    cursor: pointer;
  }

  .error-banner {
    padding: 0.75rem 1rem;
    border: 1px solid var(--red-200);
    background: var(--red-50);
    border-radius: var(--radius-md);
    color: var(--red-700);
  }

  .stats-grid {
    display: grid;
    grid-template-columns: repeat(4, minmax(0, 1fr));
    gap: var(--spacing-md);
  }

  .stat-card {
    border: 1px solid var(--slate-200);
    border-radius: var(--radius-lg);
    background: white;
    padding: var(--spacing-lg);
  }

  .stat-card span {
    color: var(--slate-500);
    font-size: var(--text-sm);
  }

  .stat-card strong {
    margin-top: var(--spacing-xs);
    display: block;
    color: var(--slate-900);
    font-size: 1.6rem;
  }

  .entry-grid {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: var(--spacing-md);
  }

  .entry-card {
    border: 1px solid var(--slate-200);
    border-radius: var(--radius-lg);
    background: white;
    padding: var(--spacing-lg);
    text-decoration: none;
    color: inherit;
    transition: all var(--transition-fast);
  }

  .entry-card:hover {
    border-color: var(--indigo-300);
    transform: translateY(-2px);
  }

  .entry-card h2 {
    margin: 0;
    color: var(--slate-800);
    font-size: var(--text-lg);
  }

  .entry-card p {
    margin: var(--spacing-sm) 0 0 0;
    color: var(--slate-500);
    line-height: 1.45;
  }

  .recent-card {
    border: 1px solid var(--slate-200);
    border-radius: var(--radius-lg);
    background: white;
    padding: var(--spacing-xl);
  }

  .recent-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: var(--spacing-md);
  }

  .recent-header h2 {
    margin: 0;
    color: var(--slate-800);
    font-size: var(--text-lg);
  }

  .recent-header a {
    color: var(--indigo-600);
    text-decoration: none;
    font-size: var(--text-sm);
  }

  .recent-list {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-direction: column;
    gap: var(--spacing-sm);
  }

  .recent-list li {
    border: 1px solid var(--slate-200);
    border-radius: var(--radius-md);
    padding: 0.55rem 0.7rem;
    display: grid;
    grid-template-columns: minmax(0, 1.5fr) 0.8fr 0.7fr;
    gap: var(--spacing-sm);
    align-items: center;
    font-size: var(--text-sm);
  }

  .recent-list li a {
    color: var(--slate-800);
    text-decoration: none;
    font-family: var(--font-mono);
  }

  .recent-list li span {
    color: var(--slate-500);
  }

  .empty {
    margin: 0;
    color: var(--slate-500);
    border: 1px dashed var(--slate-300);
    border-radius: var(--radius-md);
    padding: var(--spacing-md);
    background: var(--slate-50);
  }

  @media (max-width: 960px) {
    .page {
      padding: var(--spacing-xl);
    }

    .stats-grid {
      grid-template-columns: repeat(2, minmax(0, 1fr));
    }

    .entry-grid {
      grid-template-columns: 1fr;
    }
  }

  @media (max-width: 680px) {
    .hero {
      flex-direction: column;
      align-items: stretch;
    }

    .stats-grid {
      grid-template-columns: 1fr;
    }

    .recent-list li {
      grid-template-columns: 1fr;
    }
  }
</style>
