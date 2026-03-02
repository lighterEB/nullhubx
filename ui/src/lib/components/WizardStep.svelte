<script lang="ts">
  let { step, value = '', onchange } = $props<{
    step: { id: string; title: string; description?: string; type: string; options?: Array<{value: string; label: string; description?: string}>; required?: boolean };
    value: string;
    onchange: (value: string) => void;
  }>();
</script>

<div class="wizard-step">
  <label class="step-title">{step.title}</label>
  {#if step.description}
    <p class="step-description">{step.description}</p>
  {/if}

  {#if step.type === 'select'}
    <div class="options">
      {#each step.options || [] as option}
        <button
          class="option-btn"
          class:selected={value === option.value}
          onclick={() => onchange(option.value)}
        >
          <strong>{option.label}</strong>
          {#if option.description}<span>{option.description}</span>{/if}
        </button>
      {/each}
    </div>
  {:else if step.type === 'multi_select'}
    <div class="options">
      {#each step.options || [] as option}
        {@const selected = value.split(',').includes(option.value)}
        <button
          class="option-btn"
          class:selected
          onclick={() => {
            const vals = value ? value.split(',').filter(Boolean) : [];
            if (selected) onchange(vals.filter(v => v !== option.value).join(','));
            else onchange([...vals, option.value].join(','));
          }}
        >
          <strong>{option.label}</strong>
          {#if option.description}<span>{option.description}</span>{/if}
        </button>
      {/each}
    </div>
  {:else if step.type === 'secret'}
    <input type="password" {value} oninput={(e) => onchange(e.currentTarget.value)} placeholder="Enter secret..." />
  {:else if step.type === 'number'}
    <input type="number" {value} oninput={(e) => onchange(e.currentTarget.value)} />
  {:else if step.type === 'toggle'}
    <label class="toggle">
      <input type="checkbox" checked={value === 'true'} onchange={(e) => onchange(String(e.currentTarget.checked))} />
      <span class="toggle-slider"></span>
    </label>
  {:else}
    <input type="text" {value} oninput={(e) => onchange(e.currentTarget.value)} placeholder="Enter value..." />
  {/if}
</div>

<style>
  .wizard-step {
    margin-bottom: 1.5rem;
  }

  .step-title {
    display: block;
    font-size: 0.9rem;
    font-weight: 600;
    color: var(--text-primary);
    margin-bottom: 0.25rem;
  }

  .step-description {
    font-size: 0.8rem;
    color: var(--text-secondary);
    margin-bottom: 0.75rem;
  }

  .options {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
  }

  .option-btn {
    display: flex;
    flex-direction: column;
    gap: 0.2rem;
    text-align: left;
    background: var(--bg-tertiary);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    padding: 0.75rem 1rem;
    color: var(--text-primary);
    cursor: pointer;
    transition: border-color 0.15s, background 0.15s;
  }

  .option-btn:hover {
    background: var(--bg-hover);
  }

  .option-btn.selected {
    border-color: var(--accent);
    background: var(--bg-hover);
  }

  .option-btn strong {
    font-size: 0.875rem;
  }

  .option-btn span {
    font-size: 0.75rem;
    color: var(--text-secondary);
  }

  input[type='text'],
  input[type='password'],
  input[type='number'] {
    width: 100%;
    background: var(--bg-tertiary);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    padding: 0.6rem 0.75rem;
    color: var(--text-primary);
    font-size: 0.875rem;
    font-family: var(--font-sans);
    outline: none;
    transition: border-color 0.15s;
  }

  input[type='text']:focus,
  input[type='password']:focus,
  input[type='number']:focus {
    border-color: var(--accent);
  }

  .toggle {
    position: relative;
    display: inline-block;
    width: 44px;
    height: 24px;
    cursor: pointer;
  }

  .toggle input {
    opacity: 0;
    width: 0;
    height: 0;
  }

  .toggle-slider {
    position: absolute;
    inset: 0;
    background: var(--bg-tertiary);
    border: 1px solid var(--border);
    border-radius: 12px;
    transition: background 0.2s;
  }

  .toggle-slider::before {
    content: '';
    position: absolute;
    width: 18px;
    height: 18px;
    left: 2px;
    top: 2px;
    background: var(--text-secondary);
    border-radius: 50%;
    transition: transform 0.2s, background 0.2s;
  }

  .toggle input:checked + .toggle-slider {
    background: var(--accent);
    border-color: var(--accent);
  }

  .toggle input:checked + .toggle-slider::before {
    transform: translateX(20px);
    background: #fff;
  }
</style>
