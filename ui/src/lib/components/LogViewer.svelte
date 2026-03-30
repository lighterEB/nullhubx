<script lang="ts">
  import { api } from "$lib/api/client";
  import { SseClient, type SseEvent } from "$lib/sseClient";
  import { t } from "$lib/i18n/index.svelte";
  import type { LogSource } from "$lib/api/client";
  import { toast } from "$lib/toastStore.svelte";

  let { component = "", name = "", initialSource = "instance" as LogSource } = $props();
  let lines = $state<string[]>([]);
  let container: HTMLElement;
  let autoScroll = $state(true);
  let source = $state<LogSource>("instance");
  let lastInitialSource = $state<LogSource>("instance");
  let isConnected = $state(false);
  let sseClient: SseClient | null = null;

  const sourceLabels: Record<LogSource, string> = $derived({
    instance: t("logViewer.sourceInstance"),
    nullhubx: t("logViewer.sourceNullhubx"),
  });
  const logSources: LogSource[] = ["instance", "nullhubx"];
  const LOG_POLL_INTERVAL_MS = 3000;
  const SSE_CONNECT_TIMEOUT_MS = 3000;
  const SSE_RETRY_DELAY_MS = 10000;

  let pollInterval: ReturnType<typeof setInterval> | null = null;
  let sseConnectTimeout: ReturnType<typeof setTimeout> | null = null;
  let sseRetryTimeout: ReturnType<typeof setTimeout> | null = null;
  let transportToken = 0;

  function normalizeLogLines(value: unknown): string[] {
    if (!Array.isArray(value)) return [];
    return value.filter((line): line is string => typeof line === "string");
  }

  function extractSnapshotLines(data: unknown): string[] {
    if (Array.isArray(data)) {
      return normalizeLogLines(data);
    }
    if (data && typeof data === "object") {
      const lines = (data as { lines?: unknown }).lines;
      const normalized = normalizeLogLines(lines);
      if (normalized.length > 0) return normalized;
    }
    if (typeof data === "string") return [data];
    return [];
  }

  function extractLogLine(data: unknown): string | null {
    if (typeof data === "string") return data;
    if (data && typeof data === "object") {
      const line = (data as { line?: unknown }).line;
      return typeof line === "string" ? line : null;
    }
    return null;
  }

  function clearSseConnectTimeout() {
    if (sseConnectTimeout) {
      clearTimeout(sseConnectTimeout);
      sseConnectTimeout = null;
    }
  }

  function clearSseRetryTimeout() {
    if (sseRetryTimeout) {
      clearTimeout(sseRetryTimeout);
      sseRetryTimeout = null;
    }
  }

  async function fetchLogsSnapshot(expectedToken = transportToken) {
    const requestedSource = source;
    try {
      const data = await api.getLogs(component, name, 200, requestedSource);
      if (expectedToken !== transportToken || requestedSource !== source) return;
      lines = normalizeLogLines(data.lines);
      scrollToBottom();
    } catch {
      if (expectedToken !== transportToken) return;
      if (lines.length === 0) lines = [t("logViewer.loadFailed")];
    }
  }

  function stopSseClient() {
    if (sseClient) {
      sseClient.close();
      sseClient = null;
    }
  }

  function scheduleSseRetry(expectedToken: number) {
    clearSseRetryTimeout();
    sseRetryTimeout = setTimeout(() => {
      if (expectedToken !== transportToken) return;
      startTransportCycle();
    }, SSE_RETRY_DELAY_MS);
  }

  function stopFallbackPolling() {
    clearSseRetryTimeout();
    clearSseConnectTimeout();
    if (pollInterval) {
      clearInterval(pollInterval);
      pollInterval = null;
    }
  }

  function startFallbackPolling(expectedToken = transportToken) {
    if (expectedToken !== transportToken) return;
    clearSseConnectTimeout();
    stopSseClient();
    isConnected = false;
    if (!pollInterval) {
      void fetchLogsSnapshot(expectedToken);
      pollInterval = setInterval(() => {
        void fetchLogsSnapshot(expectedToken);
      }, LOG_POLL_INTERVAL_MS);
    }
    scheduleSseRetry(expectedToken);
  }

  function handleSseUnavailable(expectedToken: number) {
    if (expectedToken !== transportToken) return;
    startFallbackPolling(expectedToken);
  }

  function connectSse(expectedToken: number) {
    stopFallbackPolling();
    stopSseClient();
    isConnected = false;

    sseClient = new SseClient({
      bufferSize: 500,
      maxReconnectAttempts: 0,
      onEvent: (event: SseEvent) => {
        if (expectedToken !== transportToken) return;

        if (event.type === "connected") {
          clearSseConnectTimeout();
          stopFallbackPolling();
          isConnected = true;
          lines = [];
          return;
        }

        if (event.type === "snapshot") {
          const snapshotLines = extractSnapshotLines(event.data);
          lines = snapshotLines.length > 0 ? snapshotLines : [JSON.stringify(event.data)];
          scrollToBottom();
          return;
        }

        if (event.type === "log") {
          const logLine = extractLogLine(event.data);
          if (logLine) {
            lines.push(logLine);
            if (lines.length > 500) {
              lines = lines.slice(-500);
            }
            scrollToBottom();
          }
          return;
        }

        if (event.type === "error" || event.type === "end") {
          handleSseUnavailable(expectedToken);
        }
      },
      onError: () => {
        handleSseUnavailable(expectedToken);
      },
      onClose: () => {
        handleSseUnavailable(expectedToken);
      },
    });

    sseClient.connect(component, name, source);

    clearSseConnectTimeout();
    sseConnectTimeout = setTimeout(() => {
      if (expectedToken !== transportToken || isConnected) return;
      handleSseUnavailable(expectedToken);
    }, SSE_CONNECT_TIMEOUT_MS);
  }

  function stopTransport() {
    clearSseRetryTimeout();
    clearSseConnectTimeout();
    stopFallbackPolling();
    stopSseClient();
    isConnected = false;
  }

  function startTransportCycle() {
    if (!component || !name) return;
    const expectedToken = ++transportToken;
    connectSse(expectedToken);
  }

  function scrollToBottom() {
    if (autoScroll && container) {
      requestAnimationFrame(() => {
        container.scrollTop = container.scrollHeight;
      });
    }
  }

  async function clearLogs() {
    try {
      await api.clearLogs(component, name, source);
      lines = [];
    } catch (err) {
      toast.error(err instanceof Error ? err.message : t("error.requestFailed"));
    }
  }

  $effect(() => {
    component;
    name;
    source;

    if (!component || !name) {
      transportToken += 1;
      stopTransport();
      lines = [];
      return;
    }

    startTransportCycle();

    return () => {
      transportToken += 1;
      stopTransport();
    };
  });

  $effect(() => {
    if (initialSource !== lastInitialSource) {
      source = initialSource;
      lastInitialSource = initialSource;
    }
  });
</script>

<div class="log-viewer">
  <div class="log-header">
    <div class="log-title-group">
      <span>{t("logViewer.title")}</span>
      <div class="source-switch" role="tablist" aria-label={t("logViewer.sourceLabel")}>
        {#each logSources as option}
          <button
            type="button"
            class="source-btn"
            class:active={source === option}
            onclick={() => (source = option)}
          >
            {sourceLabels[option]}
          </button>
        {/each}
      </div>
      {#if isConnected}
        <span class="live-indicator">● {t("logViewer.live")}</span>
      {:else}
        <span class="polling-indicator">○ {t("logViewer.polling")}</span>
      {/if}
    </div>
    <div class="log-actions">
      <button class="clear-btn" onclick={clearLogs}>{t("logViewer.clear")}</button>
      <label class="auto-scroll">
        <input type="checkbox" bind:checked={autoScroll} />
        {t("logViewer.autoScroll")}
      </label>
    </div>
  </div>
  <div class="log-content" bind:this={container}>
    {#each lines as line}
      <div class="log-line">{line}</div>
    {/each}
    {#if lines.length === 0}
      <div class="log-empty">{t("logViewer.emptyLogs").replace("{source}", sourceLabels[source])}</div>
    {/if}
  </div>
</div>

<style>
  .log-viewer {
    display: flex;
    flex-direction: column;
    height: 460px;
    background:
      linear-gradient(180deg, rgba(10, 16, 29, 0.98), rgba(14, 22, 38, 0.96)),
      radial-gradient(circle at top right, rgba(34, 211, 238, 0.12), transparent 28%);
    border: 1px solid rgba(116, 136, 173, 0.24);
    border-radius: var(--radius-lg);
    box-shadow: var(--glow-cyan);
    overflow: hidden;
  }

  .log-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: var(--spacing-md);
    padding: 0.9rem 1rem;
    border-bottom: 1px solid rgba(116, 136, 173, 0.18);
    background: rgba(255, 255, 255, 0.03);
  }

  .log-title-group {
    display: flex;
    align-items: center;
    gap: var(--spacing-md);
    min-width: 0;
    flex-wrap: wrap;
  }

  .log-title-group > span:first-child {
    color: var(--shell-text);
    font-size: var(--text-sm);
    font-weight: 600;
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }

  .source-switch {
    display: inline-flex;
    align-items: center;
    gap: 0.375rem;
    padding: 0.25rem;
    border: 1px solid rgba(116, 136, 173, 0.2);
    border-radius: 999px;
    background: rgba(255, 255, 255, 0.06);
  }

  .source-btn {
    padding: 0.4rem 0.8rem;
    border: 1px solid transparent;
    border-radius: 999px;
    background: transparent;
    color: var(--shell-text-dim);
    font-size: 0.6875rem;
    font-family: var(--font-mono);
    text-transform: uppercase;
    letter-spacing: 0.8px;
    transition: all var(--transition-fast);
  }

  .source-btn:hover {
    background: rgba(255, 255, 255, 0.08);
  }

  .source-btn.active {
    color: var(--shell-text);
    border-color: rgba(34, 211, 238, 0.22);
    background: linear-gradient(135deg, rgba(34, 211, 238, 0.18), rgba(139, 92, 246, 0.14));
    box-shadow: inset 0 0 14px rgba(34, 211, 238, 0.12);
  }

  .live-indicator,
  .polling-indicator {
    display: inline-flex;
    align-items: center;
    gap: 0.35rem;
    font-family: var(--font-mono);
    font-size: var(--text-xs);
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }

  .live-indicator {
    color: var(--cyan-300);
  }

  .polling-indicator {
    color: var(--shell-text-dim);
  }

  .log-content {
    flex: 1;
    overflow-y: auto;
    padding: 1rem 1rem 1.2rem;
    font-family: var(--font-mono);
    font-size: 0.8rem;
    line-height: 1.6;
    color: #dce8ff;
    background:
      linear-gradient(180deg, rgba(8, 13, 24, 0.82), rgba(9, 15, 26, 0.9)),
      linear-gradient(rgba(34, 211, 238, 0.05) 1px, transparent 1px);
    background-size: auto, 100% 28px;
  }

  .log-line {
    white-space: pre-wrap;
    word-break: break-all;
    margin-bottom: 0.2rem;
    padding: 0.18rem 0.45rem;
    border-radius: 8px;
  }

  .log-line:hover {
    background: rgba(34, 211, 238, 0.08);
  }

  .log-empty {
    color: var(--shell-text-dim);
    text-align: center;
    padding: 3rem;
    line-height: 1.7;
  }

  .log-actions {
    display: flex;
    align-items: center;
    gap: var(--spacing-md);
    flex-wrap: wrap;
  }

  .clear-btn {
    padding: 0.45rem 0.85rem;
    border: 1px solid rgba(244, 63, 94, 0.22);
    border-radius: 999px;
    background: rgba(244, 63, 94, 0.08);
    color: #ffb0c0;
    font-size: 0.75rem;
    font-family: var(--font-mono);
    text-transform: uppercase;
    cursor: pointer;
    transition: all var(--transition-fast);
  }

  .clear-btn:hover {
    background: rgba(244, 63, 94, 0.14);
    border-color: rgba(244, 63, 94, 0.32);
    box-shadow: 0 0 18px rgba(244, 63, 94, 0.12);
  }

  .auto-scroll {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    font-size: 0.75rem;
    color: var(--shell-text-dim);
    cursor: pointer;
    text-transform: uppercase;
    letter-spacing: 0.5px;
  }

  .auto-scroll input[type="checkbox"] {
    appearance: none;
    width: 14px;
    height: 14px;
    border: 1px solid rgba(116, 136, 173, 0.32);
    background: rgba(255, 255, 255, 0.04);
    border-radius: 4px;
    position: relative;
    cursor: pointer;
  }

  .auto-scroll input[type="checkbox"]:checked {
    background: rgba(34, 211, 238, 0.14);
    border-color: rgba(34, 211, 238, 0.3);
    box-shadow: inset 0 0 8px rgba(34, 211, 238, 0.2);
  }

  .auto-scroll input[type="checkbox"]:checked::after {
    content: "";
    position: absolute;
    top: 2px;
    left: 2px;
    width: 8px;
    height: 8px;
    background: var(--cyan-500);
    border-radius: 1px;
    box-shadow: 0 0 6px rgba(34, 211, 238, 0.24);
  }

  @media (max-width: 760px) {
    .log-header {
      flex-direction: column;
      align-items: stretch;
    }
    .log-title-group {
      justify-content: space-between;
      flex-wrap: wrap;
    }
    .log-actions {
      justify-content: space-between;
    }
  }
</style>
