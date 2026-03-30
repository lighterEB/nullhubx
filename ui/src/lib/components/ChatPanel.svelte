<script lang="ts">
  import { api } from "$lib/api/client";
  import { t } from "$lib/i18n/index.svelte";
  import ModuleFrame from "./ModuleFrame.svelte";

  let {
    port = 0,
    moduleName = "",
    moduleVersion = "",
    instanceKey = "",
    onboardingPending = false,
    starterMessage = "Wake up, my friend!",
    onboardingMarker = "",
  } = $props<{
    port?: number;
    moduleName?: string;
    moduleVersion?: string;
    instanceKey?: string;
    onboardingPending?: boolean;
    starterMessage?: string;
    onboardingMarker?: string;
  }>();

  type HistorySession = {
    session_id: string;
    message_count: number;
  };

  type HistoryMessage = {
    role: string;
    content: string;
    created_at: string;
  };

  type ChatSeedMessage = {
    id: string;
    role: "user" | "assistant" | "system";
    content: string;
    timestamp: number;
    order?: number;
  };

  const DEFAULT_HISTORY_LIMIT = 200;

  const wsUrl = $derived(port > 0 ? `ws://127.0.0.1:${port}/ws` : "");
  const hasModule = $derived(moduleName.length > 0 && moduleVersion.length > 0);
  const mountKey = $derived(`${instanceKey}:${moduleName}:${moduleVersion}:${wsUrl}`);

  let historyReady = $state(false);
  let initialMessages = $state<ChatSeedMessage[]>([]);
  let historyRequestSeq = 0;

  function safeSessionStorageGet(key: string): string | null {
    if (typeof sessionStorage === "undefined") return null;
    try {
      return sessionStorage.getItem(key);
    } catch {
      return null;
    }
  }

  function safeSessionStorageSet(key: string, value: string) {
    if (typeof sessionStorage === "undefined") return;
    try {
      sessionStorage.setItem(key, value);
    } catch {
      /* ignore storage failures */
    }
  }

  function bootstrapAutostartKey(instance: string, marker: string): string {
    const suffix = marker.trim().length > 0 ? marker.trim() : "default";
    return `nullhubx:bootstrap-autostart:${instance}:${suffix}`;
  }

  function shouldAutoStartBootstrap(
    instance: string,
    marker: string,
    pending: boolean,
    messages: ChatSeedMessage[],
  ): boolean {
    if (!pending || messages.length > 0 || !instance) return false;
    return safeSessionStorageGet(bootstrapAutostartKey(instance, marker)) !== "1";
  }

  function markBootstrapAutostarted(instance: string, marker: string) {
    if (!instance) return;
    safeSessionStorageSet(bootstrapAutostartKey(instance, marker), "1");
  }

  let autoSendMessage = $derived.by(() => {
    if (!shouldAutoStartBootstrap(instanceKey, onboardingMarker, onboardingPending, initialMessages)) {
      return "";
    }
    return starterMessage.trim();
  });
  const moduleLabel = $derived(
    hasModule ? `${moduleName}@${moduleVersion}` : t("orchestration.moduleSurface"),
  );
  const panelStatus = $derived.by(() => {
    if (!hasModule) return t("orchestration.unavailableState");
    if (!wsUrl) return t("orchestration.loading");
    if (!historyReady) return t("orchestration.loading");
    return t("orchestration.ready");
  });
  const panelStateTone = $derived.by(() => {
    if (!hasModule) return "warning";
    if (!wsUrl) return "muted";
    if (!historyReady) return "muted";
    return "ready";
  });

  function parseInstanceKey(value: string): { component: string; name: string } | null {
    const slashIndex = value.indexOf("/");
    if (slashIndex <= 0 || slashIndex === value.length - 1) return null;
    return {
      component: value.slice(0, slashIndex),
      name: value.slice(slashIndex + 1),
    };
  }

  function historyRoleToChatRole(role: string): ChatSeedMessage["role"] {
    switch ((role || "").toLowerCase()) {
      case "assistant":
        return "assistant";
      case "system":
      case "tool":
        return "system";
      default:
        return "user";
    }
  }

  function parseHistoryTimestamp(value: string, fallback: number): number {
    const trimmed = (value || "").trim();
    if (!trimmed) return fallback;

    const normalized = /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/.test(trimmed)
      ? trimmed.replace(" ", "T") + "Z"
      : trimmed;
    const parsed = Date.parse(normalized);
    return Number.isFinite(parsed) ? parsed : fallback;
  }

  async function loadLatestHistory(component: string, name: string): Promise<ChatSeedMessage[]> {
    const sessions = await api.getHistory(component, name, { limit: 1, offset: 0 });
    const latestSession = Array.isArray(sessions?.sessions)
      ? (sessions.sessions[0] as HistorySession | undefined)
      : undefined;
    if (!latestSession?.session_id) return [];

    const totalMessages = Math.max(0, Number(latestSession.message_count || 0));
    if (totalMessages === 0) return [];

    const limit = Math.min(DEFAULT_HISTORY_LIMIT, totalMessages);
    const offset = Math.max(totalMessages - limit, 0);
    const transcript = await api.getHistory(component, name, {
      sessionId: latestSession.session_id,
      limit,
      offset,
    });
    const messages = Array.isArray(transcript?.messages)
      ? (transcript.messages as HistoryMessage[])
      : [];

    return messages.map((message, index) => {
      const fallbackTimestamp = Date.now() + index;
      return {
        id: `history-${latestSession.session_id}-${offset + index}`,
        role: historyRoleToChatRole(message.role),
        content: message.content || "",
        timestamp: parseHistoryTimestamp(message.created_at, fallbackTimestamp),
        order: offset + index,
      };
    });
  }

  $effect(() => {
    const parsed = parseInstanceKey(instanceKey);
    if (!hasModule || !wsUrl || !parsed) {
      initialMessages = [];
      historyReady = true;
      return;
    }

    const requestSeq = ++historyRequestSeq;
    historyReady = false;
    initialMessages = [];

    void loadLatestHistory(parsed.component, parsed.name)
      .then((messages) => {
        if (requestSeq !== historyRequestSeq) return;
        initialMessages = messages;
        historyReady = true;
      })
      .catch(() => {
        if (requestSeq !== historyRequestSeq) return;
        initialMessages = [];
        historyReady = true;
      });
  });
</script>

<div class="chat-panel">
  <div class="chat-header">
    <div class="chat-title-group">
      <span class="chat-kicker">{t("orchestration.liveChannel")}</span>
      <strong class="chat-title">{t("orchestration.moduleSurface")}</strong>
      <span class="chat-meta">{moduleLabel}</span>
    </div>
    <span class="chat-status" class:ready={panelStateTone === "ready"} class:warning={panelStateTone === "warning"}>
      {panelStatus}
    </span>
  </div>

  <div class="chat-body">
    {#if hasModule && wsUrl}
      {#if historyReady}
        {#key mountKey}
          <ModuleFrame
            {moduleName}
            {moduleVersion}
            instanceUrl={wsUrl}
            moduleProps={{
              wsUrl,
              pairingCode: "123456",
              initialMessages,
              autoSendMessage,
              onAutoSend: () => markBootstrapAutostarted(instanceKey, onboardingMarker),
            }}
          />
        {/key}
      {:else}
        <div class="chat-unavailable muted">{t("orchestration.loadingHistory")}</div>
      {/if}
    {:else if !hasModule}
      <div class="chat-unavailable warning">
        {t("orchestration.moduleMissing")}
      </div>
    {:else}
      <div class="chat-unavailable muted">{t("orchestration.waitingPort")}</div>
    {/if}
  </div>
</div>

<style>
  .chat-panel {
    display: flex;
    flex-direction: column;
    height: 640px;
    border: 1px solid rgba(34, 211, 238, 0.16);
    border-radius: var(--radius-xl);
    overflow: hidden;
    background:
      linear-gradient(180deg, rgba(10, 15, 28, 0.97), rgba(14, 23, 41, 0.94)),
      radial-gradient(circle at top right, rgba(34, 211, 238, 0.14), transparent 34%);
    box-shadow:
      inset 0 1px 0 rgba(255, 255, 255, 0.05),
      0 24px 70px rgba(2, 8, 23, 0.42);
  }

  .chat-header {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
    gap: var(--spacing-lg);
    padding: 1rem 1.1rem;
    border-bottom: 1px solid rgba(96, 165, 250, 0.14);
    background: rgba(9, 15, 28, 0.7);
    backdrop-filter: blur(16px);
  }

  .chat-title-group {
    display: flex;
    flex-direction: column;
    gap: 0.2rem;
  }

  .chat-kicker {
    color: var(--cyan-300);
    font-family: var(--font-mono);
    font-size: var(--text-xs);
    font-weight: 600;
    letter-spacing: 0.08em;
    text-transform: uppercase;
  }

  .chat-title {
    color: var(--shell-text);
    font-size: 1rem;
    font-weight: 600;
  }

  .chat-meta {
    color: rgba(191, 219, 254, 0.72);
    font-family: var(--font-mono);
    font-size: 0.76rem;
  }

  .chat-status {
    padding: 0.35rem 0.65rem;
    border-radius: 999px;
    border: 1px solid rgba(148, 163, 184, 0.22);
    background: rgba(15, 23, 42, 0.84);
    color: rgba(191, 219, 254, 0.72);
    font-family: var(--font-mono);
    font-size: 0.7rem;
    text-transform: uppercase;
    letter-spacing: 0.08em;
  }

  .chat-status.ready {
    border-color: rgba(34, 211, 238, 0.24);
    color: var(--cyan-300);
    box-shadow: 0 0 18px rgba(34, 211, 238, 0.14);
  }

  .chat-status.warning {
    border-color: rgba(245, 158, 11, 0.24);
    color: #fbbf24;
  }

  .chat-body {
    flex: 1;
    min-height: 0;
    padding: 0.95rem;
  }

  .chat-unavailable {
    display: flex;
    align-items: center;
    justify-content: center;
    height: 100%;
    padding: 2rem;
    border-radius: calc(var(--radius-xl) - 6px);
    border: 1px dashed rgba(96, 165, 250, 0.18);
    background:
      linear-gradient(180deg, rgba(9, 15, 28, 0.92), rgba(12, 20, 34, 0.88)),
      radial-gradient(circle at top right, rgba(34, 211, 238, 0.08), transparent 35%);
    color: rgba(191, 219, 254, 0.8);
    font-size: 0.86rem;
    font-family: var(--font-mono);
    text-transform: uppercase;
    letter-spacing: 0.08em;
    padding: 2rem;
    text-align: center;
    box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.03);
  }

  .chat-unavailable.warning {
    border-color: rgba(245, 158, 11, 0.26);
    color: #fbbf24;
    background:
      linear-gradient(180deg, rgba(24, 18, 6, 0.94), rgba(18, 14, 7, 0.9)),
      radial-gradient(circle at top right, rgba(245, 158, 11, 0.08), transparent 34%);
  }

  .chat-unavailable.muted {
    border-color: rgba(96, 165, 250, 0.14);
    color: rgba(191, 219, 254, 0.76);
  }

  @media (max-width: 760px) {
    .chat-panel {
      height: 560px;
    }

    .chat-header {
      flex-direction: column;
      align-items: stretch;
    }
  }
</style>
