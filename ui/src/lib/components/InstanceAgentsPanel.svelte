<script lang="ts">
  import { onMount } from "svelte";
  import {
    api,
    type AgentBindingsResponse,
    type AgentProfilesResponse,
  } from "$lib/api/client";
  import { channelSchemas } from "$lib/components/configSchemas";
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

      if (!agentId) issues.push(t("agentsPanel.agentIdRequired"));
      if (agentId && !validAgentIds.has(agentId)) issues.push(t("agentsPanel.agentIdMatchProfile"));
      if (!channel) issues.push(t("agentsPanel.channelRequired"));
      if (!peerKind) issues.push(t("agentsPanel.peerKindRequired"));
      if (!peerId) issues.push(t("agentsPanel.peerIdRequired"));
      if (duplicateKeyCount.get(duplicateKey) && (duplicateKeyCount.get(duplicateKey) || 0) > 1) {
        issues.push(t("agentsPanel.duplicateRoute"));
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
        api
          .getAgentProfiles(component, name)
          .catch((): AgentProfilesResponse => ({ defaults: {}, profiles: [] })),
        api
          .getAgentBindings(component, name)
          .catch((): AgentBindingsResponse => ({ bindings: [] })),
      ]);

      defaultsModelPrimary = profilesRes?.defaults?.model_primary ?? "";
      profiles = Array.isArray(profilesRes?.profiles)
        ? profilesRes.profiles.map((item) => ({
            id: item?.id ?? "",
            provider: item?.provider ?? "",
            model: item?.model ?? "",
            system_prompt: item?.system_prompt ?? "",
            temperature: typeof item?.temperature === "number" ? item.temperature : null,
            max_depth: typeof item?.max_depth === "number" ? item.max_depth : 3,
          }))
        : [];
      bindings = Array.isArray(bindingsRes?.bindings)
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
      error = t("agentsPanel.profilesInvalidSave");
      return;
    }

    savingProfiles = true;
    error = "";
    notice = "";
    try {
      await persistProfilesOnly();
      notice = translate("agentsPanel.profilesSaved", { count: profiles.length });
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
      error = t("agentsPanel.bindingsInvalidSave");
      return;
    }
    if (hasBlockingBindingReferences) {
      activeTab = "bindings";
      error = t("agentsPanel.bindingsUnsavedProfile");
      return;
    }

    savingBindings = true;
    error = "";
    notice = "";
    try {
      await persistBindingsOnly();
      notice = translate("agentsPanel.bindingsSaved", { count: bindings.length });
      await load();
    } catch (err) {
      error = normalizeError(err);
    } finally {
      savingBindings = false;
    }
  }

  async function saveAll() {
    if (!hasAnyDirty) {
      notice = t("agentsPanel.noChangesToSave");
      error = "";
      return;
    }

    if (hasProfileIssues) {
      activeTab = "profiles";
      error = t("agentsPanel.profilesInvalidTab");
      notice = "";
      return;
    }

    if (hasBindingIssues || hasBlockingBindingReferences) {
      activeTab = "bindings";
      error = hasBlockingBindingReferences
        ? t("agentsPanel.bindingsUnsavedProfileAll")
        : t("agentsPanel.bindingsInvalidTab");
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
        notice = t("agentsPanel.savedAll");
      } else if (savedProfiles) {
        notice = t("agentsPanel.savedProfilesOnly");
      } else if (savedBindings) {
        notice = t("agentsPanel.savedBindingsOnly");
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
  {#if notice}
    <div class="banner success">{notice}</div>
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
                  <input bind:value={profile.provider} placeholder="openrouter" />
                </label>
                <label class="field">
                  <span>{t("agentsPanel.model")}</span>
                  <input bind:value={profile.model} placeholder="openai/gpt-5-mini" />
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
              <div class="grid">
                <label class="field">
                  <span>{t("agentsPanel.agentId")}</span>
                  <input bind:value={binding.agent_id} list="agent-profile-ids" placeholder="coder" />
                </label>
                <label class="field">
                  <span>{t("agentsPanel.channelLabel")}</span>
                  <input bind:value={binding.match.channel} list="agent-channel-types" placeholder="telegram" />
                </label>
                <label class="field">
                  <span>{t("agentsPanel.accountId")}</span>
                  <input bind:value={binding.match.account_id} placeholder="main" />
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
  }
</style>
