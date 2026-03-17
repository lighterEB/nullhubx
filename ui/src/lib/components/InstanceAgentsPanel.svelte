<script lang="ts">
  import { onMount } from "svelte";
  import { api } from "$lib/api/client";
  import { channelSchemas } from "$lib/components/configSchemas";

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

  let {
    component = "",
    name = "",
    active = false,
  }: {
    component?: string;
    name?: string;
    active?: boolean;
  } = $props();

  let loaded = $state(false);
  let loading = $state(false);
  let savingProfiles = $state(false);
  let savingBindings = $state(false);
  let error = $state("");
  let message = $state("");

  let defaultsModelPrimary = $state("");
  let profiles = $state<AgentProfile[]>([]);
  let bindings = $state<AgentBinding[]>([]);
  const channelOptions = Object.keys(channelSchemas).sort();
  const peerKindOptions = ["direct", "group", "channel"];

  function defaultModelIssue(value: string): string | null {
    const trimmed = value.trim();
    if (!trimmed) return null;
    if (trimmed.startsWith("custom:")) return null;
    if (!trimmed.includes("/")) return "默认主模型格式应为 provider/model。";
    if (trimmed.startsWith("/") || trimmed.endsWith("/")) return "默认主模型格式应为 provider/model。";
    return null;
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

      if (!id) issues.push("ID 为必填项。");
      if (id && (counts.get(id) ?? 0) > 1) issues.push("ID 不能重复。");
      if (!provider) issues.push("Provider 为必填项。");
      if (!model) issues.push("Model 为必填项。");
      if (maxDepth < 1 || maxDepth > 8) issues.push("Max depth 必须在 1 到 8 之间。");

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

    return bindings.map((binding) => {
      const issues: string[] = [];
      const agentId = binding.agent_id.trim();
      const channel = binding.match.channel.trim();
      const peerKind = binding.match.peer.kind.trim();
      const peerId = binding.match.peer.id.trim();

      if (!agentId) issues.push("Agent ID 为必填项。");
      if (agentId && !validAgentIds.has(agentId)) issues.push("Agent ID 必须匹配已存在的 Profile。");
      if (!channel) issues.push("渠道为必填项。");
      if (!peerKind) issues.push("Peer 类型为必填项。");
      if (!peerId) issues.push("Peer ID 为必填项。");

      return issues;
    });
  }

  let defaultModelError = $derived(defaultModelIssue(defaultsModelPrimary));
  let profileIssues = $derived(buildProfileIssues());
  let bindingIssues = $derived(buildBindingIssues());
  let hasProfileIssues = $derived(
    Boolean(defaultModelError) || profileIssues.some((issues) => issues.length > 0),
  );
  let hasBindingIssues = $derived(
    bindingIssues.some((issues) => issues.length > 0),
  );

  function normalizeError(err: unknown): string {
    return err instanceof Error ? err.message : "请求失败";
  }

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

  async function load() {
    loading = true;
    error = "";
    message = "";
    try {
      const [profilesRes, bindingsRes] = await Promise.all([
        api.getAgentProfiles(component, name).catch(() => ({ defaults: {}, profiles: [] })),
        api.getAgentBindings(component, name).catch(() => ({ bindings: [] })),
      ]);

      defaultsModelPrimary = profilesRes?.defaults?.model_primary ?? "";
      profiles = Array.isArray(profilesRes?.profiles)
        ? profilesRes.profiles.map((item: any) => ({
            id: item?.id ?? "",
            provider: item?.provider ?? "",
            model: item?.model ?? "",
            system_prompt: item?.system_prompt ?? "",
            temperature: typeof item?.temperature === "number" ? item.temperature : null,
            max_depth: typeof item?.max_depth === "number" ? item.max_depth : 3,
          }))
        : [];
      bindings = Array.isArray(bindingsRes?.bindings)
        ? bindingsRes.bindings.map((item: any) => ({
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
    } catch (err) {
      error = normalizeError(err);
    } finally {
      loading = false;
      loaded = true;
    }
  }

  async function saveProfiles() {
    savingProfiles = true;
    error = "";
    message = "";
    try {
      const payload = {
        defaults: {
          model_primary: defaultsModelPrimary.trim(),
        },
        profiles: profiles.map((profile) => ({
          id: profile.id.trim(),
          provider: profile.provider.trim(),
          model: profile.model.trim(),
          system_prompt: profile.system_prompt?.trim() || undefined,
          temperature:
            profile.temperature === null || profile.temperature === undefined || Number.isNaN(profile.temperature)
              ? undefined
              : profile.temperature,
          max_depth: profile.max_depth || 3,
        })),
      };
      await api.putAgentProfiles(component, name, payload);
      message = "Profiles 已保存";
      await load();
    } catch (err) {
      error = normalizeError(err);
    } finally {
      savingProfiles = false;
    }
  }

  async function saveBindings() {
    savingBindings = true;
    error = "";
    message = "";
    try {
      const payload = {
        bindings: bindings.map((binding) => ({
          agent_id: binding.agent_id.trim(),
          match: {
            channel: binding.match.channel.trim(),
            account_id: binding.match.account_id?.trim() || undefined,
            peer: {
              kind: binding.match.peer.kind.trim(),
              id: binding.match.peer.id.trim(),
            },
          },
        })),
      };
      await api.putAgentBindings(component, name, payload);
      message = "Bindings 已保存";
      await load();
    } catch (err) {
      error = normalizeError(err);
    } finally {
      savingBindings = false;
    }
  }

  function addProfile() {
    profiles = [...profiles, blankProfile()];
  }

  function removeProfile(index: number) {
    profiles = profiles.filter((_, i) => i !== index);
  }

  function addBinding() {
    bindings = [...bindings, blankBinding()];
  }

  function removeBinding(index: number) {
    bindings = bindings.filter((_, i) => i !== index);
  }

  let lastKey = "";
  $effect(() => {
    const currentKey = `${component}/${name}/${active ? "1" : "0"}`;
    if (!active || currentKey === lastKey && loaded) return;
    lastKey = currentKey;
    void load();
  });

  onMount(() => {
    if (active) void load();
  });
</script>

<div class="agents-panel">
  <div class="panel-header">
    <div>
      <h3>代理</h3>
      <p>管理实例内的 Profiles 与 Bindings 路由规则。</p>
    </div>
    <button class="ghost-btn" onclick={() => load()} disabled={loading || savingProfiles || savingBindings}>
      {loading ? "刷新中..." : "刷新"}
    </button>
  </div>

  {#if error}
    <div class="banner error">{error}</div>
  {/if}
  {#if message}
    <div class="banner success">{message}</div>
  {/if}

  {#if !loaded || loading}
    <div class="empty">正在加载代理配置...</div>
  {:else}
    <section class="card">
      <div class="card-head">
        <div>
          <h4>Profiles</h4>
          <p>Profiles 对应 `agents.list[]`，默认主模型位于 `agents.defaults.model.primary`。</p>
        </div>
        <div class="row-actions">
          <button class="ghost-btn" onclick={addProfile}>添加 Profile</button>
          <button
            class="primary-btn"
            onclick={saveProfiles}
            disabled={savingProfiles || savingBindings || hasProfileIssues}
          >
            {savingProfiles ? "保存中..." : "保存 Profiles"}
          </button>
        </div>
      </div>

      <label class="field full">
        <span>默认主模型</span>
        <input bind:value={defaultsModelPrimary} placeholder="openrouter/openai/gpt-5-mini" />
        {#if defaultModelError}
          <div class="field-error">{defaultModelError}</div>
        {/if}
      </label>

      {#if profiles.length === 0}
        <div class="empty subtle">暂无 Profiles，可先添加一个用于路由绑定。</div>
      {/if}

      <div class="stack">
        {#each profiles as profile, index}
          <article class="entry">
            <div class="entry-head">
              <strong>{profile.id || `Profile ${index + 1}`}</strong>
              <button class="danger-btn" onclick={() => removeProfile(index)}>Remove</button>
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
                <span>Provider</span>
                <input bind:value={profile.provider} placeholder="openrouter" />
              </label>
              <label class="field">
                <span>Model</span>
                <input bind:value={profile.model} placeholder="openai/gpt-5-mini" />
              </label>
              <label class="field">
                <span>Temperature</span>
                <input
                  type="number"
                  step="0.1"
                  bind:value={profile.temperature}
                  placeholder="0.3"
                />
              </label>
              <label class="field">
                <span>Max Depth</span>
                <input type="number" min="1" max="8" bind:value={profile.max_depth} />
              </label>
              <label class="field full">
                <span>System Prompt</span>
                <textarea bind:value={profile.system_prompt} rows="4" placeholder="Focus on implementation and tests."></textarea>
              </label>
            </div>
          </article>
        {/each}
      </div>
    </section>

    <section class="card">
      <div class="card-head">
        <div>
          <h4>Bindings</h4>
          <p>Bindings 用于将渠道与 peer 路由到指定 Profile。支持 legacy `#topic:`，保存时会转换为 `:thread:`。</p>
        </div>
        <div class="row-actions">
          <button class="ghost-btn" onclick={addBinding}>添加 Binding</button>
          <button
            class="primary-btn"
            onclick={saveBindings}
            disabled={savingProfiles || savingBindings || hasBindingIssues}
          >
            {savingBindings ? "保存中..." : "保存 Bindings"}
          </button>
        </div>
      </div>

      {#if bindings.length === 0}
        <div class="empty subtle">暂无 Bindings，流量将继续使用默认路径。</div>
      {/if}

      <div class="stack">
        {#each bindings as binding, index}
          <article class="entry">
            <div class="entry-head">
              <strong>{binding.agent_id || `Binding ${index + 1}`}</strong>
              <button class="danger-btn" onclick={() => removeBinding(index)}>Remove</button>
            </div>
            {#if bindingIssues[index]?.length}
              <ul class="issues">
                {#each bindingIssues[index] as issue}
                  <li>{issue}</li>
                {/each}
              </ul>
            {/if}
            <div class="grid">
              <label class="field">
                <span>Agent ID</span>
                <input bind:value={binding.agent_id} list="agent-profile-ids" placeholder="coder" />
              </label>
              <label class="field">
                <span>渠道</span>
                <input bind:value={binding.match.channel} list="agent-channel-types" placeholder="telegram" />
              </label>
              <label class="field">
                <span>账户 ID</span>
                <input bind:value={binding.match.account_id} placeholder="main" />
              </label>
              <label class="field">
                <span>Peer 类型</span>
                <select bind:value={binding.match.peer.kind}>
                  {#each peerKindOptions as kind}
                    <option value={kind}>{kind}</option>
                  {/each}
                </select>
              </label>
              <label class="field full">
                <span>Peer ID</span>
                <input bind:value={binding.match.peer.id} placeholder="-1001234567890:thread:42" />
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
      <datalist id="agent-channel-types">
        {#each channelOptions as channelType}
          <option value={channelType}></option>
        {/each}
      </datalist>
    </section>
  {/if}
</div>

<style>
  .agents-panel {
    display: grid;
    gap: 1rem;
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
  }
  .panel-header p,
  .card-head p {
    margin: 0.35rem 0 0;
    color: var(--slate-500);
  }
  .card {
    border: 1px solid var(--slate-200);
    border-radius: 14px;
    padding: 1rem;
    background:
      linear-gradient(180deg, color-mix(in srgb, var(--indigo-50) 35%, white) 0%, white 46%),
      white;
  }
  .stack {
    display: grid;
    gap: 0.85rem;
  }
  .entry {
    border: 1px solid var(--slate-200);
    border-radius: 12px;
    background: rgba(255, 255, 255, 0.9);
    padding: 0.9rem;
    display: grid;
    gap: 0.85rem;
  }
  .grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
    gap: 0.8rem;
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
    color: var(--slate-600);
  }
  .field-error {
    color: var(--red-600);
    font-size: 0.78rem;
  }
  input,
  textarea,
  select {
    width: 100%;
    border: 1px solid var(--slate-300);
    border-radius: 10px;
    padding: 0.7rem 0.8rem;
    background: white;
    color: var(--slate-800);
  }
  textarea {
    resize: vertical;
    font: inherit;
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
    border: 1px solid var(--slate-300);
    background: white;
  }
  .primary-btn {
    border-color: var(--indigo-600);
    background: var(--indigo-600);
    color: white;
  }
  .danger-btn {
    border-color: var(--red-300);
    color: var(--red-600);
  }
  .primary-btn:disabled,
  .ghost-btn:disabled,
  .danger-btn:disabled {
    opacity: 0.6;
    cursor: not-allowed;
  }
  .banner {
    border-radius: 10px;
    padding: 0.8rem 0.95rem;
  }
  .banner.error {
    border: 1px solid var(--red-200);
    background: var(--red-50);
    color: var(--red-700);
  }
  .banner.success {
    border: 1px solid var(--emerald-200);
    background: var(--emerald-50);
    color: var(--emerald-700);
  }
  .empty {
    border: 1px dashed var(--slate-300);
    border-radius: 12px;
    padding: 1rem;
    color: var(--slate-500);
    background: var(--slate-50);
  }
  .empty.subtle {
    margin-top: 0.85rem;
  }
  .issues {
    margin: 0;
    padding: 0.5rem 0.85rem;
    border-radius: 10px;
    border: 1px solid var(--red-100);
    background: var(--red-50);
    color: var(--red-700);
    font-size: 0.82rem;
  }
  .issues li + li {
    margin-top: 0.35rem;
  }
  @media (max-width: 900px) {
    .panel-header,
    .card-head,
    .entry-head {
      flex-direction: column;
    }
  }
</style>
