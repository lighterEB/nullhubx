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

  type AgentTab = "profiles" | "bindings";

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
  let savingAll = $state(false);
  let error = $state("");
  let notice = $state("");

  let activeTab = $state<AgentTab>("profiles");

  let defaultsModelPrimary = $state("");
  let profiles = $state<AgentProfile[]>([]);
  let bindings = $state<AgentBinding[]>([]);
  let persistedProfileIds = $state<string[]>([]);

  let baselineProfilesSignature = $state("");
  let baselineBindingsSignature = $state("");

  const channelOptions = Object.keys(channelSchemas).sort();
  const peerKindOptions = ["direct", "group", "channel"];

  function normalizeError(err: unknown): string {
    return err instanceof Error ? err.message : "请求失败";
  }

  function defaultModelIssue(value: string): string | null {
    const trimmed = value.trim();
    if (!trimmed) return null;
    if (trimmed.startsWith("custom:")) return null;
    if (!trimmed.includes("/")) return "默认主模型格式应为 provider/model。";
    if (trimmed.startsWith("/") || trimmed.endsWith("/")) return "默认主模型格式应为 provider/model。";
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

    const duplicateKeyCount = new Map<string, number>();
    for (const binding of bindings) {
      const key = [
        binding.agent_id.trim(),
        binding.match.channel.trim().toLowerCase(),
        (binding.match.account_id || "").trim().toLowerCase(),
        binding.match.peer.kind.trim().toLowerCase(),
        binding.match.peer.id.trim(),
      ].join("|");
      duplicateKeyCount.set(key, (duplicateKeyCount.get(key) ?? 0) + 1);
    }

    return bindings.map((binding) => {
      const issues: string[] = [];
      const agentId = binding.agent_id.trim();
      const channel = binding.match.channel.trim();
      const peerKind = binding.match.peer.kind.trim();
      const peerId = binding.match.peer.id.trim();
      const duplicateKey = [
        agentId,
        channel.toLowerCase(),
        (binding.match.account_id || "").trim().toLowerCase(),
        peerKind.toLowerCase(),
        peerId,
      ].join("|");

      if (!agentId) issues.push("Agent ID 为必填项。");
      if (agentId && !validAgentIds.has(agentId)) issues.push("Agent ID 必须匹配已存在的 Profile。");
      if (!channel) issues.push("渠道为必填项。");
      if (!peerKind) issues.push("Peer 类型为必填项。");
      if (!peerId) issues.push("Peer ID 为必填项。");
      if (duplicateKeyCount.get(duplicateKey) && (duplicateKeyCount.get(duplicateKey) || 0) > 1) {
        issues.push("存在重复的路由规则（agent/channel/peer 组合重复）。");
      }

      return issues;
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
  let unsavedProfileRefIssues = $derived(buildUnsavedProfileReferenceIssues());

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

  async function load() {
    loading = true;
    error = "";
    notice = "";
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

      updateBaselinesFromCurrent();
    } catch (err) {
      error = normalizeError(err);
    } finally {
      loading = false;
      loaded = true;
    }
  }

  async function persistProfilesOnly() {
    const payload = buildProfilesPayload();
    await api.putAgentProfiles(component, name, payload);
  }

  async function persistBindingsOnly() {
    const payload = buildBindingsPayload();
    await api.putAgentBindings(component, name, payload);
  }

  async function saveProfiles() {
    if (hasProfileIssues) {
      activeTab = "profiles";
      error = "Profiles 存在校验问题，请先修复后再保存。";
      return;
    }

    savingProfiles = true;
    error = "";
    notice = "";
    try {
      await persistProfilesOnly();
      notice = `Profiles 已保存（${profiles.length} 项）`;
      await load();
    } catch (err) {
      error = normalizeError(err);
    } finally {
      savingProfiles = false;
    }
  }

  async function saveBindings() {
    if (hasBindingIssues) {
      activeTab = "bindings";
      error = "Bindings 存在校验问题，请先修复后再保存。";
      return;
    }
    if (hasBlockingBindingReferences) {
      activeTab = "bindings";
      error = "存在引用未保存 Profile 的 Binding，请先保存 Profiles。";
      return;
    }

    savingBindings = true;
    error = "";
    notice = "";
    try {
      await persistBindingsOnly();
      notice = `Bindings 已保存（${bindings.length} 项）`;
      await load();
    } catch (err) {
      error = normalizeError(err);
    } finally {
      savingBindings = false;
    }
  }

  async function saveAll() {
    if (!hasAnyDirty) {
      notice = "当前没有可保存的改动。";
      error = "";
      return;
    }

    if (hasProfileIssues) {
      activeTab = "profiles";
      error = "Profiles 存在校验问题，已定位到 Profiles 标签。";
      notice = "";
      return;
    }

    if (hasBindingIssues || hasBlockingBindingReferences) {
      activeTab = "bindings";
      error = hasBlockingBindingReferences
        ? "Bindings 引用了未持久化的 Profile，请先保存 Profiles 或使用“保存全部改动”。"
        : "Bindings 存在校验问题，已定位到 Bindings 标签。";
      notice = "";
      return;
    }

    savingAll = true;
    error = "";
    notice = "";

    let savedProfiles = false;
    let savedBindings = false;

    try {
      if (profilesDirty) {
        await persistProfilesOnly();
        savedProfiles = true;
      }

      if (bindingsDirty) {
        await persistBindingsOnly();
        savedBindings = true;
      }

      await load();

      if (savedProfiles && savedBindings) {
        notice = "Profiles 与 Bindings 已全部保存。";
      } else if (savedProfiles) {
        notice = "Profiles 已保存（Bindings 无改动）。";
      } else if (savedBindings) {
        notice = "Bindings 已保存（Profiles 无改动）。";
      }
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
      <h3>代理工作区</h3>
      <p>在实例内维护 Profiles 与 Bindings，保存顺序按“Profiles → Bindings”。</p>
    </div>
    <div class="row-actions">
      <button class="ghost-btn" onclick={() => load()} disabled={busy}>
        {loading ? "刷新中..." : "刷新"}
      </button>
      <button class="primary-btn" onclick={saveAll} disabled={busy || !hasAnyDirty}>
        {savingAll ? "保存中..." : "保存全部改动"}
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
      Profiles
      <span>{profiles.length}</span>
      {#if profileIssueRows > 0}
        <em>{profileIssueRows} 问题</em>
      {:else if profilesDirty}
        <em>有改动</em>
      {/if}
    </button>

    <button
      class="tab-chip"
      class:active={activeTab === "bindings"}
      onclick={() => (activeTab = "bindings")}
      type="button"
    >
      Bindings
      <span>{bindings.length}</span>
      {#if bindingIssueRows > 0}
        <em>{bindingIssueRows} 问题</em>
      {:else if bindingsDirty}
        <em>有改动</em>
      {/if}
    </button>
  </div>

  {#if error}
    <div class="banner error">{error}</div>
  {/if}
  {#if notice}
    <div class="banner success">{notice}</div>
  {/if}

  {#if !loaded || loading}
    <div class="empty">正在加载代理配置...</div>
  {:else}
    {#if activeTab === "profiles"}
      <section class="card">
        <div class="card-head">
          <div>
            <h4>Profiles</h4>
            <p>Profiles 对应 `agents.list[]`，默认主模型位于 `agents.defaults.model.primary`。</p>
          </div>
          <div class="row-actions">
            <button class="ghost-btn" onclick={addProfile} disabled={busy}>添加 Profile</button>
            <button class="primary-btn" onclick={saveProfiles} disabled={busy || !profilesDirty || hasProfileIssues}>
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
                <button class="danger-btn" onclick={() => removeProfile(index)} disabled={busy}>移除</button>
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
    {/if}

    {#if activeTab === "bindings"}
      <section class="card">
        <div class="card-head">
          <div>
            <h4>Bindings</h4>
            <p>Bindings 用于将渠道与 peer 路由到指定 Profile。支持 legacy `#topic:`，保存时会转换为 `:thread:`。</p>
          </div>
          <div class="row-actions">
            <button class="ghost-btn" onclick={addBinding} disabled={busy}>添加 Binding</button>
            <button
              class="primary-btn"
              onclick={saveBindings}
              disabled={busy || !bindingsDirty || hasBindingIssues || hasBlockingBindingReferences}
            >
              {savingBindings ? "保存中..." : "保存 Bindings"}
            </button>
          </div>
        </div>

        {#if hasBlockingBindingReferences}
          <div class="banner warn">
            <div>
              <strong>检测到 {unsavedProfileRefIssues.length} 条 Binding 引用了未保存 Profile。</strong>
              <p>请先保存 Profiles，再保存 Bindings；或直接使用“保存全部改动”。</p>
            </div>
            <button class="ghost-btn" type="button" onclick={gotoProfilesTab}>去保存 Profiles</button>
          </div>
        {/if}

        {#if bindings.length === 0}
          <div class="empty subtle">暂无 Bindings，流量将继续使用默认路径。</div>
        {/if}

        <div class="stack">
          {#each bindings as binding, index}
            <article class="entry">
              <div class="entry-head">
                <strong>{binding.agent_id || `Binding ${index + 1}`}</strong>
                <button class="danger-btn" onclick={() => removeBinding(index)} disabled={busy}>移除</button>
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

  .status-strip {
    display: flex;
    gap: 0.6rem;
    flex-wrap: wrap;
  }

  .tab-chip {
    border: 1px solid var(--slate-300);
    background: white;
    color: var(--slate-700);
    border-radius: 999px;
    padding: 0.45rem 0.8rem;
    cursor: pointer;
    display: inline-flex;
    align-items: center;
    gap: 0.45rem;
    font-weight: 600;
  }

  .tab-chip span {
    font-family: var(--font-mono);
    color: var(--slate-500);
    font-size: 0.8rem;
  }

  .tab-chip em {
    color: var(--amber-700);
    font-style: normal;
    font-size: 0.76rem;
  }

  .tab-chip.active {
    border-color: var(--indigo-500);
    background: var(--indigo-50);
    color: var(--indigo-700);
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

  .banner.warn {
    border: 1px solid var(--amber-200);
    background: var(--amber-50);
    color: var(--amber-800);
    display: flex;
    gap: 0.8rem;
    justify-content: space-between;
    align-items: flex-start;
    margin-bottom: 0.85rem;
  }

  .banner.warn p {
    margin: 0.3rem 0 0;
    color: var(--amber-700);
    font-size: 0.86rem;
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
    .entry-head,
    .banner.warn {
      flex-direction: column;
    }
  }
</style>
