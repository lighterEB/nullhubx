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
      ? "Instance name is required"
      : existingInstanceNames.includes(trimmedInstanceName)
        ? "Instance name must be unique for this component"
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
          versions = [{ value: "latest", label: "latest", recommended: true }];
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
      kind === "setup" ? "Setup" : kind === "channels" ? "Channels" : "Settings",
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

    try {
      const providers = JSON.parse(answers["_providers"] || "[]") as WizardProviderEntry[];
      if (providers.length === 0) {
        validationError = "Add at least one provider";
        return false;
      }
      const result = await api.validateProviders(component, providers);
      providerValidationResults = result.results || [];
      validationWarning = result.saved_providers_warning || "";
      return providerValidationResults.every((result) => !!result.live_ok);
    } catch (e) {
      validationError = `Validation failed: ${(e as Error).message}`;
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
      validationError = `Validation failed: ${(e as Error).message}`;
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
        return;
      }
      if (providerStep) {
        const valid = await validateProviders();
        if (!valid) return;
      }
      currentPage += 1;
      validationError = "";
      return;
    }

    if (page === "channels") {
      const valid = await validateChannels();
      if (!valid) return;
      currentPage += 1;
      validationError = "";
    }
  }

  function handleBack() {
    if (currentPage > 0) {
      currentPage -= 1;
      validationError = "";
    }
  }

  async function submit() {
    installing = true;
    installMessage = "Installing...";
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
      installMessage = result.message || "Installation complete!";
      setTimeout(() => onComplete?.(), 1500);
    } catch (e) {
      installMessage = `Error: ${(e as Error).message}`;
    } finally {
      installing = false;
    }
  }
</script>

<div class="wizard">
  <div class="wizard-header">
    <h2>Install {component}</h2>
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
        <label for={instanceNameId}>Instance Name</label>
        <p class="name-hint">Name doesn't matter, just needs to be unique</p>
        <input
          id={instanceNameId}
          type="text"
          bind:value={instanceName}
          placeholder="instance-1"
        />
        {#if instanceNameError}
          <p class="name-error">{instanceNameError}</p>
        {/if}
      </div>

      {#if versions.length > 0}
        <div class="version-select">
          <label for="version-picker">Version</label>
          <select id="version-picker" bind:value={selectedVersion}>
            {#each versions as v, i}
              <option value={v.value}>
                {v.label}{i === 0 ? " (latest, recommended)" : ""}
              </option>
            {/each}
          </select>
        </div>
      {/if}

      {#if providerStep}
        {#if validationError === "Add at least one provider"}
          <div class="provider-validation-error visible">{validationError}</div>
        {:else}
          <div class="provider-validation-error">Add at least one provider</div>
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
          Advanced
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
        Back
      </button>
    {/if}
    <div class="footer-spacer"></div>
    {#if currentPage < pageKinds.length - 1}
      <button
        class="primary-btn"
        onclick={handleNext}
        disabled={validating || !!instanceNameError}
      >
        {validating ? "Validating..." : "Next →"}
      </button>
    {:else}
      <button
        class="primary-btn install-btn"
        onclick={submit}
        disabled={installing || !!instanceNameError}
      >
        {installing ? "Installing..." : "INSTALL →"}
      </button>
    {/if}
  </div>
</div>

<style>
  .wizard {
    width: 100%;
    max-width: 800px;
    margin: 0 auto;
    padding: 32px 40px;
    background: white;
    border: 1px solid var(--slate-200);
    border-radius: 8px;
    box-shadow: var(--shadow-sm);
  }

  .wizard-header {
    padding: 0 0 24px 0;
    border-bottom: 1px solid var(--slate-200);
    margin-bottom: 24px;
  }

  .wizard-header h2 {
    font-family: var(--font-mono);
    font-size: 12px;
    font-weight: 700;
    color: var(--slate-700);
    text-transform: uppercase;
    letter-spacing: 2px;
    margin: 0 0 20px 0;
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
    background: var(--indigo-600);
    color: white;
    font-weight: 700;
  }

  .step-dot.completed .step-num {
    background: var(--indigo-50);
    color: var(--indigo-600);
    border: 1px solid var(--indigo-200);
  }

  .step-dot:not(.active):not(.completed) .step-num {
    background: white;
    color: var(--slate-400);
    border: 1px solid var(--slate-200);
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
    color: var(--indigo-600);
    font-weight: 600;
  }

  .step-dot.completed .step-label {
    color: var(--indigo-600);
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
    background: var(--indigo-200);
  }

  .step-line:not(.completed-before) {
    background: var(--slate-200);
  }

  .wizard-body { padding: 0 0 24px 0; }

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
    font-family: 'DM Sans', sans-serif;
    font-size: 12px;
    color: var(--red-600);
    background: var(--red-50);
    border: 1px solid var(--red-200);
    border-radius: 6px;
    padding: 8px 12px;
    margin-bottom: 12px;
    display: none;
    gap: 6px;
    align-items: center;
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
    padding: 1rem;
    border: 1px solid color-mix(in srgb, var(--border) 40%, transparent);
    border-radius: var(--radius-sm);
    background: color-mix(in srgb, var(--bg-surface) 50%, transparent);
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
    background: white;
    border-top: 1px solid var(--slate-200);
    padding: 16px 0 0 0;
    margin-top: 24px;
    display: flex;
    align-items: center;
    justify-content: space-between;
  }

  .footer-spacer { flex: 1; }

  .primary-btn {
    background: var(--indigo-600);
    color: white;
    border: 1px solid var(--indigo-600);
    border-radius: 8px;
    padding: 10px 28px;
    font-size: 14px;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.2s ease;
    font-family: var(--font-mono);
    letter-spacing: 1.5px;
  }

  .primary-btn.install-btn {
    background: var(--emerald-600);
    border-color: var(--emerald-600);
  }

  .primary-btn:hover:not(:disabled) {
    filter: brightness(1.1);
  }

  .primary-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  .secondary-btn {
    background: white;
    color: var(--slate-500);
    border: 1px solid var(--slate-200);
    border-radius: 8px;
    padding: 10px 24px;
    font-size: 11px;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.2s ease;
    font-family: var(--font-mono);
    letter-spacing: 1.5px;
  }

  .secondary-btn:hover:not(:disabled) {
    border-color: var(--indigo-200);
    color: var(--indigo-600);
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
