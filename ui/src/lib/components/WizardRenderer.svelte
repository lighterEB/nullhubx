<script lang="ts">
  import WizardStep from "./WizardStep.svelte";
  import ProviderList from "./ProviderList.svelte";
  import { api } from "$lib/api/client";

  let {
    component = "",
    steps = [],
    onComplete,
  } = $props<{
    component: string;
    steps: any[];
    onComplete?: () => void;
  }>();

  let answers = $state<Record<string, string>>({});
  let instanceName = $state("");
  let currentStep = $state(0);
  let installing = $state(false);
  let installMessage = $state("");
  let versions = $state<any[]>([]);
  let selectedVersion = $state("latest");
  const instanceNameId = "wizard-instance-name";

  // Auto-generate instance name on mount
  $effect(() => {
    if (component && !instanceName) {
      api
        .getInstances()
        .then((data: any) => {
          const existing = data?.instances?.[component] || {};
          const names = Object.keys(existing);
          let id = 1;
          while (names.includes(`instance-${id}`)) id++;
          instanceName = `instance-${id}`;
        })
        .catch(() => {
          instanceName = "instance-1";
        });
    }
  });

  // Fetch available versions
  $effect(() => {
    if (component) {
      api
        .getVersions(component)
        .then((data: any) => {
          versions = Array.isArray(data) ? data : [];
          if (versions.length > 0) {
            const rec = versions.find((v: any) => v.recommended);
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
        // Auto-select recommended option
        const rec = step.options.find((o: any) => o.recommended);
        if (rec) answers[step.id] = rec.value;
      }
    }
  });

  // Initialize default provider entry when provider step exists
  $effect(() => {
    if (!("_providers" in answers)) {
      const providerStep = steps.find((s) => s.id === "provider");
      if (providerStep) {
        const rec = providerStep.options?.find((o: any) => o.recommended);
        const defaultProvider =
          rec?.value || providerStep.options?.[0]?.value || "";
        answers["_providers"] = JSON.stringify([
          { provider: defaultProvider, api_key: "", model: "" },
        ]);
      }
    }
  });

  function isStepVisible(step: any): boolean {
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

  let visibleSteps = $derived(steps.filter(isStepVisible));

  async function submit() {
    installing = true;
    installMessage = "Installing...";
    try {
      const { _providers, ...rest } = answers;
      const payload: any = {
        instance_name: instanceName,
        version: selectedVersion,
        ...rest,
      };
      if (_providers) {
        try {
          const parsed = JSON.parse(_providers);
          payload.providers = parsed;
          // Flatten primary provider fields for component --from-json
          if (parsed.length > 0) {
            if (!payload.api_key && parsed[0].api_key)
              payload.api_key = parsed[0].api_key;
            if (!payload.model && parsed[0].model)
              payload.model = parsed[0].model;
          }
        } catch {}
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
  </div>

  <div class="wizard-body">
    <div class="name-step">
      <label for={instanceNameId}>Instance Name</label>
      <input
        id={instanceNameId}
        type="text"
        bind:value={instanceName}
        placeholder="instance-1"
      />
    </div>

    {#if versions.length > 1}
      <WizardStep
        step={{
          id: "_version",
          title: "Version",
          description: "Select the version to install",
          type: "select",
          options: versions,
        }}
        value={selectedVersion}
        onchange={(v) => (selectedVersion = v)}
      />
    {/if}

    {#each visibleSteps as step}
      {#if step.id === "provider"}
        <ProviderList
          providers={step.options || []}
          value={answers["_providers"] || "[]"}
          onchange={(v) => (answers["_providers"] = v)}
          {component}
        />
      {:else if step.id === "api_key" || step.id === "model"}
        <!-- Handled by ProviderList above -->
      {:else}
        <WizardStep
          {step}
          value={answers[step.id] || ""}
          onchange={(v) => (answers[step.id] = v)}
        />
      {/if}
    {/each}
  </div>

  {#if installMessage}
    <div class="install-message">{installMessage}</div>
  {/if}

  <div class="wizard-footer">
    <button
      class="primary-btn"
      onclick={submit}
      disabled={installing || !instanceName}
    >
      {installing ? "Installing..." : "Install"}
    </button>
  </div>
</div>

<style>
  .wizard {
    background: var(--bg-surface);
    border: 1px solid var(--border);
    border-radius: 4px;
    overflow: hidden;
    backdrop-filter: blur(4px);
    box-shadow: 0 0 10px rgba(0, 0, 0, 0.5);
  }

  .wizard-header {
    padding: 1.5rem;
    border-bottom: 1px solid color-mix(in srgb, var(--border) 50%, transparent);
  }

  .wizard-header h2 {
    font-size: 1.25rem;
    font-weight: 700;
    color: var(--accent);
    text-transform: uppercase;
    letter-spacing: 2px;
    text-shadow: var(--text-glow);
  }

  .wizard-body {
    padding: 1.75rem 1.5rem;
  }

  .name-step {
    margin-bottom: 2rem;
  }

  .name-step label {
    display: block;
    font-size: 0.8125rem;
    font-weight: 700;
    color: var(--fg-dim);
    margin-bottom: 0.5rem;
    text-transform: uppercase;
    letter-spacing: 1px;
  }

  .name-step input {
    width: 100%;
    background: var(--bg-surface);
    border: 1px solid var(--border);
    border-radius: 2px;
    padding: 0.625rem 0.875rem;
    color: var(--fg);
    font-size: 0.875rem;
    font-family: var(--font-mono);
    outline: none;
    transition: all 0.2s ease;
    box-shadow: inset 0 2px 4px rgba(0, 0, 0, 0.2);
  }

  .name-step input:focus {
    border-color: var(--accent);
    box-shadow: 0 0 8px var(--border-glow);
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
    text-shadow: var(--text-glow);
  }

  .wizard-footer {
    padding: 1.25rem 1.5rem;
    border-top: 1px solid color-mix(in srgb, var(--border) 50%, transparent);
    display: flex;
    justify-content: flex-end;
    background: color-mix(in srgb, var(--bg-surface) 50%, transparent);
  }

  .primary-btn {
    background: color-mix(in srgb, var(--accent) 20%, transparent);
    color: var(--accent);
    border: 1px solid var(--accent);
    border-radius: 2px;
    padding: 0.75rem 2rem;
    font-size: 0.875rem;
    font-weight: 700;
    cursor: pointer;
    transition: all 0.2s ease;
    text-transform: uppercase;
    letter-spacing: 2px;
    text-shadow: var(--text-glow);
    box-shadow: inset 0 0 10px
      color-mix(in srgb, var(--accent) 30%, transparent);
  }

  .primary-btn:hover:not(:disabled) {
    background: var(--bg-hover);
    border-color: var(--accent);
    box-shadow:
      0 0 15px var(--border-glow),
      inset 0 0 15px color-mix(in srgb, var(--accent) 40%, transparent);
    text-shadow: 0 0 10px var(--accent);
  }

  .primary-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
    box-shadow: none;
    text-shadow: none;
  }
</style>
