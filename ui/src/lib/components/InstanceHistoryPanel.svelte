<script lang="ts">
  import {
    api,
    type HistoryMessagePayload,
    type HistorySessionPayload,
  } from "$lib/api/client";
  import { t } from "$lib/i18n/index.svelte";
  import {
    describeInstanceCliError,
    isInstanceCliError,
  } from "$lib/instanceCli";

  type HistorySession = {
    session_id: string;
    message_count: number;
    first_message_at: string;
    last_message_at: string;
  };

  type HistoryMessage = {
    role: string;
    content: string;
    created_at: string;
  };

  let { component, name, active = false } = $props<{
    component: string;
    name: string;
    active?: boolean;
  }>();

  const sessionPageSize = 50;
  const messagePageSize = 100;

  let sessions = $state<HistorySession[]>([]);
  let sessionsTotal = $state(0);
  let sessionsOffset = $state(0);
  let sessionsLoading = $state(false);
  let sessionsError = $state<string | null>(null);
  let loadedSessionsKey = $state("");

  let selectedSessionId = $state("");
  let messages = $state<HistoryMessage[]>([]);
  let messagesTotal = $state(0);
  let messagesOffset = $state(0);
  let messagesLoading = $state(false);
  let olderMessagesLoading = $state(false);
  let messagesError = $state<string | null>(null);
  let loadedMessagesKey = $state("");

  let sessionRequestSeq = 0;
  let messageRequestSeq = 0;

  const instanceKey = $derived(`${component}/${name}`);
  const selectedSession = $derived(
    sessions.find((session) => session.session_id === selectedSessionId) || null,
  );
  const visibleMessages = $derived([...messages].reverse());
  const canLoadOlder = $derived(selectedSessionId !== "" && messagesOffset > 0 && !olderMessagesLoading);
  const canShowNewerSessions = $derived(sessionsOffset > 0 && !sessionsLoading);
  const canShowOlderSessions = $derived(sessionsOffset + sessions.length < sessionsTotal && !sessionsLoading);
  const visibleSessionStart = $derived(sessions.length > 0 ? sessionsOffset + 1 : 0);
  const visibleSessionEnd = $derived(sessionsOffset + sessions.length);

  function formatTimestamp(value: string): string {
    if (!value) return "-";
    const trimmed = value.trim();
    const normalized = /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/.test(trimmed)
      ? trimmed.replace(" ", "T") + "Z"
      : trimmed;
    const date = new Date(normalized);
    return Number.isNaN(date.getTime()) ? value : date.toLocaleString();
  }

  function messageClass(role: string): string {
    switch ((role || "").toLowerCase()) {
      case "assistant":
        return "assistant";
      case "system":
        return "system";
      case "tool":
        return "tool";
      default:
        return "user";
    }
  }

  function translate(key: string, replacements: Record<string, string | number> = {}): string {
    let message = t(key);
    for (const [name, value] of Object.entries(replacements)) {
      message = message.replace(`{${name}}`, String(value));
    }
    return message;
  }

  function normalizeSession(session: HistorySessionPayload): HistorySession {
    return {
      session_id: typeof session.session_id === "string" ? session.session_id : "",
      message_count: typeof session.message_count === "number" ? session.message_count : 0,
      first_message_at: typeof session.first_message_at === "string" ? session.first_message_at : "",
      last_message_at: typeof session.last_message_at === "string" ? session.last_message_at : "",
    };
  }

  function normalizeMessage(message: HistoryMessagePayload): HistoryMessage {
    return {
      role: typeof message.role === "string" ? message.role : "user",
      content: typeof message.content === "string" ? message.content : "",
      created_at: typeof message.created_at === "string" ? message.created_at : "",
    };
  }

  async function loadSessions(force = false, requestedOffset = sessionsOffset) {
    if (!active || !component || !name) return;
    const contextKey = instanceKey;
    const nextKey = `${contextKey}:sessions:${requestedOffset}`;
    if (!force && loadedSessionsKey === nextKey) return;

    const req = ++sessionRequestSeq;
    sessionsLoading = true;
    sessionsError = null;

    try {
      const result = await api.getHistory(component, name, {
        limit: sessionPageSize,
        offset: requestedOffset,
      });
      if (req !== sessionRequestSeq || contextKey !== instanceKey || !active) return;

      if (isInstanceCliError(result)) {
        sessions = [];
        sessionsTotal = 0;
        sessionsOffset = requestedOffset;
        selectedSessionId = "";
        messages = [];
        messagesTotal = 0;
        messagesOffset = 0;
        loadedMessagesKey = "";
        sessionsError = describeInstanceCliError(result, t("historyPanel.unavailable"));
        loadedSessionsKey = nextKey;
        return;
      }

      sessions = Array.isArray(result?.sessions) ? result.sessions.map(normalizeSession) : [];
      sessionsTotal = Number(result?.total || sessions.length || 0);
      sessionsOffset = Number(result?.offset ?? requestedOffset);
      loadedSessionsKey = nextKey;

      const current = sessions.find((session) => session.session_id === selectedSessionId);
      if (current) {
        selectedSessionId = current.session_id;
        return;
      }
      if (sessions.length > 0) {
        openSession(sessions[0]);
      } else {
        selectedSessionId = "";
        messages = [];
        messagesTotal = 0;
        messagesOffset = 0;
        loadedMessagesKey = "";
      }
    } catch (error) {
      if (req !== sessionRequestSeq || contextKey !== instanceKey || !active) return;
      sessions = [];
      sessionsTotal = 0;
      sessionsOffset = requestedOffset;
      sessionsError = (error as Error).message || t("historyPanel.loadFailed");
    } finally {
      if (req === sessionRequestSeq && contextKey === instanceKey) {
        sessionsLoading = false;
      }
    }
  }

  function openSession(session: HistorySession) {
    if (!session?.session_id) return;
    selectedSessionId = session.session_id;
    messages = [];
    messagesTotal = Number(session.message_count || 0);
    messagesOffset = 0;
    messagesError = null;
    loadedMessagesKey = "";
  }

  async function loadInitialMessages(session: HistorySession) {
    const total = Math.max(0, Number(session?.message_count || 0));
    const offset = Math.max(total - messagePageSize, 0);
    await loadMessagesPage(session, offset, Math.min(messagePageSize, Math.max(total, 1)), "replace");
  }

  async function loadMessagesPage(
    session: HistorySession,
    offset: number,
    limit: number,
    mode: "replace" | "prepend",
  ) {
    if (!active || !session?.session_id) return;
    const contextKey = instanceKey;
    const req = ++messageRequestSeq;
    if (mode === "replace") {
      messagesLoading = true;
      messagesError = null;
    } else {
      olderMessagesLoading = true;
    }

    try {
      const result = await api.getHistory(component, name, {
        sessionId: session.session_id,
        limit,
        offset,
      });
      if (req !== messageRequestSeq || contextKey !== instanceKey || !active) return;

      if (isInstanceCliError(result)) {
        if (mode === "replace") {
          messages = [];
          messagesTotal = Number(session.message_count || 0);
          messagesOffset = 0;
        }
        messagesError = describeInstanceCliError(result, t("historyPanel.unavailable"));
        loadedMessagesKey = `${instanceKey}:${session.session_id}:${session.message_count}`;
        return;
      }

      const nextMessages = Array.isArray(result?.messages) ? result.messages.map(normalizeMessage) : [];
      const nextTotal = Number(result?.total || session.message_count || nextMessages.length || 0);
      if (mode === "prepend") {
        messages = [...nextMessages, ...messages];
      } else {
        messages = nextMessages;
      }
      messagesTotal = nextTotal;
      messagesOffset = Number(result?.offset ?? offset);
      messagesError = null;
      loadedMessagesKey = `${instanceKey}:${session.session_id}:${nextTotal}`;
    } catch (error) {
      if (req !== messageRequestSeq || contextKey !== instanceKey || !active) return;
      if (mode === "replace") {
        messages = [];
      }
      messagesError = (error as Error).message || t("historyPanel.loadMessagesFailed");
    } finally {
      if (req === messageRequestSeq && contextKey === instanceKey) {
        messagesLoading = false;
        olderMessagesLoading = false;
      }
    }
  }

  async function loadOlderMessages() {
    if (!selectedSession || !canLoadOlder) return;
    const nextLimit = Math.min(messagePageSize, messagesOffset);
    const nextOffset = Math.max(messagesOffset - nextLimit, 0);
    await loadMessagesPage(selectedSession, nextOffset, nextLimit, "prepend");
  }

  function showOlderSessions() {
    if (!canShowOlderSessions) return;
    void loadSessions(true, sessionsOffset + sessionPageSize);
  }

  function showNewerSessions() {
    if (!canShowNewerSessions) return;
    void loadSessions(true, Math.max(sessionsOffset - sessionPageSize, 0));
  }

  function refreshHistory() {
    loadedSessionsKey = "";
    loadedMessagesKey = "";
    void loadSessions(true, sessionsOffset);
  }

  $effect(() => {
    if (!active || !component || !name) return;
    if (loadedSessionsKey === `${instanceKey}:sessions`) return;
    sessions = [];
    sessionsTotal = 0;
    sessionsOffset = 0;
    sessionsError = null;
    selectedSessionId = "";
    messages = [];
    messagesTotal = 0;
    messagesOffset = 0;
    messagesError = null;
    loadedMessagesKey = "";
    void loadSessions(true, 0);
  });

  $effect(() => {
    if (!active || !selectedSession) return;
    const key = `${instanceKey}:${selectedSession.session_id}:${selectedSession.message_count}`;
    if (loadedMessagesKey === key) return;
    void loadInitialMessages(selectedSession);
  });
</script>

<div class="history-panel">
  <div class="panel-toolbar">
    <div>
      <h2>{t("historyPanel.title")}</h2>
      <p>{t("historyPanel.subtitle")}</p>
    </div>
    <button class="toolbar-btn" onclick={refreshHistory} disabled={sessionsLoading || messagesLoading}>
      {t("historyPanel.refresh")}
    </button>
  </div>

  {#if sessionsError}
    <div class="panel-state warning">{sessionsError}</div>
  {:else if sessionsLoading && sessions.length === 0}
    <div class="panel-state">{t("historyPanel.loadingSessions")}</div>
  {:else if sessions.length === 0}
    <div class="panel-state">{t("historyPanel.empty")}</div>
  {:else}
    <div class="history-grid">
      <aside class="session-list">
        <div class="session-list-header">
          <span>{t("historyPanel.sessions")}</span>
          <span>
            {#if sessions.length > 0}
              {visibleSessionStart}-{visibleSessionEnd} / {sessionsTotal}
            {:else}
              {sessionsTotal}
            {/if}
          </span>
        </div>
        <div class="session-page-controls">
          <button class="toolbar-btn small" onclick={showNewerSessions} disabled={!canShowNewerSessions}>
            {t("historyPanel.newer")}
          </button>
          <button class="toolbar-btn small" onclick={showOlderSessions} disabled={!canShowOlderSessions}>
            {t("historyPanel.earlier")}
          </button>
        </div>
        {#each sessions as session}
          <button
            class="session-item"
            class:active={session.session_id === selectedSessionId}
            onclick={() => openSession(session)}
          >
            <div class="session-id">{session.session_id}</div>
            <div class="session-meta">
              <span>{translate("historyPanel.messageCount", { count: session.message_count })}</span>
              <span>{formatTimestamp(session.last_message_at)}</span>
            </div>
          </button>
        {/each}
      </aside>

      <section class="message-pane">
        {#if !selectedSession}
          <div class="panel-state">{t("historyPanel.selectSession")}</div>
        {:else}
          <div class="message-header">
            <div>
              <div class="message-title">{selectedSession.session_id}</div>
              <div class="message-subtitle">
                {#if messages.length > 0}
                  {translate("historyPanel.showingRange", {
                    start: messagesOffset + 1,
                    end: messagesOffset + messages.length,
                    total: messagesTotal,
                  })}
                {:else}
                  {translate("historyPanel.totalMessages", { total: messagesTotal })}
                {/if}
              </div>
            </div>
            {#if canLoadOlder}
              <button class="toolbar-btn" onclick={loadOlderMessages} disabled={olderMessagesLoading}>
                {olderMessagesLoading ? t("historyPanel.loadingOlder") : t("historyPanel.loadOlder")}
              </button>
            {/if}
          </div>

          {#if messagesError}
            <div class="panel-state warning">{messagesError}</div>
          {:else if messagesLoading}
            <div class="panel-state">{t("historyPanel.loadingMessages")}</div>
          {:else if messages.length === 0}
            <div class="panel-state">{t("historyPanel.emptySession")}</div>
          {:else}
            <div class="message-list">
              {#each visibleMessages as message}
                <article class={`message-card ${messageClass(message.role)}`}>
                  <header>
                    <span class="message-role">{message.role}</span>
                    <span class="message-time">{formatTimestamp(message.created_at)}</span>
                  </header>
                  <pre>{message.content}</pre>
                </article>
              {/each}
            </div>
          {/if}
        {/if}
      </section>
    </div>
  {/if}
</div>

<style>
  .history-panel {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-lg);
  }

  .panel-toolbar {
    display: flex;
    justify-content: space-between;
    gap: var(--spacing-lg);
    align-items: flex-start;
  }

  .panel-toolbar h2 {
    margin: 0;
    font-size: 1.1rem;
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

  .history-grid {
    display: grid;
    grid-template-columns: minmax(260px, 320px) minmax(0, 1fr);
    gap: var(--spacing-lg);
  }

  .session-list,
  .message-pane {
    border: 1px solid rgba(141, 154, 178, 0.18);
    background: linear-gradient(180deg, rgba(255, 255, 255, 0.82), rgba(245, 249, 255, 0.72));
    border-radius: var(--radius-lg);
    box-shadow: var(--shadow-sm);
  }

  .session-list {
    display: flex;
    flex-direction: column;
    max-height: 720px;
    overflow: auto;
  }

  .session-list-header {
    display: flex;
    justify-content: space-between;
    padding: 0.95rem 1rem;
    border-bottom: 1px solid rgba(141, 154, 178, 0.16);
    color: var(--slate-500);
    font-size: 0.78rem;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    font-weight: 600;
  }

  .session-page-controls {
    display: flex;
    gap: 0.5rem;
    padding: 0.75rem 1rem;
    border-bottom: 1px solid rgba(141, 154, 178, 0.16);
  }

  .toolbar-btn.small {
    padding: 0.45rem 0.7rem;
    font-size: 0.72rem;
  }

  .session-item {
    display: flex;
    flex-direction: column;
    gap: 0.4rem;
    padding: 0.9rem 1rem;
    text-align: left;
    background: transparent;
    border: none;
    border-bottom: 1px solid rgba(141, 154, 178, 0.14);
    color: var(--slate-800);
    cursor: pointer;
  }

  .session-item:hover,
  .session-item.active {
    background: rgba(34, 211, 238, 0.08);
  }

  .session-id {
    font-family: var(--font-mono);
    font-size: 0.78rem;
    word-break: break-all;
  }

  .session-meta {
    display: flex;
    justify-content: space-between;
    gap: 0.75rem;
    color: var(--slate-500);
    font-size: 0.75rem;
  }

  .message-pane {
    display: flex;
    flex-direction: column;
    min-height: 480px;
  }

  .message-header {
    display: flex;
    justify-content: space-between;
    gap: var(--spacing-lg);
    align-items: flex-start;
    padding: 1rem 1.2rem;
    border-bottom: 1px solid rgba(141, 154, 178, 0.16);
  }

  .message-title {
    font-family: var(--font-mono);
    font-size: 0.85rem;
    word-break: break-all;
    color: var(--slate-900);
  }

  .message-subtitle {
    margin-top: 0.25rem;
    color: var(--slate-500);
    font-size: 0.78rem;
  }

  .message-list {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-md);
    padding: 1.2rem;
  }

  .message-card {
    padding: 0.95rem 1rem;
    border-radius: var(--radius-lg);
    border: 1px solid rgba(141, 154, 178, 0.16);
    background: rgba(255, 255, 255, 0.7);
  }

  .message-card.user {
    border-color: rgba(34, 211, 238, 0.18);
  }

  .message-card.assistant {
    border-color: rgba(16, 185, 129, 0.18);
  }

  .message-card.system,
  .message-card.tool {
    border-color: rgba(245, 158, 11, 0.18);
  }

  .message-card header {
    display: flex;
    justify-content: space-between;
    gap: 0.75rem;
    margin-bottom: 0.65rem;
    font-size: 0.76rem;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--slate-500);
  }

  .message-card pre {
    margin: 0;
    white-space: pre-wrap;
    word-break: break-word;
    font-family: var(--font-mono);
    font-size: 0.82rem;
    line-height: 1.55;
    color: var(--slate-800);
  }

  @media (max-width: 900px) {
    .history-grid {
      grid-template-columns: 1fr;
    }
    .panel-toolbar,
    .message-header {
      flex-direction: column;
      align-items: stretch;
    }
  }
</style>
