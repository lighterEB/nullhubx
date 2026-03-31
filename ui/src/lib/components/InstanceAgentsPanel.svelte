<script lang="ts">
  import { onMount } from "svelte";
  import {
    api,
    type AgentMutationResponse,
    type AgentBindingsResponse,
    type AgentProfilesResponse,
    type AnyRecord,
  } from "$lib/api/client";
  import { getChannelSchemas } from "$lib/components/configSchemas";
  import { t } from "$lib/i18n/index.svelte";

  type AgentProfile = {
    id: string;
    provider: string;
    model: string;
    system_prompt?: string;
    temperature?: number | null;
    max_depth?: number | null;
  };

  type AgentBinding = {
    agent_id: string;
    match: {
      channel: string;
      account_id?: string;
      peer: {
        kind: string;
        id: string;
      };
    };
  };

  type AgentTab = "profiles" | "bindings";
  type BindingAdvisory = {
    tone: "info" | "warn";
    message: string;
  };
  type SaveNotice = {
    tone: "success" | "info" | "warn";
    title: string;
    detail: string;
    meta: string;
    showRefresh: boolean;
    showRestart: boolean;
  };
  type BindingTemplate = "groupFallback" | "topicExact" | "dmDirect";
  type RoutePreviewDraft = {
    channel: string;
    account_id: string;
    peer_kind: string;
    peer_id: string;
    roles: string;
  };
  type RoutePreviewStep = {
    key: "peerScoped" | "peerAnyAccount" | "groupScoped" | "groupAnyAccount" | "defaultFallback";
    matched: boolean;
    detail: string;
  };
  type RoutePreviewResult = {
    status: "incomplete" | "matched" | "fallback";
    agentId: string;
    reason: string;
    tierKey: RoutePreviewStep["key"] | "incomplete";
    matchedBindingIndex: number | null;
    matchedBindingSummary: string | null;
    steps: RoutePreviewStep[];
    ignoresRoles: boolean;
  };

  let {
    component = "",
    name = "",
    active = false,
    runtimeStatus = "unknown",
    canRestart = false,
    onSaved,
    onRequestRestart,
  }: {
    component?: string;
    name?: string;
    active?: boolean;
    runtimeStatus?: string;
    canRestart?: boolean;
    onSaved?: (() => void | Promise<void>) | undefined;
    onRequestRestart?: (() => void) | undefined;
  } = $props();

  let loaded = $state(false);
  let loading = $state(false);
  let savingProfiles = $state(false);
  let savingBindings = $state(false);
  let savingAll = $state(false);
  let error = $state("");
  let saveNotice = $state<SaveNotice | null>(null);
  let channelSchemas = $derived(getChannelSchemas());

  let activeTab = $state<AgentTab>("profiles");

  let defaultsModelPrimary = $state("");
  let profiles = $state<AgentProfile[]>([]);
  let bindings = $state<AgentBinding[]>([]);
  let persistedProfileIds = $state<string[]>([]);
  let providerOptions = $state<string[]>([]);
  let modelOptions = $state<string[]>([]);
  let configuredChannelOptions = $state<string[]>([]);
  let channelAccountMap = $state<Record<string, string[]>>({});

  let baselineProfilesSignature = $state("");
  let baselineBindingsSignature = $state("");
  let routePreview = $state<RoutePreviewDraft>({
    channel: "",
    account_id: "",
    peer_kind: "direct",
    peer_id: "",
    roles: "",
  });

  const channelOptions = $derived(Object.keys(channelSchemas).sort());
  const peerKindOptions = ["direct", "group", "channel"];
  const peerExamples: Record<string, Record<string, string>> = {
    telegram: {
      direct: "123456789",
      group: "-1001234567890 or -1001234567890:thread:42",
      channel: "@channelusername",
    },
    discord: {
      direct: "123456789012345678",
      group: "123456789012345678 or 123456789012345678:thread:42",
      channel: "123456789012345678",
    },
    slack: {
      direct: "U12345678",
      group: "C12345678 or C12345678:thread:1700000000.000200",
      channel: "C12345678",
    },
    whatsapp: {
      direct: "+15551234567",
      group: "1203630XXXXXXXX@g.us",
      channel: "status-or-broadcast-id",
    },
    matrix: {
      direct: "@alice:matrix.org",
      group: "!roomid:matrix.org",
      channel: "!roomid:matrix.org",
    },
    email: {
      direct: "user@example.com",
      group: "team@example.com",
      channel: "inbox@example.com",
    },
    default: {
      direct: "user-123",
      group: "group-123",
      channel: "channel-123",
    },
  };

  function translate(key: string, replacements?: Record<string, string | number>): string {
    let message = t(key);
    if (!replacements) return message;

    for (const [name, value] of Object.entries(replacements)) {
      message = message.replace(`{${name}}`, String(value));
    }

    return message;
  }

  function normalizeError(err: unknown): string {
    return err instanceof Error ? err.message : t("agentsPanel.requestFailed");
  }

  function asRecord(value: unknown): Record<string, unknown> | null {
    if (value && typeof value === "object" && !Array.isArray(value)) {
      return value as Record<string, unknown>;
    }
    return null;
  }

  function addTrimmed(target: Set<string>, value: unknown) {
    if (typeof value !== "string") return;
    const trimmed = value.trim();
    if (trimmed) target.add(trimmed);
  }

  function parseProviderModelRef(value: string): { provider: string; model: string } | null {
    const trimmed = value.trim();
    if (!trimmed || !trimmed.includes("/") || trimmed.startsWith("/") || trimmed.endsWith("/")) {
      return null;
    }
    const slash = trimmed.indexOf("/");
    const provider = trimmed.slice(0, slash).trim();
    const model = trimmed.slice(slash + 1).trim();
    if (!provider || !model) return null;
    return { provider, model };
  }

  function collectAccountIds(node: unknown, out: Set<string>) {
    if (Array.isArray(node)) {
      for (const item of node) collectAccountIds(item, out);
      return;
    }

    const obj = asRecord(node);
    if (!obj) return;

    addTrimmed(out, obj.account_id);

    const accountsObj = asRecord(obj.accounts);
    if (accountsObj) {
      for (const [accountKey, accountValue] of Object.entries(accountsObj)) {
        addTrimmed(out, accountKey);
        collectAccountIds(accountValue, out);
      }
    }

    for (const [key, value] of Object.entries(obj)) {
      if (key === "accounts") continue;
      if (value && typeof value === "object") collectAccountIds(value, out);
    }
  }

  function mergeAccountSuggestion(map: Map<string, Set<string>>, channel: string, accountId: string) {
    const normalizedChannel = channel.trim().toLowerCase();
    const normalizedAccount = accountId.trim();
    if (!normalizedChannel || !normalizedAccount) return;
    const entry = map.get(normalizedChannel) ?? new Set<string>();
    entry.add(normalizedAccount);
    map.set(normalizedChannel, entry);
  }

  function refreshFormSupport(config: AnyRecord, nextProfiles: AgentProfile[], nextBindings: AgentBinding[], defaultPrimary: string) {
    const nextProviders = new Set<string>();
    const nextModels = new Set<string>();
    const nextConfiguredChannels = new Set<string>();
    const accountSuggestions = new Map<string, Set<string>>();

    const modelsObj = asRecord(config.models);
    const providerObj = asRecord(modelsObj?.providers);
    if (providerObj) {
      for (const providerName of Object.keys(providerObj)) {
        addTrimmed(nextProviders, providerName);
      }
    }

    const defaultRef = parseProviderModelRef(defaultPrimary);
    if (defaultRef) {
      nextProviders.add(defaultRef.provider);
      nextModels.add(defaultRef.model);
    }

    for (const profile of nextProfiles) {
      addTrimmed(nextProviders, profile.provider);
      addTrimmed(nextModels, profile.model);
    }

    const channelsObj = asRecord(config.channels);
    if (channelsObj) {
      for (const [channelName, channelValue] of Object.entries(channelsObj)) {
        const normalizedChannel = channelName.trim();
        if (!normalizedChannel) continue;
        nextConfiguredChannels.add(normalizedChannel);
        const accounts = new Set<string>();
        collectAccountIds(channelValue, accounts);
        if (accounts.size > 0) {
          accountSuggestions.set(normalizedChannel.toLowerCase(), accounts);
        }
      }
    }

    for (const binding of nextBindings) {
      addTrimmed(nextConfiguredChannels, binding.match.channel);
      if (binding.match.account_id) {
        mergeAccountSuggestion(accountSuggestions, binding.match.channel, binding.match.account_id);
      }
    }

    providerOptions = [...nextProviders].sort();
    modelOptions = [...nextModels].sort();
    configuredChannelOptions = [...nextConfiguredChannels].sort();
    channelAccountMap = Object.fromEntries(
      [...accountSuggestions.entries()].map(([channelName, accounts]) => [channelName, [...accounts].sort()]),
    );
  }

  function clearFeedback() {
    error = "";
    saveNotice = null;
  }

  function buildBindingChannelOptions(): string[] {
    const combined = new Set<string>();
    for (const channelName of configuredChannelOptions) combined.add(channelName);
    for (const channelName of channelOptions) combined.add(channelName);
    return [...combined];
  }

  function channelDisplayName(channel: string): string {
    const trimmed = channel.trim();
    if (!trimmed) return t("agentsPanel.pendingChannel");
    const schema = channelSchemas[trimmed.toLowerCase()];
    return schema?.label || trimmed;
  }

  function bindingAccountsForChannel(channel: string): string[] {
    return channelAccountMap[channel.trim().toLowerCase()] ?? [];
  }

  function providerHint(): string {
    if (providerOptions.length === 0) return t("agentsPanel.providerHintMissing");
    return translate("agentsPanel.providerHintAvailable", {
      providers: providerOptions.join(", "),
    });
  }

  function modelHint(profile: AgentProfile): string {
    if (profile.provider.trim()) {
      return translate("agentsPanel.modelHintWithProvider", {
        provider: profile.provider.trim(),
      });
    }
    return t("agentsPanel.modelHint");
  }

  function accountHint(binding: AgentBinding): string {
    const channel = binding.match.channel.trim();
    if (!channel) return t("agentsPanel.accountHintSelectChannel");
    const accounts = bindingAccountsForChannel(channel);
    if (accounts.length === 0) {
      return translate("agentsPanel.accountHintMissing", {
        channel: channelDisplayName(channel),
      });
    }
    return translate("agentsPanel.accountHintAvailable", {
      channel: channelDisplayName(channel),
      accounts: accounts.join(", "),
    });
  }

  function peerExample(channel: string, peerKind: string): string {
    const normalizedChannel = channel.trim().toLowerCase();
    const normalizedPeerKind = peerKind.trim().toLowerCase();
    return (
      peerExamples[normalizedChannel]?.[normalizedPeerKind] ||
      peerExamples.default[normalizedPeerKind] ||
      peerExamples.default.direct
    );
  }

  function bindingPeerPlaceholder(binding: AgentBinding): string {
    return peerExample(binding.match.channel, binding.match.peer.kind);
  }

  function bindingPeerHint(binding: AgentBinding): string {
    const channel = channelDisplayName(binding.match.channel);
    const kind = binding.match.peer.kind.trim().toLowerCase();
    const example = peerExample(binding.match.channel, binding.match.peer.kind);

    if (kind === "group") {
      return translate("agentsPanel.peerHintGroup", {
        channel,
        example,
      });
    }
    if (kind === "channel") {
      return translate("agentsPanel.peerHintChannel", {
        channel,
        example,
      });
    }
    return translate("agentsPanel.peerHintDirect", {
      channel,
      example,
    });
  }

  function templateDefaultChannel(template: BindingTemplate): string {
    const preferences: Record<BindingTemplate, string[]> = {
      groupFallback: ["telegram", "discord", "slack"],
      topicExact: ["telegram", "discord"],
      dmDirect: ["telegram", "whatsapp", "discord", "email"],
    };

    const preferredConfigured = configuredChannelOptions.find((channelName) =>
      preferences[template].includes(channelName.toLowerCase()),
    );
    if (preferredConfigured) return preferredConfigured;

    const preferredKnown = channelOptions.find((channelName) => preferences[template].includes(channelName.toLowerCase()));
    if (preferredKnown) return preferredKnown;

    return configuredChannelOptions[0] || channelOptions[0] || "";
  }

  function templateDefaultAccount(channel: string): string {
    return bindingAccountsForChannel(channel)[0] || "";
  }

  function templatePeerId(template: BindingTemplate, channel: string): string {
    switch (template) {
      case "groupFallback":
        if (channel.trim().toLowerCase() === "telegram") return "-1001234567890";
        if (channel.trim().toLowerCase() === "discord") return "123456789012345678";
        if (channel.trim().toLowerCase() === "slack") return "C12345678";
        return "group-123";
      case "topicExact":
        if (channel.trim().toLowerCase() === "telegram") return "-1001234567890:thread:42";
        if (channel.trim().toLowerCase() === "discord") return "123456789012345678:thread:42";
        return "group-123:thread:42";
      case "dmDirect":
        return peerExample(channel, "direct");
    }
  }

  function createBindingTemplate(template: BindingTemplate): AgentBinding {
    const channel = templateDefaultChannel(template);
    return {
      agent_id: "",
      match: {
        channel,
        account_id: templateDefaultAccount(channel),
        peer: {
          kind: template === "dmDirect" ? "direct" : "group",
          id: templatePeerId(template, channel),
        },
      },
    };
  }

  function isLiveRuntimeStatus(status: string): boolean {
    return ["running", "starting", "restarting", "stopping"].includes(status);
  }

  function buildSaveNotice(response: AgentMutationResponse, title: string): SaveNotice {
    const applyState = response.apply_state || "config_saved";
    const runtimeEffect = response.runtime_effect || "component_defined";

    const detailParts: string[] = [];
    let tone: SaveNotice["tone"] = "info";
    let showRestart = false;

    if (runtimeStatus === "stopped") {
      tone = "success";
      detailParts.push(t("agentsPanel.feedback.runtimeStopped"));
    } else if (runtimeStatus === "failed") {
      tone = "warn";
      detailParts.push(t("agentsPanel.feedback.runtimeFailed"));
      showRestart = canRestart;
    } else if (isLiveRuntimeStatus(runtimeStatus)) {
      tone = "warn";
      detailParts.push(t("agentsPanel.feedback.runtimeRunning"));
      showRestart = canRestart;
    } else {
      tone = "info";
      detailParts.push(t("agentsPanel.feedback.runtimeUnknown"));
    }

    if (onSaved) {
      detailParts.push(t("agentsPanel.feedback.summaryRefreshed"));
    }

    return {
      tone,
      title,
      detail: detailParts.join(" "),
      meta: translate("agentsPanel.feedback.meta", {
        applyState,
        runtimeEffect,
      }),
      showRefresh: Boolean(onSaved),
      showRestart: showRestart && Boolean(onRequestRestart),
    };
  }

  async function refreshSummaryAfterSave() {
    await onSaved?.();
  }

  async function finalizeSave(response: AgentMutationResponse, title: string) {
    await load();
    await refreshSummaryAfterSave();
    saveNotice = buildSaveNotice(response, title);
  }

  function defaultModelIssue(value: string): string | null {
    const trimmed = value.trim();
    if (!trimmed) return null;
    if (trimmed.startsWith("custom:")) return null;
    if (!trimmed.includes("/")) return t("agentsPanel.defaultModelFormat");
    if (trimmed.startsWith("/") || trimmed.endsWith("/")) return t("agentsPanel.defaultModelFormat");
    return null;
  }

  function normalizeProfilesForSave(sourceProfiles: AgentProfile[]) {
    return sourceProfiles.map((profile) => ({
      id: profile.id.trim(),
      provider: profile.provider.trim(),
      model: profile.model.trim(),
      system_prompt: profile.system_prompt?.trim() || undefined,
      temperature:
        profile.temperature === null || profile.temperature === undefined || Number.isNaN(profile.temperature)
          ? undefined
          : profile.temperature,
      max_depth: profile.max_depth || 3,
    }));
  }

  function normalizeBindingsForSave(sourceBindings: AgentBinding[]) {
    return sourceBindings.map((binding) => ({
      agent_id: binding.agent_id.trim(),
      match: {
        channel: binding.match.channel.trim(),
        account_id: binding.match.account_id?.trim() || undefined,
        peer: {
          kind: binding.match.peer.kind.trim(),
          id: binding.match.peer.id.trim(),
        },
      },
    }));
  }

  function serializeProfilesSignature(modelPrimary: string, sourceProfiles: AgentProfile[]): string {
    return JSON.stringify({
      defaults: { model_primary: modelPrimary.trim() },
      profiles: normalizeProfilesForSave(sourceProfiles),
    });
  }

  function serializeBindingsSignature(sourceBindings: AgentBinding[]): string {
    return JSON.stringify({
      bindings: normalizeBindingsForSave(sourceBindings),
    });
  }

  function buildProfileIssues() {
    const counts = new Map<string, number>();
    for (const profile of profiles) {
      const id = profile.id.trim();
      if (!id) continue;
      counts.set(id, (counts.get(id) ?? 0) + 1);
    }

    return profiles.map((profile) => {
      const issues: string[] = [];
      const id = profile.id.trim();
      const provider = profile.provider.trim();
      const model = profile.model.trim();
      const maxDepth = profile.max_depth ?? 0;

      if (!id) issues.push(t("agentsPanel.idRequired"));
      if (id && (counts.get(id) ?? 0) > 1) issues.push(t("agentsPanel.idUnique"));
      if (!provider) issues.push(t("agentsPanel.providerRequired"));
      if (!model) issues.push(t("agentsPanel.modelRequired"));
      if (maxDepth < 1 || maxDepth > 8) issues.push(t("agentsPanel.maxDepthRange"));

      return issues;
    });
  }

  function buildBindingIssues() {
    const validAgentIds = new Set<string>();
    for (const profile of profiles) {
      const id = profile.id.trim();
      if (id) validAgentIds.add(id);
    }
    validAgentIds.add("main");
    validAgentIds.add("default");

    const scopeKeyCount = new Map<string, number>();
    const duplicateKeyCount = new Map<string, number>();
    for (const binding of bindings) {
      const scopeKey = bindingExactScopeKey(binding);
      const routeKey = bindingExactRouteKey(binding);
      if (scopeKey) {
        scopeKeyCount.set(scopeKey, (scopeKeyCount.get(scopeKey) ?? 0) + 1);
      }
      if (routeKey) {
        duplicateKeyCount.set(routeKey, (duplicateKeyCount.get(routeKey) ?? 0) + 1);
      }
    }

    return bindings.map((binding) => {
      const issues: string[] = [];
      const agentId = normalizedBindingAgentId(binding);
      const channel = binding.match.channel.trim();
      const peerKind = binding.match.peer.kind.trim();
      const peerId = binding.match.peer.id.trim();
      const scopeKey = bindingExactScopeKey(binding);
      const routeKey = bindingExactRouteKey(binding);

      if (!agentId) issues.push(t("agentsPanel.agentIdRequired"));
      if (agentId && !validAgentIds.has(agentId)) issues.push(t("agentsPanel.agentIdMatchProfile"));
      if (!channel) issues.push(t("agentsPanel.channelRequired"));
      if (!peerKind) issues.push(t("agentsPanel.peerKindRequired"));
      if (!peerId) issues.push(t("agentsPanel.peerIdRequired"));
      if (routeKey && (duplicateKeyCount.get(routeKey) || 0) > 1) {
        issues.push(t("agentsPanel.duplicateRoute"));
      } else if (scopeKey && (scopeKeyCount.get(scopeKey) || 0) > 1) {
        issues.push(t("agentsPanel.conflictingScope"));
      }

      return issues;
    });
  }

  function normalizedBindingAgentId(binding: AgentBinding): string {
    return binding.agent_id.trim();
  }

  function normalizedBindingChannel(binding: AgentBinding): string {
    return binding.match.channel.trim().toLowerCase();
  }

  function normalizedBindingAccount(binding: AgentBinding): string {
    return (binding.match.account_id || "").trim().toLowerCase();
  }

  function normalizedBindingPeerKind(binding: AgentBinding): string {
    return binding.match.peer.kind.trim().toLowerCase();
  }

  function normalizedBindingPeerId(binding: AgentBinding): string {
    return binding.match.peer.id.trim();
  }

  function hasExactPeer(binding: AgentBinding): boolean {
    return normalizedBindingPeerKind(binding).length > 0 && normalizedBindingPeerId(binding).length > 0;
  }

  function hasCompleteBindingScope(binding: AgentBinding): boolean {
    return normalizedBindingChannel(binding).length > 0 && hasExactPeer(binding);
  }

  function bindingExactScopeKey(binding: AgentBinding): string {
    if (!hasCompleteBindingScope(binding)) return "";
    return [
      normalizedBindingChannel(binding),
      normalizedBindingAccount(binding),
      normalizedBindingPeerKind(binding),
      normalizedBindingPeerId(binding),
    ].join("|");
  }

  function bindingExactRouteKey(binding: AgentBinding): string {
    const scopeKey = bindingExactScopeKey(binding);
    if (!scopeKey) return "";
    return [normalizedBindingAgentId(binding), scopeKey].join("|");
  }

  function bindingPriorityKey(binding: AgentBinding): string {
    if (hasExactPeer(binding)) {
      return normalizedBindingAccount(binding) ? "peerScoped" : "peerAnyAccount";
    }
    if (normalizedBindingAccount(binding)) return "accountFallback";
    if (normalizedBindingChannel(binding)) return "channelFallback";
    return "incomplete";
  }

  function bindingPriorityLabel(binding: AgentBinding): string {
    return t(`agentsPanel.priority.${bindingPriorityKey(binding)}`);
  }

  function bindingScopeSummary(binding: AgentBinding): string {
    const agentId = binding.agent_id.trim() || t("agentsPanel.unassignedAgent");
    const channel = binding.match.channel.trim() || t("agentsPanel.pendingChannel");
    const accountId = binding.match.account_id?.trim() || "";
    const peerKind = binding.match.peer.kind.trim() || t("agentsPanel.pendingPeerKind");
    const peerId = binding.match.peer.id.trim() || t("agentsPanel.pendingPeerId");

    switch (bindingPriorityKey(binding)) {
      case "peerScoped":
        return translate("agentsPanel.summary.peerScoped", {
          channel,
          account: accountId,
          peerKind,
          peerId,
          agentId,
        });
      case "peerAnyAccount":
        return translate("agentsPanel.summary.peerAnyAccount", {
          channel,
          peerKind,
          peerId,
          agentId,
        });
      case "accountFallback":
        return translate("agentsPanel.summary.accountFallback", {
          channel,
          account: accountId,
          agentId,
        });
      case "channelFallback":
        return translate("agentsPanel.summary.channelFallback", {
          channel,
          agentId,
        });
      default:
        return t("agentsPanel.summary.incomplete");
    }
  }

  function accountBadgeLabel(binding: AgentBinding): string {
    const accountId = binding.match.account_id?.trim();
    if (!accountId) return t("agentsPanel.anyAccount");
    return translate("agentsPanel.accountScoped", { account: accountId });
  }

  function peerBadgeLabel(binding: AgentBinding): string {
    const peerKind = binding.match.peer.kind.trim();
    const peerId = binding.match.peer.id.trim();
    if (!peerKind && !peerId) return t("agentsPanel.pendingPeer");
    if (!peerKind || !peerId) return t("agentsPanel.pendingPeer");
    return translate("agentsPanel.peerScopedBadge", {
      peerKind,
      peerId,
    });
  }

  function threadParentPeerId(peerId: string): string | null {
    const marker = ":thread:";
    const markerIndex = peerId.lastIndexOf(marker);
    if (markerIndex === -1) return null;
    return peerId.slice(0, markerIndex);
  }

  function maybeSeedRoutePreview(nextBindings: AgentBinding[]) {
    if (routePreview.channel || routePreview.account_id || routePreview.peer_id || routePreview.roles) return;
    if (nextBindings.length === 0) return;

    const first = nextBindings[0];
    routePreview = {
      channel: first.match.channel ?? "",
      account_id: first.match.account_id ?? "",
      peer_kind: first.match.peer.kind ?? "direct",
      peer_id: first.match.peer.id ?? "",
      roles: "",
    };
  }

  function routePreviewChannelHint(): string {
    if (configuredChannelOptions.length === 0) return t("agentsPanel.channelHintMissing");
    return translate("agentsPanel.channelHintAvailable", {
      channels: configuredChannelOptions.join(", "),
    });
  }

  function routePreviewAccountHint(): string {
    return accountHint({
      agent_id: "",
      match: {
        channel: routePreview.channel,
        account_id: routePreview.account_id,
        peer: {
          kind: routePreview.peer_kind,
          id: routePreview.peer_id,
        },
      },
    });
  }

  function routePreviewPeerHint(): string {
    return bindingPeerHint({
      agent_id: "",
      match: {
        channel: routePreview.channel,
        account_id: routePreview.account_id,
        peer: {
          kind: routePreview.peer_kind,
          id: routePreview.peer_id,
        },
      },
    });
  }

  function findBindingPreviewMatch(
    predicate: (binding: AgentBinding) => boolean,
  ): { binding: AgentBinding; index: number } | null {
    for (const [index, binding] of bindings.entries()) {
      if (predicate(binding)) return { binding, index };
    }
    return null;
  }

  function previewStepDetail(
    matched: { binding: AgentBinding; index: number } | null,
    fallbackMessage: string,
  ): string {
    if (!matched) return fallbackMessage;
    return translate("agentsPanel.preview.stepMatched", {
      index: matched.index + 1,
      summary: bindingScopeSummary(matched.binding),
    });
  }

  function buildRoutePreviewResult(): RoutePreviewResult {
    const channel = routePreview.channel.trim().toLowerCase();
    const account = routePreview.account_id.trim().toLowerCase();
    const peerKind = routePreview.peer_kind.trim().toLowerCase();
    const peerId = routePreview.peer_id.trim();
    const ignoresRoles = routePreview.roles.trim().length > 0;

    if (!channel || !peerKind || !peerId) {
      return {
        status: "incomplete",
        agentId: "",
        reason: t("agentsPanel.preview.incomplete"),
        tierKey: "incomplete",
        matchedBindingIndex: null,
        matchedBindingSummary: null,
        steps: [],
        ignoresRoles,
      };
    }

    const steps: RoutePreviewStep[] = [];
    const exactScoped = account
      ? findBindingPreviewMatch((binding) =>
          normalizedBindingChannel(binding) === channel &&
          normalizedBindingAccount(binding) === account &&
          normalizedBindingPeerKind(binding) === peerKind &&
          normalizedBindingPeerId(binding) === peerId
        )
      : null;
    steps.push({
      key: "peerScoped",
      matched: Boolean(exactScoped),
      detail: previewStepDetail(exactScoped, t("agentsPanel.preview.stepNoMatch")),
    });
    if (exactScoped) {
      return {
        status: "matched",
        agentId: exactScoped.binding.agent_id.trim() || "main/default",
        reason: t("agentsPanel.preview.reason.peerScoped"),
        tierKey: "peerScoped",
        matchedBindingIndex: exactScoped.index,
        matchedBindingSummary: bindingScopeSummary(exactScoped.binding),
        steps,
        ignoresRoles,
      };
    }

    const exactAnyAccount = findBindingPreviewMatch((binding) =>
      normalizedBindingChannel(binding) === channel &&
      normalizedBindingAccount(binding).length === 0 &&
      normalizedBindingPeerKind(binding) === peerKind &&
      normalizedBindingPeerId(binding) === peerId
    );
    steps.push({
      key: "peerAnyAccount",
      matched: Boolean(exactAnyAccount),
      detail: previewStepDetail(exactAnyAccount, t("agentsPanel.preview.stepNoMatch")),
    });
    if (exactAnyAccount) {
      return {
        status: "matched",
        agentId: exactAnyAccount.binding.agent_id.trim() || "main/default",
        reason: t("agentsPanel.preview.reason.peerAnyAccount"),
        tierKey: "peerAnyAccount",
        matchedBindingIndex: exactAnyAccount.index,
        matchedBindingSummary: bindingScopeSummary(exactAnyAccount.binding),
        steps,
        ignoresRoles,
      };
    }

    const parentPeerId = threadParentPeerId(peerId);
    if (parentPeerId) {
      const groupScoped = account
        ? findBindingPreviewMatch((binding) =>
            normalizedBindingChannel(binding) === channel &&
            normalizedBindingAccount(binding) === account &&
            normalizedBindingPeerKind(binding) === peerKind &&
            normalizedBindingPeerId(binding) === parentPeerId
          )
        : null;
      steps.push({
        key: "groupScoped",
        matched: Boolean(groupScoped),
        detail: previewStepDetail(groupScoped, t("agentsPanel.preview.stepNoMatch")),
      });
      if (groupScoped) {
        return {
          status: "matched",
          agentId: groupScoped.binding.agent_id.trim() || "main/default",
          reason: t("agentsPanel.preview.reason.groupScoped"),
          tierKey: "groupScoped",
          matchedBindingIndex: groupScoped.index,
          matchedBindingSummary: bindingScopeSummary(groupScoped.binding),
          steps,
          ignoresRoles,
        };
      }

      const groupAnyAccount = findBindingPreviewMatch((binding) =>
        normalizedBindingChannel(binding) === channel &&
        normalizedBindingAccount(binding).length === 0 &&
        normalizedBindingPeerKind(binding) === peerKind &&
        normalizedBindingPeerId(binding) === parentPeerId
      );
      steps.push({
        key: "groupAnyAccount",
        matched: Boolean(groupAnyAccount),
        detail: previewStepDetail(groupAnyAccount, t("agentsPanel.preview.stepNoMatch")),
      });
      if (groupAnyAccount) {
        return {
          status: "matched",
          agentId: groupAnyAccount.binding.agent_id.trim() || "main/default",
          reason: t("agentsPanel.preview.reason.groupAnyAccount"),
          tierKey: "groupAnyAccount",
          matchedBindingIndex: groupAnyAccount.index,
          matchedBindingSummary: bindingScopeSummary(groupAnyAccount.binding),
          steps,
          ignoresRoles,
        };
      }
    }

    steps.push({
      key: "defaultFallback",
      matched: true,
      detail: t("agentsPanel.preview.defaultFallbackDetail"),
    });
    return {
      status: "fallback",
      agentId: "main/default",
      reason: t("agentsPanel.preview.reason.defaultFallback"),
      tierKey: "defaultFallback",
      matchedBindingIndex: null,
      matchedBindingSummary: null,
      steps,
      ignoresRoles,
    };
  }

  function buildBindingAdvisories(): BindingAdvisory[][] {
    return bindings.map((binding, index) => {
      const advisories: BindingAdvisory[] = [];
      const channel = normalizedBindingChannel(binding);
      const account = normalizedBindingAccount(binding);
      const peerKind = normalizedBindingPeerKind(binding);
      const peerId = normalizedBindingPeerId(binding);
      const agentId = binding.agent_id.trim().toLowerCase();

      if (agentId === "main" || agentId === "default") {
        advisories.push({
          tone: "info",
          message: translate("agentsPanel.advisory.reservedTarget", {
            target: binding.agent_id.trim() || "main",
          }),
        });
      }

      if (hasExactPeer(binding)) {
        const hasScopedVariant = bindings.some((candidate, candidateIndex) => {
          if (candidateIndex === index) return false;
          return normalizedBindingChannel(candidate) === channel &&
            normalizedBindingPeerKind(candidate) === peerKind &&
            normalizedBindingPeerId(candidate) === peerId &&
            normalizedBindingAccount(candidate).length > 0;
        });
        const hasAnyAccountVariant = bindings.some((candidate, candidateIndex) => {
          if (candidateIndex === index) return false;
          return normalizedBindingChannel(candidate) === channel &&
            normalizedBindingPeerKind(candidate) === peerKind &&
            normalizedBindingPeerId(candidate) === peerId &&
            normalizedBindingAccount(candidate).length === 0;
        });

        if (account && hasAnyAccountVariant) {
          advisories.push({
            tone: "info",
            message: t("agentsPanel.advisory.accountScopedPeerWins"),
          });
        } else if (!account && hasScopedVariant) {
          advisories.push({
            tone: "warn",
            message: t("agentsPanel.advisory.anyAccountPeerFallback"),
          });
        }

        const parentPeerId = threadParentPeerId(peerId);
        if (parentPeerId) {
          const hasGroupFallback = bindings.some((candidate, candidateIndex) => {
            if (candidateIndex === index) return false;
            const candidateAccount = normalizedBindingAccount(candidate);
            return normalizedBindingChannel(candidate) === channel &&
              normalizedBindingPeerKind(candidate) === peerKind &&
              normalizedBindingPeerId(candidate) === parentPeerId &&
              (candidateAccount === account || candidateAccount.length === 0);
          });
          if (hasGroupFallback) {
            advisories.push({
              tone: "info",
              message: t("agentsPanel.advisory.threadOverridesGroup"),
            });
          }
        } else {
          const hasThreadOverrides = bindings.some((candidate, candidateIndex) => {
            if (candidateIndex === index) return false;
            const candidatePeerId = normalizedBindingPeerId(candidate);
            const candidateParentPeerId = threadParentPeerId(candidatePeerId);
            const candidateAccount = normalizedBindingAccount(candidate);
            return normalizedBindingChannel(candidate) === channel &&
              normalizedBindingPeerKind(candidate) === peerKind &&
              candidateParentPeerId === peerId &&
              (candidateAccount === account || candidateAccount.length === 0);
          });
          if (hasThreadOverrides) {
            advisories.push({
              tone: "info",
              message: t("agentsPanel.advisory.groupFallbackUnderSpecificThreads"),
            });
          }
        }
      }

      return advisories;
    });
  }

  function buildUnsavedProfileReferenceIssues() {
    const persisted = new Set(persistedProfileIds);
    const pending: Array<{ index: number; agentId: string }> = [];

    bindings.forEach((binding, index) => {
      const agentId = binding.agent_id.trim();
      if (!agentId || agentId === "main" || agentId === "default") return;
      if (!persisted.has(agentId)) {
        pending.push({ index, agentId });
      }
    });

    return pending;
  }

  function buildBindingsPayload() {
    return {
      bindings: normalizeBindingsForSave(bindings),
    };
  }

  function buildProfilesPayload() {
    return {
      defaults: {
        model_primary: defaultsModelPrimary.trim(),
      },
      profiles: normalizeProfilesForSave(profiles),
    };
  }

  function updateBaselinesFromCurrent() {
    baselineProfilesSignature = serializeProfilesSignature(defaultsModelPrimary, profiles);
    baselineBindingsSignature = serializeBindingsSignature(bindings);
    persistedProfileIds = profiles.map((profile) => profile.id.trim()).filter(Boolean);
  }

  let defaultModelError = $derived(defaultModelIssue(defaultsModelPrimary));
  let profileIssues = $derived(buildProfileIssues());
  let bindingIssues = $derived(buildBindingIssues());
  let bindingAdvisories = $derived(buildBindingAdvisories());
  let unsavedProfileRefIssues = $derived(buildUnsavedProfileReferenceIssues());
  let bindingChannelOptions = $derived(buildBindingChannelOptions());
  let accountOptions = $derived(
    [...new Set(Object.values(channelAccountMap).flat())].sort(),
  );
  let routePreviewResult = $derived(buildRoutePreviewResult());

  let profileIssueRows = $derived(profileIssues.filter((issues) => issues.length > 0).length + (defaultModelError ? 1 : 0));
  let bindingIssueRows = $derived(bindingIssues.filter((issues) => issues.length > 0).length + unsavedProfileRefIssues.length);

  let profilesDirty = $derived(
    loaded && serializeProfilesSignature(defaultsModelPrimary, profiles) !== baselineProfilesSignature,
  );
  let bindingsDirty = $derived(
    loaded && serializeBindingsSignature(bindings) !== baselineBindingsSignature,
  );

  let hasProfileIssues = $derived(Boolean(defaultModelError) || profileIssues.some((issues) => issues.length > 0));
  let hasBindingIssues = $derived(bindingIssues.some((issues) => issues.length > 0));
  let hasBlockingBindingReferences = $derived(unsavedProfileRefIssues.length > 0);

  let busy = $derived(loading || savingProfiles || savingBindings || savingAll);
  let hasAnyDirty = $derived(profilesDirty || bindingsDirty);

  function blankProfile(): AgentProfile {
    return {
      id: "",
      provider: "",
      model: "",
      system_prompt: "",
      temperature: null,
      max_depth: 3,
    };
  }

  function blankBinding(): AgentBinding {
    return {
      agent_id: "",
      match: {
        channel: "",
        account_id: "",
        peer: {
          kind: "direct",
          id: "",
        },
      },
    };
  }

  function addBindingTemplate(template: BindingTemplate) {
    bindings = [...bindings, createBindingTemplate(template)];
    activeTab = "bindings";
  }

  async function load() {
    loading = true;
    error = "";
    saveNotice = null;
    try {
      const [profilesRes, bindingsRes, configRes] = await Promise.all([
        api
          .getAgentProfiles(component, name)
          .catch((): AgentProfilesResponse => ({ defaults: {}, profiles: [] })),
        api
          .getAgentBindings(component, name)
          .catch((): AgentBindingsResponse => ({ bindings: [] })),
        api
          .getConfig(component, name)
          .catch((): AnyRecord => ({})),
      ]);

      const nextDefaultPrimary = profilesRes?.defaults?.model_primary ?? "";
      const nextProfiles = Array.isArray(profilesRes?.profiles)
        ? profilesRes.profiles.map((item) => ({
            id: item?.id ?? "",
            provider: item?.provider ?? "",
            model: item?.model ?? "",
            system_prompt: item?.system_prompt ?? "",
            temperature: typeof item?.temperature === "number" ? item.temperature : null,
            max_depth: typeof item?.max_depth === "number" ? item.max_depth : 3,
          }))
        : [];
      const nextBindings = Array.isArray(bindingsRes?.bindings)
        ? bindingsRes.bindings.map((item) => ({
            agent_id: item?.agent_id ?? "",
            match: {
              channel: item?.match?.channel ?? "",
              account_id: item?.match?.account_id ?? "",
              peer: {
                kind: item?.match?.peer?.kind ?? "direct",
                id: item?.match?.peer?.id ?? "",
              },
            },
          }))
        : [];

      defaultsModelPrimary = nextDefaultPrimary;
      profiles = nextProfiles;
      bindings = nextBindings;
      refreshFormSupport(configRes, nextProfiles, nextBindings, nextDefaultPrimary);
      maybeSeedRoutePreview(nextBindings);

      updateBaselinesFromCurrent();
    } catch (err) {
      error = normalizeError(err);
    } finally {
      loading = false;
      loaded = true;
    }
  }

  async function saveProfiles() {
    if (hasProfileIssues) {
      activeTab = "profiles";
      error = t("agentsPanel.profilesInvalidSave");
      return;
    }

    savingProfiles = true;
    clearFeedback();
    try {
      const response = await api.putAgentProfiles(component, name, buildProfilesPayload());
      await finalizeSave(response, translate("agentsPanel.profilesSaved", { count: profiles.length }));
    } catch (err) {
      error = normalizeError(err);
    } finally {
      savingProfiles = false;
    }
  }

  async function saveBindings() {
    if (hasBindingIssues) {
      activeTab = "bindings";
      error = t("agentsPanel.bindingsInvalidSave");
      return;
    }
    if (hasBlockingBindingReferences) {
      activeTab = "bindings";
      error = t("agentsPanel.bindingsUnsavedProfile");
      return;
    }

    savingBindings = true;
    clearFeedback();
    try {
      const response = await api.putAgentBindings(component, name, buildBindingsPayload());
      await finalizeSave(response, translate("agentsPanel.bindingsSaved", { count: bindings.length }));
    } catch (err) {
      error = normalizeError(err);
    } finally {
      savingBindings = false;
    }
  }

  async function saveAll() {
    if (!hasAnyDirty) {
      saveNotice = {
        tone: "info",
        title: t("agentsPanel.noChangesToSave"),
        detail: t("agentsPanel.feedback.noChangesDetail"),
        meta: translate("agentsPanel.feedback.meta", {
          applyState: "unchanged",
          runtimeEffect: "unchanged",
        }),
        showRefresh: false,
        showRestart: false,
      };
      error = "";
      return;
    }

    if (hasProfileIssues) {
      activeTab = "profiles";
      error = t("agentsPanel.profilesInvalidTab");
      saveNotice = null;
      return;
    }

    if (hasBindingIssues || hasBlockingBindingReferences) {
      activeTab = "bindings";
      error = hasBlockingBindingReferences
        ? t("agentsPanel.bindingsUnsavedProfileAll")
        : t("agentsPanel.bindingsInvalidTab");
      saveNotice = null;
      return;
    }

    savingAll = true;
    clearFeedback();

    let savedProfiles = false;
    let savedBindings = false;
    let lastResponse: AgentMutationResponse = {};

    try {
      if (profilesDirty) {
        lastResponse = await api.putAgentProfiles(component, name, buildProfilesPayload());
        savedProfiles = true;
      }

      if (bindingsDirty) {
        lastResponse = await api.putAgentBindings(component, name, buildBindingsPayload());
        savedBindings = true;
      }

      let title = "";
      if (savedProfiles && savedBindings) {
        title = t("agentsPanel.savedAll");
      } else if (savedProfiles) {
        title = t("agentsPanel.savedProfilesOnly");
      } else if (savedBindings) {
        title = t("agentsPanel.savedBindingsOnly");
      }
      await finalizeSave(lastResponse, title);
    } catch (err) {
      error = normalizeError(err);
      await load();
    } finally {
      savingAll = false;
    }
  }

  function addProfile() {
    profiles = [...profiles, blankProfile()];
    activeTab = "profiles";
  }

  function removeProfile(index: number) {
    profiles = profiles.filter((_, i) => i !== index);
  }

  function addBinding() {
    bindings = [...bindings, blankBinding()];
    activeTab = "bindings";
  }

  function removeBinding(index: number) {
    bindings = bindings.filter((_, i) => i !== index);
  }

  function gotoProfilesTab() {
    activeTab = "profiles";
  }

  async function handleRefreshSummary() {
    if (!onSaved) return;
    await refreshSummaryAfterSave();
    if (saveNotice) {
      saveNotice = {
        ...saveNotice,
        detail: `${saveNotice.detail} ${t("agentsPanel.feedback.summaryRefreshedAgain")}`.trim(),
      };
    }
  }

  function handleRestartRequest() {
    onRequestRestart?.();
  }

  let lastKey = "";
  $effect(() => {
    const currentKey = `${component}/${name}/${active ? "1" : "0"}`;
    if ((!active || currentKey === lastKey) && loaded) return;
    lastKey = currentKey;
    activeTab = "profiles";
    void load();
  });

  onMount(() => {
    if (active) void load();
  });
</script>

<div class="agents-panel">
  <div class="panel-header">
    <div>
      <h3>{t("agentsPanel.title")}</h3>
      <p>{t("agentsPanel.subtitle")}</p>
    </div>
    <div class="row-actions">
      <button class="ghost-btn" onclick={() => load()} disabled={busy}>
        {loading ? t("agentsPanel.refreshing") : t("agentsPanel.refresh")}
      </button>
      <button class="primary-btn" onclick={saveAll} disabled={busy || !hasAnyDirty}>
        {savingAll ? t("agentsPanel.saving") : t("agentsPanel.saveAll")}
      </button>
    </div>
  </div>

  <div class="status-strip">
    <button
      class="tab-chip"
      class:active={activeTab === "profiles"}
      onclick={() => (activeTab = "profiles")}
      type="button"
    >
      {t("agentsPanel.profilesTab")}
      <span>{profiles.length}</span>
      {#if profileIssueRows > 0}
        <em>{translate("agentsPanel.issuesCount", { count: profileIssueRows })}</em>
      {:else if profilesDirty}
        <em>{t("agentsPanel.modified")}</em>
      {/if}
    </button>

    <button
      class="tab-chip"
      class:active={activeTab === "bindings"}
      onclick={() => (activeTab = "bindings")}
      type="button"
    >
      {t("agentsPanel.bindingsTab")}
      <span>{bindings.length}</span>
      {#if bindingIssueRows > 0}
        <em>{translate("agentsPanel.issuesCount", { count: bindingIssueRows })}</em>
      {:else if bindingsDirty}
        <em>{t("agentsPanel.modified")}</em>
      {/if}
    </button>
  </div>

  {#if error}
    <div class="banner error">{error}</div>
  {/if}
  {#if saveNotice}
    <div class={`banner ${saveNotice.tone}`}>
      <div>
        <strong>{saveNotice.title}</strong>
        <p>{saveNotice.detail}</p>
        <div class="banner-meta">{saveNotice.meta}</div>
      </div>
      {#if saveNotice.showRefresh || saveNotice.showRestart}
        <div class="banner-actions">
          {#if saveNotice.showRefresh}
            <button class="ghost-btn" type="button" onclick={handleRefreshSummary} disabled={busy}>
              {t("agentsPanel.feedback.refreshSummary")}
            </button>
          {/if}
          {#if saveNotice.showRestart}
            <button class="primary-btn" type="button" onclick={handleRestartRequest} disabled={busy}>
              {t("agentsPanel.feedback.restartInstance")}
            </button>
          {/if}
        </div>
      {/if}
    </div>
  {/if}

  {#if !loaded || loading}
    <div class="empty">{t("agentsPanel.loading")}</div>
  {:else}
    {#if activeTab === "profiles"}
      <section class="card">
        <div class="card-head">
          <div>
            <h4>{t("agentsPanel.profilesTitle")}</h4>
            <p>{t("agentsPanel.profilesSubtitle")}</p>
          </div>
          <div class="row-actions">
            <button class="ghost-btn" onclick={addProfile} disabled={busy}>{t("agentsPanel.addProfile")}</button>
            <button class="primary-btn" onclick={saveProfiles} disabled={busy || !profilesDirty || hasProfileIssues}>
              {savingProfiles ? t("agentsPanel.saving") : t("agentsPanel.saveProfiles")}
            </button>
          </div>
        </div>

        <label class="field full">
          <span>{t("agentsPanel.defaultPrimaryModel")}</span>
          <input bind:value={defaultsModelPrimary} placeholder="openrouter/openai/gpt-5-mini" />
          {#if defaultModelError}
            <div class="field-error">{defaultModelError}</div>
          {/if}
        </label>

        {#if profiles.length === 0}
          <div class="empty subtle">{t("agentsPanel.emptyProfiles")}</div>
        {/if}

        <div class="stack">
          {#each profiles as profile, index}
            <article class="entry">
              <div class="entry-head">
                <strong>{profile.id || translate("agentsPanel.profileLabel", { count: index + 1 })}</strong>
                <button class="danger-btn" onclick={() => removeProfile(index)} disabled={busy}>{t("agentsPanel.remove")}</button>
              </div>
              {#if profileIssues[index]?.length}
                <ul class="issues">
                  {#each profileIssues[index] as issue}
                    <li>{issue}</li>
                  {/each}
                </ul>
              {/if}
              <div class="grid">
                <label class="field">
                  <span>ID</span>
                  <input bind:value={profile.id} placeholder="coder" />
                </label>
                <label class="field">
                  <span>{t("agentsPanel.provider")}</span>
                  <input bind:value={profile.provider} list="agent-provider-ids" placeholder="openrouter" />
                  <div class="field-hint">{providerHint()}</div>
                </label>
                <label class="field">
                  <span>{t("agentsPanel.model")}</span>
                  <input bind:value={profile.model} list="agent-model-ids" placeholder="gpt-5-mini" />
                  <div class="field-hint">{modelHint(profile)}</div>
                </label>
                <label class="field">
                  <span>{t("agentsPanel.temperature")}</span>
                  <input
                    type="number"
                    step="0.1"
                    bind:value={profile.temperature}
                    placeholder="0.3"
                  />
                </label>
                <label class="field">
                  <span>{t("agentsPanel.maxDepth")}</span>
                  <input type="number" min="1" max="8" bind:value={profile.max_depth} />
                </label>
                <label class="field full">
                  <span>{t("agentsPanel.systemPrompt")}</span>
                  <textarea bind:value={profile.system_prompt} rows="4" placeholder="Focus on implementation and tests."></textarea>
                </label>
              </div>
            </article>
          {/each}
        </div>
      </section>
    {/if}

    {#if activeTab === "bindings"}
      <section class="card">
        <div class="card-head">
          <div>
            <h4>{t("agentsPanel.bindingsTitle")}</h4>
            <p>{t("agentsPanel.bindingsSubtitle")}</p>
          </div>
          <div class="row-actions">
            <button class="ghost-btn" onclick={addBinding} disabled={busy}>{t("agentsPanel.addBinding")}</button>
            <button
              class="primary-btn"
              onclick={saveBindings}
              disabled={busy || !bindingsDirty || hasBindingIssues || hasBlockingBindingReferences}
            >
              {savingBindings ? t("agentsPanel.saving") : t("agentsPanel.saveBindings")}
            </button>
          </div>
        </div>

        {#if hasBlockingBindingReferences}
          <div class="banner warn">
            <div>
              <strong>{translate("agentsPanel.unsavedBindingsTitle", { count: unsavedProfileRefIssues.length })}</strong>
              <p>{t("agentsPanel.unsavedBindingsDesc")}</p>
            </div>
            <button class="ghost-btn" type="button" onclick={gotoProfilesTab}>{t("agentsPanel.gotoProfiles")}</button>
          </div>
        {/if}

        <div class="routing-guide">
          <article class="guide-card">
            <strong>{t("agentsPanel.routingGuideTitle")}</strong>
            <p>{t("agentsPanel.routingGuideDesc")}</p>
            <ul class="guide-list">
              <li>{t("agentsPanel.routingGuideSingleWinner")}</li>
              <li>{t("agentsPanel.routingGuideCurrentScope")}</li>
              <li>{t("agentsPanel.routingGuidePeerPriority")}</li>
              <li>{t("agentsPanel.routingGuideThreadFallback")}</li>
              <li>{t("agentsPanel.routingGuideReservedTargets")}</li>
            </ul>
            <div class="template-strip">
              <span class="template-label">{t("agentsPanel.templatesLabel")}</span>
              <button class="ghost-btn" type="button" onclick={() => addBindingTemplate("groupFallback")} disabled={busy}>
                {t("agentsPanel.templates.groupFallback")}
              </button>
              <button class="ghost-btn" type="button" onclick={() => addBindingTemplate("topicExact")} disabled={busy}>
                {t("agentsPanel.templates.topicExact")}
              </button>
              <button class="ghost-btn" type="button" onclick={() => addBindingTemplate("dmDirect")} disabled={busy}>
                {t("agentsPanel.templates.dmDirect")}
              </button>
            </div>
          </article>
        </div>

        <div class="routing-guide">
          <article class="guide-card preview-card">
            <div class="preview-head">
              <div>
                <strong>{t("agentsPanel.preview.title")}</strong>
                <p>{t("agentsPanel.preview.subtitle")}</p>
              </div>
              <span class={`route-chip ${routePreviewResult.status === "matched" ? "priority" : routePreviewResult.status === "fallback" ? "dim" : ""}`}>
                {routePreviewResult.status === "matched"
                  ? t("agentsPanel.preview.statusMatched")
                  : routePreviewResult.status === "fallback"
                    ? t("agentsPanel.preview.statusFallback")
                    : t("agentsPanel.preview.statusIncomplete")}
              </span>
            </div>

            <div class="grid preview-grid">
              <label class="field">
                <span>{t("agentsPanel.preview.channelLabel")}</span>
                <select bind:value={routePreview.channel}>
                  <option value="">{t("agentsPanel.selectChannel")}</option>
                  {#each bindingChannelOptions as channelType}
                    <option value={channelType}>{channelDisplayName(channelType)}</option>
                  {/each}
                </select>
                <div class="field-hint">{routePreviewChannelHint()}</div>
              </label>
              <label class="field">
                <span>{t("agentsPanel.preview.accountLabel")}</span>
                <input bind:value={routePreview.account_id} list="agent-account-ids" placeholder="main" />
                <div class="field-hint">{routePreviewAccountHint()}</div>
              </label>
              <label class="field">
                <span>{t("agentsPanel.preview.peerKindLabel")}</span>
                <select bind:value={routePreview.peer_kind}>
                  {#each peerKindOptions as kind}
                    <option value={kind}>{kind}</option>
                  {/each}
                </select>
              </label>
              <label class="field full">
                <span>{t("agentsPanel.preview.peerIdLabel")}</span>
                <input bind:value={routePreview.peer_id} placeholder={peerExample(routePreview.channel, routePreview.peer_kind)} />
                <div class="field-hint">{routePreviewPeerHint()}</div>
              </label>
              <label class="field full">
                <span>{t("agentsPanel.preview.rolesLabel")}</span>
                <input bind:value={routePreview.roles} placeholder="@ops, @reviewer" />
                <div class="field-hint">{t("agentsPanel.preview.rolesHint")}</div>
              </label>
            </div>

            <div class="preview-result">
              <div class="preview-result-main">
                <span class="label">{t("agentsPanel.preview.resultLabel")}</span>
                <strong>{routePreviewResult.agentId || t("agentsPanel.preview.pendingTarget")}</strong>
                <p>{routePreviewResult.reason}</p>
                {#if routePreviewResult.matchedBindingIndex !== null && routePreviewResult.matchedBindingSummary}
                  <div class="banner-meta">
                    {translate("agentsPanel.preview.bindingRef", { index: routePreviewResult.matchedBindingIndex + 1 })} · {routePreviewResult.matchedBindingSummary}
                  </div>
                {:else if routePreviewResult.status === "fallback"}
                  <div class="banner-meta">{t("agentsPanel.preview.defaultFallbackDetail")}</div>
                {/if}
                {#if routePreviewResult.ignoresRoles}
                  <div class="field-hint">{t("agentsPanel.preview.rolesIgnored")}</div>
                {/if}
              </div>
              <div class="preview-trace">
                <span class="label">{t("agentsPanel.preview.traceTitle")}</span>
                <ul class="preview-trace-list">
                  {#if routePreviewResult.steps.length === 0}
                    <li class="trace-row">
                      <span class="route-chip dim">{t("agentsPanel.preview.statusIncomplete")}</span>
                      <span>{t("agentsPanel.preview.tracePending")}</span>
                    </li>
                  {:else}
                    {#each routePreviewResult.steps as step}
                      <li class="trace-row">
                        <span class={`route-chip ${step.matched ? "priority" : "dim"}`}>{t(`agentsPanel.preview.tiers.${step.key}`)}</span>
                        <span>{step.detail}</span>
                      </li>
                    {/each}
                  {/if}
                </ul>
              </div>
            </div>
          </article>
        </div>

        {#if bindings.length === 0}
          <div class="empty subtle">{t("agentsPanel.emptyBindings")}</div>
        {/if}

        <div class="stack">
          {#each bindings as binding, index}
            <article class="entry">
              <div class="entry-head">
                <strong>{binding.agent_id || translate("agentsPanel.bindingLabel", { count: index + 1 })}</strong>
                <button class="danger-btn" onclick={() => removeBinding(index)} disabled={busy}>{t("agentsPanel.remove")}</button>
              </div>
              {#if bindingIssues[index]?.length}
                <ul class="issues">
                  {#each bindingIssues[index] as issue}
                    <li>{issue}</li>
                  {/each}
                </ul>
              {/if}
              <div class="binding-summary">
                <div class="binding-badges">
                  <span class="route-chip priority">{bindingPriorityLabel(binding)}</span>
                  <span class="route-chip">{binding.match.channel.trim() || t("agentsPanel.pendingChannel")}</span>
                  <span class="route-chip dim">{accountBadgeLabel(binding)}</span>
                  <span class="route-chip dim">{peerBadgeLabel(binding)}</span>
                </div>
                <p>{bindingScopeSummary(binding)}</p>
              </div>
              {#if bindingAdvisories[index]?.length}
                <ul class="binding-advisories">
                  {#each bindingAdvisories[index] as advisory}
                    <li class:warn={advisory.tone === "warn"} class:info={advisory.tone === "info"}>
                      {advisory.message}
                    </li>
                  {/each}
                </ul>
              {/if}
              <div class="grid">
                <label class="field">
                  <span>{t("agentsPanel.agentId")}</span>
                  <input bind:value={binding.agent_id} list="agent-profile-ids" placeholder="coder" />
                </label>
                <label class="field">
                  <span>{t("agentsPanel.channelLabel")}</span>
                  <select bind:value={binding.match.channel}>
                    <option value="">{t("agentsPanel.selectChannel")}</option>
                    {#if binding.match.channel && !bindingChannelOptions.includes(binding.match.channel)}
                      <option value={binding.match.channel}>{translate("agentsPanel.customChannelOption", { channel: binding.match.channel })}</option>
                    {/if}
                    {#each bindingChannelOptions as channelType}
                      <option value={channelType}>{channelDisplayName(channelType)}</option>
                    {/each}
                  </select>
                  <div class="field-hint">
                    {#if configuredChannelOptions.length > 0}
                      {translate("agentsPanel.channelHintAvailable", { channels: configuredChannelOptions.join(", ") })}
                    {:else}
                      {t("agentsPanel.channelHintMissing")}
                    {/if}
                  </div>
                </label>
                <label class="field">
                  <span>{t("agentsPanel.accountId")}</span>
                  <input bind:value={binding.match.account_id} list="agent-account-ids" placeholder="main" />
                  <div class="field-hint">{accountHint(binding)}</div>
                </label>
                <label class="field">
                  <span>{t("agentsPanel.peerKind")}</span>
                  <select bind:value={binding.match.peer.kind}>
                    {#each peerKindOptions as kind}
                      <option value={kind}>{kind}</option>
                    {/each}
                  </select>
                </label>
                <label class="field full">
                  <span>{t("agentsPanel.peerId")}</span>
                  <input bind:value={binding.match.peer.id} placeholder={bindingPeerPlaceholder(binding)} />
                  <div class="field-hint">{bindingPeerHint(binding)}</div>
                </label>
              </div>
            </article>
          {/each}
        </div>

        <datalist id="agent-profile-ids">
          {#each profiles as profile}
            {#if profile.id}
              <option value={profile.id}></option>
            {/if}
          {/each}
          <option value="main"></option>
          <option value="default"></option>
        </datalist>
        <datalist id="agent-provider-ids">
          {#each providerOptions as providerName}
            <option value={providerName}></option>
          {/each}
        </datalist>
        <datalist id="agent-model-ids">
          {#each modelOptions as modelName}
            <option value={modelName}></option>
          {/each}
        </datalist>
        <datalist id="agent-account-ids">
          {#each accountOptions as accountId}
            <option value={accountId}></option>
          {/each}
        </datalist>
      </section>
    {/if}
  {/if}
</div>

<style>
  .agents-panel {
    display: grid;
    gap: var(--spacing-lg);
  }

  .panel-header,
  .card-head,
  .entry-head {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
    gap: 1rem;
  }

  .panel-header h3,
  .card-head h4 {
    margin: 0;
    color: var(--shell-text);
  }

  .panel-header p,
  .card-head p {
    margin: 0.35rem 0 0;
    color: var(--shell-text-dim);
  }

  .status-strip {
    display: flex;
    gap: 0.6rem;
    flex-wrap: wrap;
  }

  .tab-chip {
    border: 1px solid rgba(116, 136, 173, 0.22);
    background: rgba(255, 255, 255, 0.06);
    color: var(--shell-text-dim);
    border-radius: 999px;
    padding: 0.5rem 0.9rem;
    cursor: pointer;
    display: inline-flex;
    align-items: center;
    gap: 0.45rem;
    font-weight: 600;
  }

  .tab-chip span {
    font-family: var(--font-mono);
    color: var(--shell-text-dim);
    font-size: 0.8rem;
  }

  .tab-chip em {
    color: #ffd089;
    font-style: normal;
    font-size: 0.76rem;
  }

  .tab-chip.active {
    border-color: rgba(34, 211, 238, 0.22);
    background: linear-gradient(135deg, rgba(15, 23, 42, 0.96), rgba(24, 34, 56, 0.94));
    color: var(--shell-text);
    box-shadow: var(--glow-cyan);
  }

  .card {
    border: 1px solid rgba(116, 136, 173, 0.22);
    border-radius: var(--radius-lg);
    padding: var(--spacing-lg);
    background:
      linear-gradient(180deg, rgba(9, 15, 27, 0.98), rgba(15, 24, 40, 0.96)),
      radial-gradient(circle at top right, rgba(34, 211, 238, 0.1), transparent 30%);
    box-shadow: var(--glow-cyan);
  }

  .routing-guide {
    margin-bottom: 0.95rem;
  }

  .guide-card {
    border: 1px solid rgba(34, 211, 238, 0.18);
    border-radius: var(--radius-lg);
    padding: 0.95rem 1rem;
    background: linear-gradient(180deg, rgba(9, 15, 27, 0.88), rgba(15, 24, 40, 0.84));
  }

  .guide-card strong {
    display: block;
    margin-bottom: 0.3rem;
    color: var(--shell-text);
  }

  .guide-card p {
    margin: 0;
    color: var(--shell-text-dim);
  }

  .guide-list {
    margin: 0.8rem 0 0;
    padding-left: 1.1rem;
    color: var(--shell-text-dim);
    display: grid;
    gap: 0.45rem;
    font-size: 0.84rem;
  }

  .template-strip {
    display: flex;
    flex-wrap: wrap;
    gap: 0.55rem;
    align-items: center;
    margin-top: 0.95rem;
  }

  .preview-card {
    display: grid;
    gap: var(--spacing-md);
  }

  .preview-head {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
    gap: var(--spacing-md);
  }

  .preview-grid {
    margin-top: 0.15rem;
  }

  .preview-result {
    display: grid;
    grid-template-columns: minmax(0, 1.1fr) minmax(0, 1fr);
    gap: var(--spacing-md);
  }

  .preview-result-main,
  .preview-trace {
    border: 1px solid rgba(116, 136, 173, 0.16);
    border-radius: var(--radius-md);
    background: rgba(255, 255, 255, 0.05);
    padding: 0.85rem 0.95rem;
    display: grid;
    gap: 0.45rem;
  }

  .preview-result-main .label,
  .preview-trace .label {
    font-size: 0.76rem;
    letter-spacing: 0.08em;
    text-transform: uppercase;
    color: var(--shell-text-dim);
    font-weight: 600;
  }

  .preview-result-main strong {
    color: var(--shell-text);
    font-size: 1rem;
  }

  .preview-result-main p {
    margin: 0;
    color: var(--shell-text-dim);
    font-size: 0.84rem;
    line-height: 1.5;
  }

  .preview-trace-list {
    margin: 0;
    padding: 0;
    list-style: none;
    display: grid;
    gap: 0.55rem;
  }

  .trace-row {
    display: grid;
    gap: 0.4rem;
  }

  .trace-row span:last-child {
    color: var(--shell-text-dim);
    font-size: 0.8rem;
    line-height: 1.45;
  }

  .template-label {
    color: var(--shell-text-dim);
    font-size: 0.78rem;
    font-weight: 600;
  }

  .stack {
    display: grid;
    gap: var(--spacing-md);
  }

  .entry {
    border: 1px solid rgba(116, 136, 173, 0.18);
    border-radius: var(--radius-lg);
    background: rgba(255, 255, 255, 0.06);
    padding: var(--spacing-lg);
    display: grid;
    gap: var(--spacing-md);
  }

  .grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
    gap: var(--spacing-md);
  }

  .binding-summary {
    display: grid;
    gap: 0.55rem;
  }

  .binding-summary p {
    margin: 0;
    color: var(--shell-text-dim);
    font-size: 0.84rem;
  }

  .binding-badges {
    display: flex;
    gap: 0.45rem;
    flex-wrap: wrap;
  }

  .route-chip {
    display: inline-flex;
    align-items: center;
    gap: 0.35rem;
    border-radius: 999px;
    padding: 0.32rem 0.7rem;
    border: 1px solid rgba(116, 136, 173, 0.2);
    background: rgba(255, 255, 255, 0.06);
    color: var(--shell-text);
    font-size: 0.77rem;
    line-height: 1.25;
  }

  .route-chip.priority {
    border-color: rgba(34, 211, 238, 0.24);
    background: rgba(34, 211, 238, 0.12);
    color: #a5f3fc;
  }

  .route-chip.dim {
    color: var(--shell-text-dim);
  }

  .binding-advisories {
    margin: 0;
    padding: 0;
    list-style: none;
    display: grid;
    gap: 0.4rem;
  }

  .binding-advisories li {
    border-radius: var(--radius-md);
    padding: 0.55rem 0.75rem;
    font-size: 0.8rem;
  }

  .binding-advisories li.info {
    border: 1px solid rgba(34, 211, 238, 0.16);
    background: rgba(34, 211, 238, 0.08);
    color: #b7f6ff;
  }

  .binding-advisories li.warn {
    border: 1px solid rgba(245, 158, 11, 0.22);
    background: rgba(245, 158, 11, 0.08);
    color: #ffd89f;
  }

  .field {
    display: grid;
    gap: 0.35rem;
  }

  .field.full {
    grid-column: 1 / -1;
  }

  .field span {
    font-size: 0.8rem;
    font-weight: 600;
    color: var(--shell-text-dim);
  }

  .field-hint {
    color: rgba(181, 199, 230, 0.72);
    font-size: 0.76rem;
    line-height: 1.45;
  }

  .field-error {
    color: #ff98ad;
    font-size: 0.78rem;
  }

  input,
  textarea,
  select {
    width: 100%;
    border: 1px solid rgba(116, 136, 173, 0.22);
    border-radius: var(--radius-md);
    padding: 0.75rem 0.85rem;
    background: rgba(255, 255, 255, 0.08);
    color: var(--shell-text);
    box-shadow: inset 0 1px 2px rgba(4, 9, 18, 0.22);
  }

  textarea {
    resize: vertical;
    font: inherit;
  }

  input::placeholder,
  textarea::placeholder {
    color: rgba(181, 199, 230, 0.52);
  }

  .row-actions {
    display: flex;
    gap: 0.6rem;
    flex-wrap: wrap;
  }

  .primary-btn,
  .ghost-btn,
  .danger-btn {
    border-radius: 999px;
    padding: 0.55rem 0.95rem;
    cursor: pointer;
    border: 1px solid rgba(116, 136, 173, 0.2);
    background: rgba(255, 255, 255, 0.06);
    color: var(--shell-text);
  }

  .primary-btn {
    border-color: rgba(34, 211, 238, 0.22);
    background: linear-gradient(135deg, rgba(34, 211, 238, 0.18), rgba(139, 92, 246, 0.14));
    box-shadow: inset 0 0 14px rgba(34, 211, 238, 0.12);
  }

  .danger-btn {
    border-color: rgba(244, 63, 94, 0.22);
    color: #ffb0c0;
  }

  .primary-btn:disabled,
  .ghost-btn:disabled,
  .danger-btn:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }

  .banner {
    border-radius: var(--radius-lg);
    padding: 0.9rem 1rem;
  }

  .banner.error {
    border: 1px solid rgba(244, 63, 94, 0.22);
    background: rgba(244, 63, 94, 0.08);
    color: #ffc0cc;
  }

  .banner.success {
    border: 1px solid rgba(16, 185, 129, 0.22);
    background: rgba(16, 185, 129, 0.08);
    color: #b8f8d7;
  }

  .banner.info {
    border: 1px solid rgba(34, 211, 238, 0.18);
    background: rgba(34, 211, 238, 0.08);
    color: #b7f6ff;
  }

  .banner.warn {
    border: 1px solid rgba(245, 158, 11, 0.22);
    background: rgba(245, 158, 11, 0.08);
    color: #ffd89f;
    display: flex;
    gap: 0.8rem;
    justify-content: space-between;
    align-items: flex-start;
    margin-bottom: 0.85rem;
  }

  .banner.warn p {
    margin: 0.3rem 0 0;
    color: #ffd9a5;
    font-size: 0.86rem;
  }

  .banner.success p,
  .banner.info p {
    margin: 0.3rem 0 0;
    font-size: 0.86rem;
  }

  .banner.success p {
    color: #cffde6;
  }

  .banner.info p {
    color: #d1faff;
  }

  .banner-meta {
    margin-top: 0.5rem;
    font-family: var(--font-mono);
    font-size: 0.76rem;
    opacity: 0.84;
  }

  .banner-actions {
    display: flex;
    flex-wrap: wrap;
    gap: 0.55rem;
  }

  .empty {
    border: 1px dashed rgba(116, 136, 173, 0.28);
    border-radius: var(--radius-lg);
    padding: 1rem;
    color: var(--shell-text-dim);
    background: rgba(255, 255, 255, 0.04);
  }

  .empty.subtle {
    margin-top: 0.85rem;
  }

  .issues {
    margin: 0;
    padding: 0.5rem 0.85rem;
    border-radius: var(--radius-md);
    border: 1px solid rgba(244, 63, 94, 0.18);
    background: rgba(244, 63, 94, 0.08);
    color: #ffc0cc;
    font-size: 0.82rem;
  }

  .issues li + li {
    margin-top: 0.35rem;
  }

  @media (max-width: 900px) {
    .panel-header,
    .card-head,
    .entry-head,
    .banner.warn {
      flex-direction: column;
    }

    .preview-head {
      flex-direction: column;
    }

    .preview-result {
      grid-template-columns: 1fr;
    }
  }
</style>
