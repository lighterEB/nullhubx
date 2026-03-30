<script lang="ts">
  import { api } from "$lib/api/client";
  import { t } from "$lib/i18n/index.svelte";
  import {
    describeInstanceCliError,
    isInstanceCliError,
  } from "$lib/instanceCli";

  type Skill = {
    name: string;
    version: string;
    description: string;
    author: string;
    enabled: boolean;
    always: boolean;
    available: boolean;
    missing_deps: string;
    path: string;
    source: string;
    instructions_bytes: number;
  };

  type CatalogEntry = {
    name: string;
    version: string;
    description: string;
    author?: string;
    recommended: boolean;
    install_kind: string;
    source?: string;
    homepage_url?: string;
    clawhub_slug?: string;
    always?: boolean;
  };

  type InstallResult = {
    status?: string;
    restart_required?: boolean;
  };

  let { component, name, active = false } = $props<{
    component: string;
    name: string;
    active?: boolean;
  }>();

  let skills = $state<Skill[]>([]);
  let catalog = $state<CatalogEntry[]>([]);
  let loading = $state(false);
  let catalogLoading = $state(false);
  let error = $state<string | null>(null);
  let catalogError = $state<string | null>(null);
  let actionError = $state<string | null>(null);
  let actionMessage = $state<string | null>(null);
  let loadedKey = $state("");
  let catalogLoadedKey = $state("");
  let requestSeq = 0;
  let catalogRequestSeq = 0;
  let busyAction = $state<string | null>(null);
  let clawhubSlug = $state("");
  let sourceInput = $state("");

  const instanceKey = $derived(`${component}/${name}`);
  const supportsInstall = $derived(component === "nullclaw");
  const installedSkillNames = $derived(new Set(skills.map((skill) => skill.name)));
  const sortedSkills = $derived(
    [...skills].sort((a, b) => {
      if (a.available !== b.available) return a.available ? -1 : 1;
      if (a.always !== b.always) return a.always ? -1 : 1;
      return a.name.localeCompare(b.name);
    }),
  );
  const sortedCatalog = $derived(
    [...catalog].sort((a, b) => {
      if (a.recommended !== b.recommended) return a.recommended ? -1 : 1;
      return a.name.localeCompare(b.name);
    }),
  );

  function translate(key: string, replacements: Record<string, string | number> = {}): string {
    let message = t(key);
    for (const [name, value] of Object.entries(replacements)) {
      message = message.replace(`{${name}}`, String(value));
    }
    return message;
  }

  async function loadSkills(force = false) {
    if (!active || !component || !name) return;
    const contextKey = instanceKey;
    const nextKey = `${contextKey}:skills`;
    if (!force && loadedKey === nextKey) return;

    const req = ++requestSeq;
    loading = true;
    error = null;
    try {
      const result = await api.getSkills(component, name);
      if (req !== requestSeq || contextKey !== instanceKey || !active) return;
      if (isInstanceCliError(result)) {
        skills = [];
        error = describeInstanceCliError(result, t("skillsPanel.unavailable"));
      } else {
        skills = Array.isArray(result) ? result : [];
        error = null;
      }
      loadedKey = nextKey;
    } catch (err) {
      if (req !== requestSeq || contextKey !== instanceKey || !active) return;
      skills = [];
      error = (err as Error).message || t("skillsPanel.loadSkillsFailed");
    } finally {
      if (req === requestSeq && contextKey === instanceKey) {
        loading = false;
      }
    }
  }

  async function loadCatalog(force = false) {
    if (!active || !supportsInstall || !component || !name) return;
    const contextKey = instanceKey;
    const nextKey = `${contextKey}:skills:catalog`;
    if (!force && catalogLoadedKey === nextKey) return;

    const req = ++catalogRequestSeq;
    catalogLoading = true;
    catalogError = null;
    try {
      const result = await api.getSkillCatalog(component, name);
      if (req !== catalogRequestSeq || contextKey !== instanceKey || !active) return;
      catalog = Array.isArray(result) ? result : [];
      catalogLoadedKey = nextKey;
    } catch (err) {
      if (req !== catalogRequestSeq || contextKey !== instanceKey || !active) return;
      catalog = [];
      catalogError = (err as Error).message || t("skillsPanel.loadRecommendedFailed");
    } finally {
      if (req === catalogRequestSeq && contextKey === instanceKey) {
        catalogLoading = false;
      }
    }
  }

  async function refreshAll() {
    loadedKey = "";
    catalogLoadedKey = "";
    await Promise.all([loadSkills(true), loadCatalog(true)]);
  }

  async function installBundled(entry: CatalogEntry) {
    actionError = null;
    actionMessage = null;
    busyAction = `bundled:${entry.name}`;
    try {
      const result = await api.installBundledSkill(component, name, entry.name) as InstallResult;
      if (isInstanceCliError(result)) {
        throw new Error(describeInstanceCliError(result, translate("skillsPanel.installFailed", { name: entry.name })));
      }
      const baseMessage = result?.status === "updated"
        ? translate("skillsPanel.updated", { name: entry.name })
        : translate("skillsPanel.installedOne", { name: entry.name });
      actionMessage = result?.restart_required
        ? `${baseMessage}${t("skillsPanel.restartHint")}`
        : baseMessage;
      await refreshAll();
    } catch (err) {
      actionError = (err as Error).message || translate("skillsPanel.installFailed", { name: entry.name });
    } finally {
      busyAction = null;
    }
  }

  async function installFromClawhub() {
    const slug = clawhubSlug.trim();
    if (!slug) {
      actionError = t("skillsPanel.enterClawhubSlug");
      actionMessage = null;
      return;
    }
    actionError = null;
    actionMessage = null;
    busyAction = `clawhub:${slug}`;
    try {
      const result = await api.installSkillFromClawhub(component, name, slug);
      if (isInstanceCliError(result)) {
        throw new Error(describeInstanceCliError(result, translate("skillsPanel.installFromClawhubFailed", { slug })));
      }
      clawhubSlug = "";
      actionMessage = translate("skillsPanel.installedFromClawhub", { slug });
      await refreshAll();
    } catch (err) {
      actionError = (err as Error).message || translate("skillsPanel.installFromClawhubFailed", { slug });
    } finally {
      busyAction = null;
    }
  }

  async function installFromSource() {
    const source = sourceInput.trim();
    if (!source) {
      actionError = t("skillsPanel.enterSource");
      actionMessage = null;
      return;
    }
    actionError = null;
    actionMessage = null;
    busyAction = `source:${source}`;
    try {
      const result = await api.installSkillFromSource(component, name, source);
      if (isInstanceCliError(result)) {
        throw new Error(describeInstanceCliError(result, t("skillsPanel.installFromSourceFailed")));
      }
      sourceInput = "";
      actionMessage = t("skillsPanel.installedFromSource");
      await refreshAll();
    } catch (err) {
      actionError = (err as Error).message || t("skillsPanel.installFromSourceFailed");
    } finally {
      busyAction = null;
    }
  }

  async function removeSkill(skillName: string) {
    actionError = null;
    actionMessage = null;
    busyAction = `remove:${skillName}`;
    try {
      const result = await api.removeSkill(component, name, skillName);
      if (isInstanceCliError(result)) {
        throw new Error(describeInstanceCliError(result, translate("skillsPanel.removeFailed", { name: skillName })));
      }
      actionMessage = translate("skillsPanel.removed", { name: skillName });
      await refreshAll();
    } catch (err) {
      actionError = (err as Error).message || translate("skillsPanel.removeFailed", { name: skillName });
    } finally {
      busyAction = null;
    }
  }

  function installLabel(entry: CatalogEntry) {
    if (entry.install_kind === "bundled") return t("skillsPanel.bundled");
    if (entry.install_kind === "clawhub") return "ClawHub";
    return t("skillsPanel.sourceInstall");
  }

  $effect(() => {
    if (!active || !component || !name) return;
    if (loadedKey === `${instanceKey}:skills` && (!supportsInstall || catalogLoadedKey === `${instanceKey}:skills:catalog`)) return;
    skills = [];
    catalog = [];
    error = null;
    catalogError = null;
    void refreshAll();
  });
</script>

<div class="skills-panel">
  <div class="panel-toolbar">
    <div>
      <h2>{t("skillsPanel.title")}</h2>
      <p>{t("skillsPanel.subtitle")}</p>
    </div>
    <button class="toolbar-btn" onclick={() => void refreshAll()} disabled={loading || catalogLoading || busyAction !== null}>
      {t("skillsPanel.refresh")}
    </button>
  </div>

  {#if supportsInstall}
    <section class="skill-section">
      <div class="section-header">
        <div>
          <h3>{t("skillsPanel.recommendedTitle")}</h3>
          <p>{t("skillsPanel.recommendedSubtitle")}</p>
        </div>
      </div>

      {#if actionMessage}
        <div class="panel-state success">{actionMessage}</div>
      {/if}
      {#if actionError}
        <div class="panel-state warning">{actionError}</div>
      {/if}
      {#if catalogError}
        <div class="panel-state warning">{catalogError}</div>
      {:else if catalogLoading && sortedCatalog.length === 0}
        <div class="panel-state">{t("skillsPanel.loadingRecommended")}</div>
      {:else if sortedCatalog.length > 0}
        <div class="skill-grid">
          {#each sortedCatalog as entry}
            <article class="skill-card recommended" class:installed={installedSkillNames.has(entry.name)}>
              <header>
                <div>
                  <div class="skill-name">
                    {entry.name}
                    <span class="skill-version">v{entry.version || "-"}</span>
                  </div>
                  {#if entry.description}
                    <div class="skill-description">{entry.description}</div>
                  {/if}
                </div>
                <div class="skill-badges">
                  {#if entry.recommended}
                    <span class="badge accent">{t("skillsPanel.recommendedBadge")}</span>
                  {/if}
                  {#if entry.always}
                    <span class="badge accent">{t("skillsPanel.defaultBadge")}</span>
                  {/if}
                  {#if installedSkillNames.has(entry.name)}
                    <span class="badge ok">{t("skillsPanel.installedBadge")}</span>
                  {/if}
                </div>
              </header>

              <div class="skill-meta">
                <div>
                  <span>{t("skillsPanel.installMethod")}</span>
                  <strong>{installLabel(entry)}</strong>
                </div>
                <div>
                  <span>{t("skillsPanel.source")}</span>
                  <strong>{entry.source || entry.clawhub_slug || "nullhubx"}</strong>
                </div>
                <div>
                  <span>{t("skillsPanel.homepage")}</span>
                  <strong>{entry.homepage_url || "-"}</strong>
                </div>
              </div>

              <div class="skill-actions">
                <button
                  class="toolbar-btn"
                  onclick={() => void installBundled(entry)}
                  disabled={busyAction !== null || entry.install_kind !== "bundled"}
                >
                  {installedSkillNames.has(entry.name) ? t("skillsPanel.reinstall") : t("skillsPanel.install")}
                </button>
                {#if entry.homepage_url}
                  <a class="toolbar-link" href={entry.homepage_url} target="_blank" rel="noreferrer">{t("skillsPanel.view")}</a>
                {/if}
              </div>
            </article>
          {/each}
        </div>
      {/if}

      <div class="install-grid">
        <form class="install-card" onsubmit={(event) => {
          event.preventDefault();
          void installFromClawhub();
        }}>
          <div>
            <h4>{t("skillsPanel.clawhubTitle")}</h4>
            <p>{t("skillsPanel.clawhubSubtitle")} <code>clawhub install</code>.</p>
          </div>
          <input
            bind:value={clawhubSlug}
            type="text"
            placeholder="my-skill"
            disabled={busyAction !== null}
          />
          <div class="skill-actions">
            <button class="toolbar-btn" type="submit" disabled={busyAction !== null}>{t("skillsPanel.install")}</button>
            <a class="toolbar-link" href="https://clawhub.ai" target="_blank" rel="noreferrer">{t("skillsPanel.browseClawhub")}</a>
          </div>
        </form>

        <form class="install-card" onsubmit={(event) => {
          event.preventDefault();
          void installFromSource();
        }}>
          <div>
            <h4>{t("skillsPanel.sourceTitle")}</h4>
            <p>{t("skillsPanel.sourceSubtitle")} <code>nullclaw skills install</code>.</p>
          </div>
          <input
            bind:value={sourceInput}
            type="text"
            placeholder="https://github.com/owner/repo.git"
            disabled={busyAction !== null}
          />
          <div class="skill-actions">
            <button class="toolbar-btn" type="submit" disabled={busyAction !== null}>{t("skillsPanel.install")}</button>
          </div>
        </form>
      </div>
    </section>
  {/if}

  {#if error}
    <div class="panel-state warning">{error}</div>
  {:else if loading && skills.length === 0}
    <div class="panel-state">{t("skillsPanel.loadingSkills")}</div>
  {:else if sortedSkills.length === 0}
    <div class="panel-state">{t("skillsPanel.empty")}</div>
  {:else}
    <div class="skill-grid">
      {#each sortedSkills as skill}
        <article class="skill-card" class:missing={!skill.available}>
          <header>
            <div>
              <div class="skill-name">
                {skill.name}
                <span class="skill-version">v{skill.version || "-"}</span>
              </div>
              {#if skill.description}
                <div class="skill-description">{skill.description}</div>
              {/if}
            </div>
            <div class="skill-badges">
              <span class:ok={skill.available} class="badge">
                {skill.available ? t("skillsPanel.available") : t("skillsPanel.missingDeps")}
              </span>
              {#if skill.always}
                <span class="badge accent">{t("skillsPanel.defaultBadge")}</span>
              {/if}
              {#if skill.enabled}
                <span class="badge">{t("skillsPanel.enabled")}</span>
              {/if}
            </div>
          </header>

          <div class="skill-meta">
            <div>
              <span>{t("skillsPanel.source")}</span>
              <strong>{skill.source || "-"}</strong>
            </div>
            <div>
              <span>{t("skillsPanel.author")}</span>
              <strong>{skill.author || "-"}</strong>
            </div>
            <div>
              <span>{t("skillsPanel.instructions")}</span>
              <strong>{translate("skillsPanel.bytes", { count: skill.instructions_bytes ?? 0 })}</strong>
            </div>
          </div>

          <div class="skill-path mono">{skill.path || "-"}</div>

          {#if skill.missing_deps}
            <div class="missing-deps">{translate("skillsPanel.missingDependencies", { deps: skill.missing_deps })}</div>
          {/if}

          {#if skill.source === "workspace" && supportsInstall}
            <div class="skill-actions">
              <button class="toolbar-btn danger" onclick={() => void removeSkill(skill.name)} disabled={busyAction !== null}>
                {t("skillsPanel.remove")}
              </button>
            </div>
          {/if}
        </article>
      {/each}
    </div>
  {/if}
</div>

<style>
  .skills-panel {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-lg);
  }

  .skill-section {
    display: flex;
    flex-direction: column;
    gap: var(--spacing-md);
    padding: var(--spacing-lg);
    border: 1px solid rgba(141, 154, 178, 0.18);
    background: linear-gradient(180deg, rgba(255, 255, 255, 0.84), rgba(245, 249, 255, 0.72));
    border-radius: var(--radius-lg);
    box-shadow: var(--shadow-sm);
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

  .panel-toolbar h2 {
    font-size: 1.1rem;
  }

  .section-header h3 {
    font-size: 1rem;
  }

  .panel-toolbar p,
  .section-header p {
    margin: 0.25rem 0 0;
    color: var(--slate-600);
    font-size: 0.875rem;
    line-height: 1.45;
  }

  .install-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
    gap: var(--spacing-md);
  }

  .install-card {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;
    padding: 1rem;
    border: 1px solid rgba(141, 154, 178, 0.18);
    background: rgba(255, 255, 255, 0.72);
    border-radius: var(--radius-lg);
  }

  .install-card h4 {
    margin: 0;
    font-size: 0.95rem;
    color: var(--slate-900);
  }

  .install-card p {
    margin: 0.25rem 0 0;
    color: var(--slate-600);
    font-size: 0.82rem;
    line-height: 1.45;
  }

  .install-card input {
    width: 100%;
    padding: 0.7rem 0.8rem;
    border: 1px solid rgba(141, 154, 178, 0.22);
    background: rgba(255, 255, 255, 0.84);
    color: var(--slate-900);
    border-radius: var(--radius-md);
    font-family: var(--font-mono);
    font-size: 0.82rem;
  }

  .install-card input:focus {
    outline: none;
    border-color: rgba(34, 211, 238, 0.38);
    box-shadow: 0 0 0 3px rgba(34, 211, 238, 0.12);
  }

  .toolbar-btn,
  .toolbar-link {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 0.35rem;
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
    text-decoration: none;
    transition:
      border-color 0.18s ease,
      background 0.18s ease,
      color 0.18s ease,
      transform 0.18s ease;
  }

  .toolbar-btn:hover,
  .toolbar-link:hover {
    border-color: rgba(34, 211, 238, 0.26);
    color: var(--cyan-700);
    transform: translateY(-1px);
  }

  .toolbar-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .toolbar-btn.danger {
    border-color: rgba(244, 63, 94, 0.22);
    color: var(--rose-700);
  }

  .panel-state {
    padding: 1.4rem;
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

  .panel-state.success {
    border-color: rgba(16, 185, 129, 0.22);
    color: var(--emerald-700);
    background: rgba(236, 253, 245, 0.88);
  }

  .skill-grid {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(280px, 1fr));
    gap: var(--spacing-md);
  }

  .skill-card {
    display: flex;
    flex-direction: column;
    gap: 0.9rem;
    padding: 1rem;
    border: 1px solid rgba(141, 154, 178, 0.18);
    background: linear-gradient(180deg, rgba(255, 255, 255, 0.84), rgba(245, 249, 255, 0.72));
    border-radius: var(--radius-lg);
    box-shadow: var(--shadow-sm);
  }

  .skill-card.recommended {
    border-color: rgba(34, 211, 238, 0.2);
  }

  .skill-card.installed {
    box-shadow:
      var(--shadow-sm),
      inset 0 0 0 1px rgba(16, 185, 129, 0.22);
  }

  .skill-card.missing {
    border-color: rgba(245, 158, 11, 0.24);
  }

  .skill-card header {
    display: flex;
    justify-content: space-between;
    gap: 1rem;
  }

  .skill-name {
    font-size: 0.95rem;
    font-weight: 700;
    color: var(--slate-900);
  }

  .skill-version {
    margin-left: 0.35rem;
    color: var(--cyan-700);
    font-family: var(--font-mono);
    font-size: 0.78rem;
  }

  .skill-description {
    margin-top: 0.35rem;
    color: var(--slate-600);
    font-size: 0.82rem;
    line-height: 1.45;
  }

  .skill-badges {
    display: flex;
    flex-wrap: wrap;
    gap: 0.35rem;
    justify-content: flex-end;
  }

  .badge {
    padding: 0.2rem 0.5rem;
    border: 1px solid rgba(141, 154, 178, 0.18);
    border-radius: 999px;
    color: var(--slate-500);
    font-size: 0.68rem;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    background: rgba(255, 255, 255, 0.72);
  }

  .badge.ok {
    border-color: rgba(16, 185, 129, 0.22);
    color: var(--emerald-700);
  }

  .badge.accent {
    border-color: rgba(34, 211, 238, 0.22);
    color: var(--cyan-700);
  }

  .skill-meta {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 0.75rem;
  }

  .skill-meta div {
    display: flex;
    flex-direction: column;
    gap: 0.15rem;
    min-width: 0;
  }

  .skill-meta span {
    font-size: 0.68rem;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--slate-500);
  }

  .skill-meta strong {
    font-size: 0.82rem;
    line-height: 1.35;
    word-break: break-word;
    color: var(--slate-800);
  }

  .skill-path,
  .missing-deps {
    font-size: 0.8rem;
    color: var(--slate-600);
  }

  .skill-path {
    padding: 0.7rem 0.8rem;
    border-radius: var(--radius-md);
    background: rgba(248, 250, 252, 0.92);
    border: 1px solid rgba(141, 154, 178, 0.14);
    overflow-wrap: anywhere;
  }

  .missing-deps {
    padding: 0.75rem 0.8rem;
    border: 1px dashed rgba(245, 158, 11, 0.2);
    border-radius: var(--radius-md);
    background: rgba(255, 251, 235, 0.8);
  }

  .skill-actions {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5rem;
  }

  @media (max-width: 720px) {
    .panel-toolbar,
    .section-header,
    .skill-card header {
      flex-direction: column;
      align-items: stretch;
    }

    .skill-meta {
      grid-template-columns: 1fr;
    }

    .skill-badges {
      justify-content: flex-start;
    }
  }
</style>
