<script lang="ts">
  import { api } from "$lib/api/client";
  import { t } from "$lib/i18n/index.svelte";
  import {
    describeInstanceCliError,
    isInstanceCliError,
  } from "$lib/instanceCli";

  type MemoryStats = {
    backend?: string;
    retrieval?: string;
    vector?: string;
    embedding?: string;
    rollout?: string;
    sync?: string;
    fallback?: string;
    sources?: number;
    entries?: number;
    vector_entries?: number | null;
    outbox_pending?: number | null;
  };

  type MemoryEntry = {
    key: string;
    category: string;
    timestamp: string;
    content: string;
    session_id?: string | null;
  };

  type MemorySearchResult = {
    key: string;
    category: string;
    snippet: string;
    source: string;
    source_path: string;
    final_score: number;
    start_line: number;
    end_line: number;
    created_at: number;
    keyword_rank?: number | null;
    vector_score?: number | null;
  };

  let { component, name, active = false } = $props<{
    component: string;
    name: string;
    active?: boolean;
  }>();

  let stats = $state<MemoryStats | null>(null);
  let statsLoading = $state(false);
  let statsError = $state<string | null>(null);
  let loadedStatsKey = $state("");

  let entries = $state<MemoryEntry[]>([]);
  let entriesLoading = $state(false);
  let entriesError = $state<string | null>(null);
  let category = $state("conversation");
  let limit = $state("50");
  let loadedEntriesKey = $state("");

  let searchQuery = $state("");
  let searchResults = $state<MemorySearchResult[]>([]);
  let searchLoading = $state(false);
  let searchError = $state<string | null>(null);
  let searchSubmittedQuery = $state("");
  let searchContextKey = $state("");

  const instanceKey = $derived(`${component}/${name}`);
  let statsRequestSeq = 0;
  let entriesRequestSeq = 0;
  let searchRequestSeq = 0;

  function formatSearchTimestamp(epochSeconds: number): string {
    if (!epochSeconds) return "-";
    const date = new Date(epochSeconds * 1000);
    return Number.isNaN(date.getTime()) ? String(epochSeconds) : date.toLocaleString();
  }

  function parsedLimit(): number {
    return Math.max(1, Number(limit || 50) || 50);
  }

  function translate(key: string, replacements: Record<string, string | number> = {}): string {
    let message = t(key);
    for (const [name, value] of Object.entries(replacements)) {
      message = message.replace(`{${name}}`, String(value));
    }
    return message;
  }

  async function loadStats(force = false) {
    if (!active || !component || !name) return;
    const contextKey = instanceKey;
    const nextKey = `${instanceKey}:stats`;
    if (!force && loadedStatsKey === nextKey) return;

    const req = ++statsRequestSeq;
    statsLoading = true;
    statsError = null;
    try {
      const result = await api.getMemory(component, name, { stats: true });
      if (req !== statsRequestSeq || contextKey !== instanceKey || !active) return;
      if (isInstanceCliError(result)) {
        stats = null;
        statsError = describeInstanceCliError(result, t("memoryPanel.statsUnavailable"));
      } else {
        stats = result || null;
        statsError = null;
      }
      loadedStatsKey = nextKey;
    } catch (error) {
      if (req !== statsRequestSeq || contextKey !== instanceKey || !active) return;
      stats = null;
      statsError = (error as Error).message || t("memoryPanel.loadStatsFailed");
    } finally {
      if (req === statsRequestSeq && contextKey === instanceKey) {
        statsLoading = false;
      }
    }
  }

  async function loadEntries(force = false) {
    if (!active || !component || !name) return;
    const contextKey = instanceKey;
    const nextKey = `${instanceKey}:${category}:${limit}`;
    if (!force && loadedEntriesKey === nextKey) return;

    const req = ++entriesRequestSeq;
    entriesLoading = true;
    entriesError = null;
    try {
      const result = await api.getMemory(component, name, {
        category: category === "all" ? undefined : category,
        limit: parsedLimit(),
      });
      if (req !== entriesRequestSeq || contextKey !== instanceKey || !active) return;
      if (isInstanceCliError(result)) {
        entries = [];
        entriesError = describeInstanceCliError(result, t("memoryPanel.entriesUnavailable"));
      } else {
        entries = Array.isArray(result) ? result : [];
        entriesError = null;
      }
      loadedEntriesKey = nextKey;
    } catch (error) {
      if (req !== entriesRequestSeq || contextKey !== instanceKey || !active) return;
      entries = [];
      entriesError = (error as Error).message || t("memoryPanel.loadEntriesFailed");
    } finally {
      if (req === entriesRequestSeq && contextKey === instanceKey) {
        entriesLoading = false;
      }
    }
  }

  async function runSearch() {
    if (!active || !searchQuery.trim()) return;
    const contextKey = instanceKey;
    const req = ++searchRequestSeq;
    searchLoading = true;
    searchError = null;
    searchSubmittedQuery = searchQuery.trim();
    try {
      const result = await api.getMemory(component, name, {
        query: searchSubmittedQuery,
        limit: parsedLimit(),
      });
      if (req !== searchRequestSeq || contextKey !== instanceKey || !active) return;
      if (isInstanceCliError(result)) {
        searchResults = [];
        searchError = describeInstanceCliError(result, t("memoryPanel.searchUnavailable"));
      } else {
        searchResults = Array.isArray(result) ? result : [];
        searchError = null;
      }
    } catch (error) {
      if (req !== searchRequestSeq || contextKey !== instanceKey || !active) return;
      searchResults = [];
      searchError = (error as Error).message || t("memoryPanel.searchFailed");
    } finally {
      if (req === searchRequestSeq && contextKey === instanceKey) {
        searchLoading = false;
      }
    }
  }

  function refreshMemory() {
    loadedStatsKey = "";
    loadedEntriesKey = "";
    void loadStats(true);
    void loadEntries(true);
  }

  $effect(() => {
    if (!active || !component || !name) return;
    if (searchContextKey !== instanceKey) {
      searchContextKey = instanceKey;
      searchQuery = "";
      searchResults = [];
      searchLoading = false;
      searchError = null;
      searchSubmittedQuery = "";
    }
    if (loadedStatsKey !== `${instanceKey}:stats`) {
      stats = null;
      statsError = null;
      void loadStats(true);
    }
  });

  $effect(() => {
    if (!active || !component || !name) return;
    const key = `${instanceKey}:${category}:${limit}`;
    if (loadedEntriesKey === key) return;
    entries = [];
    entriesError = null;
    void loadEntries(true);
  });
</script>

<div class="memory-panel">
  <div class="panel-toolbar">
    <div>
      <h2>{t("memoryPanel.title")}</h2>
      <p>{t("memoryPanel.subtitle")}</p>
    </div>
    <button class="toolbar-btn" onclick={refreshMemory} disabled={statsLoading || entriesLoading}>
      {t("memoryPanel.refresh")}
    </button>
  </div>

  <div class="stats-grid">
    {#if statsError}
      <div class="panel-state warning">{statsError}</div>
    {:else if statsLoading && !stats}
      <div class="panel-state">{t("memoryPanel.loadingStats")}</div>
    {:else if stats}
      <div class="stat-card">
        <span>{t("memoryPanel.backend")}</span>
        <strong>{stats.backend || "-"}</strong>
      </div>
      <div class="stat-card">
        <span>{t("memoryPanel.retrieval")}</span>
        <strong>{stats.retrieval || "-"}</strong>
      </div>
      <div class="stat-card">
        <span>{t("memoryPanel.vector")}</span>
        <strong>{stats.vector || "-"}</strong>
      </div>
      <div class="stat-card">
        <span>{t("memoryPanel.entries")}</span>
        <strong>{stats.entries ?? 0}</strong>
      </div>
      <div class="stat-card">
        <span>{t("memoryPanel.vectorEntries")}</span>
        <strong>{stats.vector_entries ?? "-"}</strong>
      </div>
      <div class="stat-card">
        <span>{t("memoryPanel.pending")}</span>
        <strong>{stats.outbox_pending ?? "-"}</strong>
      </div>
    {/if}
  </div>

  <section class="memory-section">
    <div class="section-header">
      <h3>{t("memoryPanel.savedEntries")}</h3>
      <div class="controls">
        <label>
          <span>{t("memoryPanel.category")}</span>
          <select bind:value={category}>
            <option value="all">{t("memoryPanel.all")}</option>
            <option value="core">{t("memoryPanel.core")}</option>
            <option value="daily">{t("memoryPanel.daily")}</option>
            <option value="conversation">{t("memoryPanel.conversation")}</option>
          </select>
        </label>
        <label>
          <span>{t("memoryPanel.count")}</span>
          <select bind:value={limit}>
            <option value="20">20</option>
            <option value="50">50</option>
            <option value="100">100</option>
          </select>
        </label>
      </div>
    </div>

    {#if entriesError}
      <div class="panel-state warning">{entriesError}</div>
    {:else if entriesLoading && entries.length === 0}
      <div class="panel-state">{t("memoryPanel.loadingEntries")}</div>
    {:else if entries.length === 0}
      <div class="panel-state">{t("memoryPanel.emptyEntries")}</div>
    {:else}
      <div class="entry-list">
        {#each entries as entry}
          <article class="entry-card">
            <header>
              <div>
                <div class="entry-key">{entry.key}</div>
                <div class="entry-meta">
                  <span>{entry.category}</span>
                  <span>{entry.timestamp || "-"}</span>
                  {#if entry.session_id}
                    <span class="mono">{entry.session_id}</span>
                  {/if}
                </div>
              </div>
            </header>
            <pre>{entry.content}</pre>
          </article>
        {/each}
      </div>
    {/if}
  </section>

  <section class="memory-section">
    <div class="section-header">
      <h3>{t("memoryPanel.searchTitle")}</h3>
      <form
        class="search-form"
        onsubmit={(event) => {
          event.preventDefault();
          void runSearch();
        }}
      >
        <input bind:value={searchQuery} placeholder={t("memoryPanel.searchPlaceholder")} />
        <button class="toolbar-btn" type="submit" disabled={searchLoading || !searchQuery.trim()}>
          {searchLoading ? t("memoryPanel.searching") : t("memoryPanel.searchAction")}
        </button>
      </form>
    </div>

    {#if searchError}
      <div class="panel-state warning">{searchError}</div>
    {:else if searchLoading}
      <div class="panel-state">{t("memoryPanel.searching")}</div>
    {:else if searchSubmittedQuery && searchResults.length === 0}
      <div class="panel-state">{translate("memoryPanel.noResults", { query: searchSubmittedQuery })}</div>
    {:else if searchResults.length > 0}
      <div class="search-list">
        {#each searchResults as result}
          <article class="search-card">
            <header>
              <div>
                <div class="entry-key">{result.key}</div>
                <div class="entry-meta">
                  <span>{result.category}</span>
                  <span>{result.source}</span>
                  <span>{result.final_score?.toFixed?.(3) ?? result.final_score}</span>
                </div>
              </div>
              <div class="search-meta">
                <span>{formatSearchTimestamp(result.created_at)}</span>
                <span>{result.start_line}-{result.end_line}</span>
              </div>
            </header>
            <div class="search-path mono">{result.source_path}</div>
            <pre>{result.snippet}</pre>
          </article>
        {/each}
      </div>
    {:else}
      <div class="panel-state">{t("memoryPanel.hint")}</div>
    {/if}
  </section>
</div>

<style>
  .memory-panel {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-lg);
  }

  .panel-toolbar,
  .section-header {
    display: flex;
    justify-content: space-between;
    gap: var(--spacing-lg);
    align-items: flex-start;
  }

  .panel-toolbar h2,
  .section-header h3 {
    margin: 0;
    color: var(--slate-900);
  }

  .panel-toolbar p {
    margin: 0.25rem 0 0;
    color: var(--slate-600);
    font-size: 0.875rem;
  }

  .toolbar-btn {
    padding: 0.6rem 0.95rem;
    border: 1px solid rgba(141, 154, 178, 0.22);
    background: rgba(255, 255, 255, 0.74);
    color: var(--slate-700);
    border-radius: 999px;
    font-size: 0.78rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    cursor: pointer;
  }

  .toolbar-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .panel-state {
    padding: 1.5rem;
    border: 1px dashed rgba(116, 136, 173, 0.32);
    background: rgba(255, 255, 255, 0.58);
    color: var(--slate-500);
    border-radius: var(--radius-lg);
    text-align: center;
  }

  .panel-state.warning {
    border-color: rgba(245, 158, 11, 0.22);
    color: var(--amber-700);
    background: rgba(255, 251, 235, 0.86);
  }

  .stats-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
    gap: var(--spacing-md);
  }

  .stat-card {
    display: flex;
    flex-direction: column;
    gap: 0.35rem;
    padding: 1rem;
    border: 1px solid rgba(141, 154, 178, 0.18);
    background: linear-gradient(180deg, rgba(255, 255, 255, 0.84), rgba(246, 249, 255, 0.74));
    border-radius: var(--radius-lg);
    box-shadow: var(--shadow-sm);
  }

  .stat-card span {
    color: var(--slate-500);
    font-size: 0.72rem;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    font-weight: 600;
  }

  .stat-card strong {
    font-size: 0.95rem;
    color: var(--slate-900);
  }

  .memory-section {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-md);
    padding: var(--spacing-lg);
    border: 1px solid rgba(141, 154, 178, 0.18);
    background: linear-gradient(180deg, rgba(255, 255, 255, 0.84), rgba(245, 249, 255, 0.72));
    border-radius: var(--radius-lg);
    box-shadow: var(--shadow-sm);
  }

  .controls,
  .search-form {
    display: flex;
    gap: var(--spacing-md);
    align-items: end;
  }

  .controls label,
  .search-form {
    color: var(--slate-600);
    font-size: 0.8rem;
  }

  .controls label {
    display: flex;
    flex-direction: column;
    gap: 0.35rem;
    font-weight: 600;
  }

  select,
  input {
    min-width: 120px;
    padding: 0.7rem 0.8rem;
    border: 1px solid rgba(141, 154, 178, 0.22);
    background: rgba(255, 255, 255, 0.78);
    color: var(--slate-900);
    border-radius: var(--radius-md);
  }

  .search-form {
    flex: 1;
  }

  .search-form input {
    flex: 1;
  }

  .entry-list,
  .search-list {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-md);
  }

  .entry-card,
  .search-card {
    padding: 0.95rem 1rem;
    border: 1px solid rgba(141, 154, 178, 0.16);
    border-radius: var(--radius-lg);
    background: rgba(255, 255, 255, 0.72);
  }

  .entry-card header,
  .search-card header {
    display: flex;
    justify-content: space-between;
    gap: 1rem;
    margin-bottom: 0.65rem;
  }

  .entry-key {
    font-family: var(--font-mono);
    font-size: 0.82rem;
    word-break: break-all;
    color: var(--slate-900);
  }

  .entry-meta,
  .search-meta {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem 0.75rem;
    margin-top: 0.3rem;
    color: var(--slate-500);
    font-size: 0.75rem;
  }

  .search-path {
    margin-bottom: 0.65rem;
    color: var(--cyan-600);
    font-size: 0.74rem;
    word-break: break-all;
  }

  .mono {
    font-family: var(--font-mono);
  }

  pre {
    margin: 0;
    white-space: pre-wrap;
    word-break: break-word;
    font-family: var(--font-mono);
    font-size: 0.82rem;
    line-height: 1.55;
    color: var(--slate-800);
  }

  @media (max-width: 900px) {
    .panel-toolbar,
    .section-header,
    .search-form {
      flex-direction: column;
      align-items: stretch;
    }
    .controls {
      flex-wrap: wrap;
      align-items: stretch;
    }
  }
</style>
