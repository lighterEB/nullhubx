<script lang="ts">
  import WizardStep from "./WizardStep.svelte";
  import ProviderList from "./ProviderList.svelte";
  import ChannelList from "./ChannelList.svelte";
  import {
    api,
    type JsonObject,
    type JsonValue,
    type ValidationResultPayload,
    type VersionOptionPayload,
  } from "$lib/api/client";
  import { t } from "$lib/i18n/index.svelte";

  type WizardOption = {
    value: string;
    label: string;
    description?: string;
    recommended?: boolean;
  };

  type WizardCondition = {
    step: string;
    equals?: string;
    not_equals?: string;
    contains?: string;
    not_in?: string;
  };

  type WizardStepDef = {
    id: string;
    title: string;
    description?: string;
    type: string;
    options?: WizardOption[];
    default_value?: string;
    advanced?: boolean;
    group?: string;
    condition?: WizardCondition;
  };

  type VersionOption = {
    value: string;
    label: string;
    recommended?: boolean;
  };

  type WizardProviderEntry = JsonObject & {
    provider: string;
    api_key: string;
    model: string;
  };

  type ChannelConfig = Record<string, Record<string, Record<string, JsonValue>>>;

  let {
    component = "",
    steps = [],
    onComplete,
  } = $props<{
    component: string;
    steps: WizardStepDef[];
    onComplete?: () => void;
  }>();

  let answers = $state<Record<string, string>>({});
  let instanceName = $state("");
  let currentPage = $state(0);
  let installing = $state(false);
  let installMessage = $state("");
  let versions = $state<VersionOption[]>([]);
  let selectedVersion = $state("latest");
  let channels = $state<ChannelConfig>({});
  const instanceNameId = "wizard-instance-name";

  // Validation state
  let validating = $state(false);
  let providerValidationResults = $state<ValidationResultPayload[]>([]);
  let channelValidationResults = $state<ValidationResultPayload[]>([]);
  let validationError = $state("");
  let validationWarning = $state("");
  let existingInstanceNames = $state<string[]>([]);
  let showProviderRequiredError = $state(false);
  const providerValidationView = $derived(
    providerValidationResults.map((result) => ({
      provider: result.provider ?? "",
      live_ok: !!result.live_ok,
      reason: result.reason ?? result.error ?? "",
    })),
  );
  const channelValidationView = $derived(
    channelValidationResults.map((result) => ({
      channel: result.channel ?? "",
      account: result.account ?? result.account_id ?? "",
      live_ok: !!result.live_ok,
      reason: result.reason ?? result.error ?? "",
    })),
  );

  // Auto-generate instance name on mount
  $effect(() => {
    if (component && !instanceName) {
      api
        .getInstances()
        .then((data) => {
          const existing = data?.instances?.[component] || {};
          const names = Object.keys(existing);
          existingInstanceNames = names;
          let id = 1;
          while (names.includes(`instance-${id}`)) id++;
          instanceName = `instance-${id}`;
        })
        .catch(() => {
          existingInstanceNames = [];
          instanceName = "instance-1";
        });
    }
  });

  let trimmedInstanceName = $derived(instanceName.trim());
  let instanceNameError = $derived(
    !trimmedInstanceName
      ? t("wizard.instanceNameRequired")
      : existingInstanceNames.includes(trimmedInstanceName)
        ? t("wizard.instanceNameUnique")
        : "",
  );

  // Fetch available versions
  $effect(() => {
    if (component) {
      api
        .getVersions(component)
        .then((data) => {
          versions = Array.isArray(data)
            ? data.map((option: VersionOptionPayload) => ({
                value: option.value,
                label: option.label ?? option.value,
                recommended: option.recommended,
              }))
            : [];
          if (versions.length > 0) {
            const rec = versions.find((v) => v.recommended);
            selectedVersion = rec?.value || versions[0].value;
          }
        })
        .catch(() => {
          versions = [{ value: "latest", label: t("wizard.latest"), recommended: true }];
          selectedVersion = "latest";
        });
    }
  });

  // Apply default values from steps
  $effect(() => {
    for (const step of steps) {
      if (step.default_value && !(step.id in answers)) {
        answers[step.id] = step.default_value;
      } else if (step.options?.length && !(step.id in answers)) {
        const rec = step.options.find((o: WizardOption) => o.recommended);
        if (rec) answers[step.id] = rec.value;
      }
    }
  });

  $effect(() => {
    if (component === "nullboiler" && (answers["tracker_instance"] || "").length > 0) {
      answers["tracker_enabled"] = "true";
    }
  });

  // Initialize default provider entry when provider step exists
  $effect(() => {
    if (!("_providers" in answers)) {
      const providerStep = steps.find((s: WizardStepDef) => s.id === "provider");
      if (providerStep) {
        const rec = providerStep.options?.find((o: WizardOption) => o.recommended);
        const defaultProvider =
          rec?.value || providerStep.options?.[0]?.value || "";
        answers["_providers"] = JSON.stringify([
          { provider: defaultProvider, api_key: "", model: "" },
        ]);
      }
    }
  });

  function isStepVisible(step: WizardStepDef): boolean {
    if (!step.condition) return true;
    const ref = answers[step.condition.step] || "";
    if (step.condition.equals) return ref === step.condition.equals;
    if (step.condition.not_equals) return ref !== step.condition.not_equals;
    if (step.condition.contains)
      return ref.split(",").includes(step.condition.contains);
    if (step.condition.not_in) {
      const excluded = step.condition.not_in.split(",");
      return !excluded.includes(ref);
    }
    return true;
  }

  let settingsSteps = $derived(
    steps.filter(
      (s: WizardStepDef) =>
        s.id !== "provider" &&
        s.id !== "api_key" &&
        s.id !== "model" &&
        s.group !== "providers" &&
        s.group !== "channels" &&
        !s.advanced &&
        isStepVisible(s),
    ),
  );

  let advancedSteps = $derived(
    steps.filter(
      (s: WizardStepDef) =>
        s.advanced &&
        s.id !== "provider" &&
        s.id !== "api_key" &&
        s.id !== "model" &&
        isStepVisible(s),
    ),
  );

  let showAdvanced = $state(false);

  let providerStep = $derived(steps.find((s: WizardStepDef) => s.id === "provider"));
  let hasChannelsPage = $derived(component === "nullclaw");
  let pageKinds = $derived(
    hasChannelsPage ? ["setup", "channels", "settings"] : ["setup", "settings"],
  );
  let pageLabels = $derived(
    pageKinds.map((kind) =>
      kind === "setup" ? t("wizard.setupPage") : kind === "channels" ? t("wizard.channelsPage") : t("wizard.settingsPage"),
    ),
  );

  $effect(() => {
    if (currentPage >= pageKinds.length) {
      currentPage = pageKinds.length - 1;
    }
  });

  $effect(() => {
    component;
    steps;
    showAdvanced = false;
  });

  async function validateProviders(): Promise<boolean> {
    validating = true;
    validationError = "";
    validationWarning = "";
    providerValidationResults = [];
    showProviderRequiredError = false;

    try {
      const providers = JSON.parse(answers["_providers"] || "[]") as WizardProviderEntry[];
      if (providers.length === 0) {
        validationError = t("wizard.providerRequired");
        showProviderRequiredError = true;
        return false;
      }
      const result = await api.validateProviders(component, providers);
      providerValidationResults = result.results || [];
      validationWarning = result.saved_providers_warning || "";
      return providerValidationResults.every((result) => !!result.live_ok);
    } catch (e) {
      validationError = t("wizard.validationFailed").replace("{error}", (e as Error).message);
      return false;
    } finally {
      validating = false;
    }
  }

  async function validateChannels(): Promise<boolean> {
    validating = true;
    validationError = "";
    validationWarning = "";
    channelValidationResults = [];
    showProviderRequiredError = false;

    const hasNonDefaultChannels = Object.keys(channels).some(
      (k) => k !== "web" && k !== "cli",
    );
    if (!hasNonDefaultChannels) {
      validating = false;
      return true;
    }

    try {
      const result = await api.validateChannels(component, channels);
      channelValidationResults = result.results || [];
      validationWarning = result.saved_channels_warning || "";
      return channelValidationResults.every((result) => !!result.live_ok);
    } catch (e) {
      validationError = t("wizard.validationFailed").replace("{error}", (e as Error).message);
      return false;
    } finally {
      validating = false;
    }
  }

  async function handleNext() {
    const page = pageKinds[currentPage];
    if (page === "setup") {
      if (instanceNameError) {
        validationError = instanceNameError;
        showProviderRequiredError = false;
        return;
      }
      if (providerStep) {
        const valid = await validateProviders();
        if (!valid) return;
      }
      currentPage += 1;
      validationError = "";
      showProviderRequiredError = false;
      return;
    }

    if (page === "channels") {
      const valid = await validateChannels();
      if (!valid) return;
      currentPage += 1;
      validationError = "";
      showProviderRequiredError = false;
    }
  }

  function handleBack() {
    if (currentPage > 0) {
      currentPage -= 1;
      validationError = "";
      showProviderRequiredError = false;
    }
  }

  async function submit() {
    installing = true;
    installMessage = t("wizard.installing");
    try {
      const { _providers, ...rest } = answers;
      const payload: JsonObject = {
        instance_name: trimmedInstanceName,
        version: selectedVersion,
        ...rest,
      };
      if (_providers) {
        try {
          const parsed = JSON.parse(_providers) as WizardProviderEntry[];
          payload.providers = parsed;
          if (parsed.length > 0) {
            payload.provider = parsed[0].provider;
            payload.api_key = parsed[0].api_key || "";
            payload.model = parsed[0].model || "";
          }
        } catch {
          // Provider validation should have caught malformed JSON before submit.
        }
      }
      if (Object.keys(channels).length > 0) {
        payload.channels = channels;
      }
      const result = await api.postWizard(component, payload);
      installMessage = result.message || t("wizard.installComplete");
      setTimeout(() => onComplete?.(), 1500);
    } catch (e) {
      installMessage = `${t("common.error")}: ${(e as Error).message}`;
    } finally {
      installing = false;
    }
  }
</script>

<div class="wizard">
  <div class="wizard-header">
    <h2>{t("wizard.title").replace("{component}", component)}</h2>
      <div class="step-indicator">
      {#each pageLabels as label, i}
        <button
          class="step-dot"
          class:active={currentPage === i}
          class:completed={currentPage > i}
          disabled={i > currentPage}
          onclick={() => { if (i < currentPage) currentPage = i; }}
        >
          <span class="step-num">{i + 1}</span>
          <span class="step-label">{label}</span>
        </button>
        {#if i < pageLabels.length - 1}
          <div class="step-line" class:completed-before={i < currentPage}></div>
        {/if}
      {/each}
    </div>
  </div>

  <div class="wizard-body">
    {#if pageKinds[currentPage] === "setup"}
      <div class="name-step">
        <label for={instanceNameId}>{t("wizard.instanceName")}</label>
        <p class="name-hint">{t("wizard.instanceNameHint")}</p>
        <input
          id={instanceNameId}
          type="text"
          bind:value={instanceName}
          placeholder={t("wizard.instanceNamePlaceholder")}
        />
        {#if instanceNameError}
          <p class="name-error">{instanceNameError}</p>
        {/if}
      </div>

      {#if versions.length > 0}
        <div class="version-select">
          <label for="version-picker">{t("wizard.version")}</label>
          <select id="version-picker" bind:value={selectedVersion}>
            {#each versions as v, i}
              <option value={v.value}>
                {v.label}{i === 0 ? ` (${t("wizard.latestRecommended")})` : ""}
              </option>
            {/each}
          </select>
        </div>
      {/if}

      {#if providerStep}
        {#if showProviderRequiredError}
          <div class="provider-validation-error visible">{validationError}</div>
        {:else}
          <div class="provider-validation-error">{t("wizard.providerRequired")}</div>
        {/if}
        <ProviderList
          providers={providerStep.options || []}
          value={answers["_providers"] || "[]"}
          onchange={(v: string) => (answers["_providers"] = v)}
          {component}
          validationResults={providerValidationView}
        />
      {/if}
    {:else if pageKinds[currentPage] === "channels"}
      <ChannelList
        value={channels}
        onchange={(v: ChannelConfig) => (channels = v)}
        validationResults={channelValidationView}
      />
    {:else}
      {#each settingsSteps as step}
        <WizardStep
          {step}
          value={answers[step.id] || ""}
          onchange={(v) => (answers[step.id] = v)}
        />
      {/each}

      {#if advancedSteps.length > 0}
        <button class="advanced-toggle" onclick={() => (showAdvanced = !showAdvanced)}>
          <span class="advanced-arrow">{showAdvanced ? "\u25BC" : "\u25B6"}</span>
          {t("wizard.advanced")}
        </button>

        {#if showAdvanced}
          <div class="advanced-section">
            {#each advancedSteps as step}
              <WizardStep
                {step}
                value={answers[step.id] || ""}
                onchange={(v) => (answers[step.id] = v)}
              />
            {/each}
          </div>
        {/if}
      {/if}
    {/if}
  </div>

  {#if validationError}
    <div class="validation-error">{validationError}</div>
  {/if}

  {#if validationWarning}
    <div class="validation-warning">{validationWarning}</div>
  {/if}

  {#if installMessage}
    <div class="install-message">{installMessage}</div>
  {/if}

  <div class="wizard-footer">
    {#if currentPage > 0}
      <button class="secondary-btn" onclick={handleBack} disabled={validating || installing}>
        {t("common.back")}
      </button>
    {/if}
    <div class="footer-spacer"></div>
    {#if currentPage < pageKinds.length - 1}
      <button
        class="primary-btn"
        onclick={handleNext}
        disabled={validating || !!instanceNameError}
      >
        {validating ? t("wizard.validating") : `${t("common.next")} ->`}
      </button>
    {:else}
      <button
        class="primary-btn install-btn"
        onclick={submit}
        disabled={installing || !!instanceNameError}
      >
        {installing ? t("wizard.installing") : `${t("common.install")} ->`}
      </button>
    {/if}
  </div>
</div>

<style>
  .wizard {
    width: 100%;
    max-width: 800px;
    margin: 0 auto;
    padding: 1.9rem 2rem;
    border: 1px solid rgba(141, 154, 178, 0.18);
    border-radius: var(--radius-xl);
    background:
      radial-gradient(circle at top right, rgba(34, 211, 238, 0.12), transparent 34%),
      linear-gradient(180deg, rgba(255, 255, 255, 0.9), rgba(244, 248, 255, 0.8));
    box-shadow: var(--shadow-lg);
    backdrop-filter: blur(16px);
  }

  .wizard-header {
    padding: 0 0 1.4rem 0;
    border-bottom: 1px solid rgba(141, 154, 178, 0.16);
    margin-bottom: 1.4rem;
  }

  .wizard-header h2 {
    font-family: var(--font-display);
    font-size: clamp(1.1rem, 1rem + 0.5vw, 1.35rem);
    font-weight: 700;
    color: var(--slate-900);
    letter-spacing: -0.02em;
    margin: 0 0 1rem 0;
  }

  .step-indicator {
    display: flex;
    align-items: center;
    gap: 0;
    width: 100%;
  }

  .step-dot {
    display: flex;
    align-items: center;
    gap: 8px;
    background: none;
    border: none;
    cursor: pointer;
    padding: 0;
    transition: all 0.2s ease;
  }

  .step-dot:disabled { cursor: default; }

  .step-num {
    width: 24px;
    height: 24px;
    border-radius: 50%;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 12px;
    font-weight: 700;
    font-family: var(--font-mono);
    transition: all 0.2s ease;
  }

  .step-dot.active .step-num {
    background: linear-gradient(135deg, var(--cyan-500), var(--cyan-600));
    color: white;
    font-weight: 700;
    box-shadow: 0 10px 20px rgba(8, 145, 178, 0.24);
  }

  .step-dot.completed .step-num {
    background: rgba(34, 211, 238, 0.08);
    color: var(--cyan-700);
    border: 1px solid rgba(34, 211, 238, 0.18);
  }

  .step-dot:not(.active):not(.completed) .step-num {
    background: rgba(255, 255, 255, 0.9);
    color: var(--slate-400);
    border: 1px solid rgba(141, 154, 178, 0.18);
  }

  .step-label {
    font-family: var(--font-mono);
    font-size: 10px;
    letter-spacing: 1.5px;
    text-transform: uppercase;
    margin-left: 8px;
    transition: all 0.2s ease;
  }

  .step-dot.active .step-label {
    color: var(--cyan-700);
    font-weight: 600;
  }

  .step-dot.completed .step-label {
    color: var(--cyan-700);
  }

  .step-dot:not(.active):not(.completed) .step-label {
    color: var(--slate-400);
  }

  .step-line {
    flex: 1;
    height: 1px;
    margin: 0 16px;
    transition: all 0.2s ease;
  }

  .step-line.completed-before {
    background: rgba(34, 211, 238, 0.26);
  }

  .step-line:not(.completed-before) {
    background: var(--slate-200);
  }

  .wizard-body { padding: 0 0 1.5rem 0; }

  .name-step { margin-bottom: 2rem; }

  .name-step label {
    display: block;
    font-size: 0.8125rem;
    font-weight: 700;
    color: var(--fg-dim);
    margin-bottom: 0.25rem;
    text-transform: uppercase;
    letter-spacing: 1px;
  }

  .name-hint {
    font-size: 0.75rem;
    color: color-mix(in srgb, var(--fg-dim) 70%, transparent);
    margin-bottom: 0.5rem;
    font-family: var(--font-mono);
  }

  .name-step input {
    width: 100%;
    background: var(--bg-surface);
    border: 1px solid var(--border);
    border-radius: var(--radius-sm);
    padding: 0.625rem 0.875rem;
    color: var(--fg);
    font-size: 0.875rem;
    font-family: var(--font-mono);
    outline: none;
    transition: all 0.2s ease;
    box-shadow: inset 0 1px 2px rgba(15, 23, 42, 0.05);
  }

  .name-step input:focus {
    border-color: var(--accent);
    box-shadow: 0 0 8px var(--border-glow);
  }

  .version-select {
    margin-bottom: 2rem;
  }
  .version-select label {
    display: block;
    font-size: 0.8125rem;
    font-weight: 700;
    color: var(--fg-dim);
    margin-bottom: 0.5rem;
    text-transform: uppercase;
    letter-spacing: 1px;
  }
  .version-select select {
    width: 100%;
    background: var(--bg-surface);
    border: 1px solid var(--border);
    border-radius: var(--radius-sm);
    padding: 0.625rem 0.875rem;
    color: var(--fg);
    font-size: 0.875rem;
    font-family: var(--font-mono);
    outline: none;
    transition: all 0.2s ease;
    box-shadow: inset 0 1px 2px rgba(15, 23, 42, 0.05);
    cursor: pointer;
  }
  .version-select select:focus {
    border-color: var(--accent);
    box-shadow: 0 0 8px var(--border-glow);
  }

  .name-error {
    margin-top: 0.5rem;
    font-size: 0.75rem;
    color: var(--error, #e55);
    font-family: var(--font-mono);
  }

  .provider-validation-error {
    font-size: 0.8rem;
    color: var(--red-700);
    background: rgba(254, 242, 242, 0.92);
    border: 1px solid rgba(248, 113, 113, 0.24);
    border-radius: var(--radius-md);
    padding: 0.7rem 0.9rem;
    margin-bottom: 0.9rem;
    display: none;
    gap: 6px;
    align-items: center;
    box-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.7);
  }

  .provider-validation-error.visible {
    display: flex;
  }

  .provider-validation-error::before {
    content: '⚠';
    color: var(--red-600);
  }

  .advanced-toggle {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    background: none;
    border: 1px dashed color-mix(in srgb, var(--border) 60%, transparent);
    border-radius: var(--radius-sm);
    padding: 0.625rem 1rem;
    color: var(--fg-dim);
    font-size: 0.8125rem;
    font-weight: 700;
    text-transform: uppercase;
    letter-spacing: 1px;
    cursor: pointer;
    width: 100%;
    transition: all 0.2s ease;
    margin-top: 1rem;
  }
  .advanced-toggle:hover {
    border-color: var(--accent);
    color: var(--accent);

  }
  .advanced-arrow { font-size: 0.65rem; }

  .advanced-section {
    margin-top: 1rem;
    padding: 1rem 1.1rem;
    border: 1px solid rgba(141, 154, 178, 0.18);
    border-radius: var(--radius-lg);
    background: rgba(255, 255, 255, 0.5);
  }

  .validation-error {
    padding: 0.75rem 1.5rem;
    font-size: 0.8125rem;
    color: var(--error, #e55);
    border-top: 1px dashed color-mix(in srgb, var(--error, #e55) 30%, transparent);
    background: color-mix(in srgb, var(--error, #e55) 5%, transparent);
    font-weight: bold;
    text-transform: uppercase;
    letter-spacing: 1px;
  }

  .validation-warning {
    padding: 0.75rem 1.5rem;
    font-size: 0.8125rem;
    color: var(--warning, #ca0);
    border-top: 1px dashed color-mix(in srgb, var(--warning, #ca0) 30%, transparent);
    background: color-mix(in srgb, var(--warning, #ca0) 5%, transparent);
    font-weight: bold;
    text-transform: uppercase;
    letter-spacing: 1px;
  }

  .install-message {
    padding: 1rem 1.5rem;
    font-size: 0.875rem;
    color: var(--accent);
    border-top: 1px dashed color-mix(in srgb, var(--border) 50%, transparent);
    background: color-mix(in srgb, var(--accent) 5%, transparent);
    font-weight: bold;
    text-transform: uppercase;
    letter-spacing: 1px;

  }

  .wizard-footer {
    position: sticky;
    bottom: 0;
    left: 0;
    right: 0;
    background: linear-gradient(180deg, rgba(250, 252, 255, 0.82), rgba(255, 255, 255, 0.96));
    border-top: 1px solid rgba(141, 154, 178, 0.16);
    padding: 1rem 0 0 0;
    margin-top: 24px;
    display: flex;
    align-items: center;
    justify-content: space-between;
    backdrop-filter: blur(14px);
  }

  .footer-spacer { flex: 1; }

  .primary-btn {
    background: linear-gradient(135deg, var(--cyan-600), var(--cyan-500));
    color: white;
    border: 1px solid rgba(8, 145, 178, 0.28);
    border-radius: 999px;
    padding: 0.72rem 1.35rem;
    font-size: 0.82rem;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.2s ease;
    font-family: var(--font-sans);
    letter-spacing: 0.02em;
    box-shadow: 0 14px 28px rgba(8, 145, 178, 0.18);
  }

  .primary-btn.install-btn {
    background: linear-gradient(135deg, var(--emerald-600), var(--emerald-500));
    border-color: rgba(5, 150, 105, 0.28);
    box-shadow: 0 14px 28px rgba(5, 150, 105, 0.18);
  }

  .primary-btn:hover:not(:disabled) {
    transform: translateY(-1px);
    filter: brightness(1.04);
  }

  .primary-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .secondary-btn {
    background: rgba(255, 255, 255, 0.88);
    color: var(--slate-700);
    border: 1px solid rgba(141, 154, 178, 0.2);
    border-radius: 999px;
    padding: 0.72rem 1.2rem;
    font-size: 0.78rem;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.2s ease;
    font-family: var(--font-sans);
    letter-spacing: 0.02em;
  }

  .secondary-btn:hover:not(:disabled) {
    border-color: rgba(34, 211, 238, 0.28);
    color: var(--cyan-700);
    box-shadow: var(--focus-ring);
  }

  .secondary-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  @media (max-width: 760px) {
    .wizard-footer {
      flex-direction: column-reverse;
      gap: 0.75rem;
      align-items: stretch;
    }

    .footer-spacer {
      display: none;
    }

    .primary-btn,
    .secondary-btn {
      width: 100%;
    }
  }
</style>
