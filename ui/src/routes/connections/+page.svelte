<script lang="ts">
  import { onMount } from "svelte";
  import { api } from "$lib/api/client";

  let loading = $state(true);
  let error = $state("");
  let providers = $state<any[]>([]);
  let channels = $state<any[]>([]);

  async function load() {
    loading = true;
    error = "";
    try {
      const [providerData, channelData] = await Promise.all([
        api.getSavedProviders(),
        api.getSavedChannels(),
      ]);
      providers = providerData?.providers || [];
      channels = channelData?.channels || [];
    } catch (e) {
      error = e instanceof Error ? e.message : "加载失败";
    } finally {
      loading = false;
    }
  }

  onMount(() => {
    void load();
  });
</script>

<svelte:head>
  <title>资源中心 - NullHubX</title>
</svelte:head>

<div class="page">
  <header class="page-header">
    <div>
      <h1>资源中心</h1>
      <p>统一管理全局共享资源：模型服务商与通讯渠道</p>
    </div>
    <button class="refresh-btn" onclick={load} disabled={loading}>
      {loading ? "刷新中..." : "刷新"}
    </button>
  </header>

  {#if error}
    <div class="error-banner">加载失败：{error}</div>
  {/if}

  <section class="card">
    <div class="card-title-row">
      <h2>模型服务商</h2>
      <span>{providers.length} 条</span>
    </div>
    {#if providers.length === 0}
      <p class="empty">暂无已保存模型服务商。可在安装向导中验证后自动入库。</p>
    {:else}
      <div class="table-wrap">
        <table>
          <thead>
            <tr>
              <th>名称</th>
              <th>提供商</th>
              <th>默认模型</th>
              <th>验证状态</th>
            </tr>
          </thead>
          <tbody>
            {#each providers as p}
              <tr>
                <td>{p.name}</td>
                <td>{p.provider}</td>
                <td>{p.model || "-"}</td>
                <td>
                  {#if p.last_validation_ok}
                    <span class="ok">通过</span>
                  {:else if p.last_validation_at}
                    <span class="bad">失败</span>
                  {:else}
                    <span class="dim">未校验</span>
                  {/if}
                </td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    {/if}
  </section>

  <section class="card">
    <div class="card-title-row">
      <h2>通讯渠道</h2>
      <span>{channels.length} 条</span>
    </div>
    {#if channels.length === 0}
      <p class="empty">暂无已保存渠道。可在安装向导中验证后自动入库。</p>
    {:else}
      <div class="table-wrap">
        <table>
          <thead>
            <tr>
              <th>名称</th>
              <th>渠道类型</th>
              <th>账号</th>
              <th>最近验证</th>
            </tr>
          </thead>
          <tbody>
            {#each channels as c}
              <tr>
                <td>{c.name}</td>
                <td>{c.channel_type}</td>
                <td>{c.account}</td>
                <td>{c.validated_at || "未验证"}</td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
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

  .page-header {
    display: flex;
    justify-content: space-between;
    align-items: flex-end;
    gap: var(--spacing-lg);
  }

  h1 {
    margin: 0;
    font-family: var(--font-mono);
    font-size: var(--text-2xl);
    color: var(--slate-900);
  }

  .page-header p {
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

  .refresh-btn:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  .error-banner {
    padding: 0.75rem 1rem;
    border: 1px solid var(--red-200);
    background: var(--red-50);
    border-radius: var(--radius-md);
    color: var(--red-700);
  }

  .card {
    border: 1px solid var(--slate-200);
    border-radius: var(--radius-lg);
    background: white;
    padding: var(--spacing-xl);
  }

  .card-title-row {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: var(--spacing-md);
  }

  h2 {
    margin: 0;
    font-size: var(--text-lg);
    color: var(--slate-800);
  }

  .card-title-row span {
    color: var(--slate-500);
    font-family: var(--font-mono);
    font-size: var(--text-xs);
  }

  .empty {
    margin: 0;
    color: var(--slate-500);
    padding: var(--spacing-md);
    border: 1px dashed var(--slate-300);
    border-radius: var(--radius-md);
    background: var(--slate-50);
  }

  .table-wrap {
    overflow: auto;
  }

  table {
    width: 100%;
    border-collapse: collapse;
    min-width: 720px;
  }

  th, td {
    text-align: left;
    padding: 0.55rem 0.5rem;
    border-bottom: 1px solid var(--slate-200);
    font-size: var(--text-sm);
  }

  th {
    color: var(--slate-500);
    font-weight: 600;
    background: var(--slate-50);
  }

  td {
    color: var(--slate-800);
  }

  .ok {
    color: var(--emerald-700);
    font-weight: 600;
  }

  .bad {
    color: var(--red-600);
    font-weight: 600;
  }

  .dim {
    color: var(--slate-500);
  }

  @media (max-width: 780px) {
    .page {
      padding: var(--spacing-xl);
    }

    .page-header {
      flex-direction: column;
      align-items: stretch;
    }
  }
</style>
