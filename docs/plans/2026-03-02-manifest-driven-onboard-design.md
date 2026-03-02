# Manifest-Driven Onboard Design

## Problem

NullHub and each component (nullclaw, nullboiler, nulltickets) both need to configure instances. Today nullclaw has a rich CLI onboard (`nullclaw onboard --interactive`) with 29 providers, live model fetching, channel setup, and workspace scaffolding. NullHub has a separate, static manifest in `manifests/nullclaw.json` with a simplified wizard. These two sources of truth inevitably diverge.

## Solution

Components own their wizard. NullHub asks the component for its manifest and delegates config generation back to it.

### CLI Protocol

Every component implements three subcommands:

```bash
# Export manifest (wizard steps, metadata, launch/health/ports)
component --export-manifest
# stdout: Manifest JSON

# List dynamic options (optional, only nullclaw uses this for models)
component --list-models --provider openrouter --api-key sk-...
# stdout: ["anthropic/claude-sonnet-4.6", "openai/gpt-5.2", ...]

# Accept wizard answers, generate config, scaffold workspace
component --from-json '{"provider":"openrouter","api_key":"sk-...","model":"..."}'
# Generates config files, prints {"status":"ok"} to stdout
```

### Install Flow

```
User opens NullHub UI
  → Sees list of known components (from registry)
  → Selects "Install NullClaw"
  → NullHub downloads the binary
  → Runs: nullclaw --export-manifest → gets wizard steps
  → Renders wizard in UI (provider → key → model → memory → ...)
  → For model step: runs nullclaw --list-models → gets live model list
  → User completes wizard, submits answers
  → Runs: nullclaw --from-json '{"answers":{...}}' → component generates its config
  → NullHub registers instance in state.json
  → Starts: nullclaw gateway
```

### Manifest Schema

What `--export-manifest` returns:

```json
{
  "schema_version": 1,
  "name": "nullclaw",
  "display_name": "NullClaw",
  "description": "Autonomous AI agent runtime",
  "icon": "agent",
  "repo": "nullclaw/nullclaw",
  "platforms": {
    "aarch64-macos": { "asset": "nullclaw-macos-aarch64", "binary": "nullclaw" },
    "x86_64-linux": { "asset": "nullclaw-linux-x86_64", "binary": "nullclaw" }
  },
  "build_from_source": {
    "zig_version": "0.15.2",
    "command": "zig build -Doptimize=ReleaseSmall",
    "output": "zig-out/bin/nullclaw"
  },
  "launch": { "command": "gateway", "args": [] },
  "health": { "endpoint": "/health", "port_from_config": "gateway.port" },
  "ports": [
    { "name": "gateway", "config_key": "gateway.port", "default": 3000, "protocol": "http" }
  ],
  "wizard": {
    "steps": [
      {
        "id": "provider",
        "title": "AI Provider",
        "type": "select",
        "required": true,
        "options": [
          { "value": "openrouter", "label": "OpenRouter (recommended)", "description": "Multi-provider gateway" },
          { "value": "anthropic", "label": "Anthropic (Claude direct)" }
        ]
      },
      {
        "id": "api_key",
        "title": "API Key",
        "type": "secret",
        "required": true,
        "condition": { "step": "provider", "not_equals": "ollama" }
      },
      {
        "id": "model",
        "title": "Model",
        "type": "dynamic_select",
        "required": true,
        "dynamic_source": { "command": "--list-models", "depends_on": ["provider", "api_key"] }
      }
    ]
  },
  "depends_on": [],
  "connects_to": [
    { "component": "nullboiler", "role": "worker", "description": "Registers as a worker" }
  ]
}
```

Key changes from current schema:
- Removed `config.path` — component knows where its config is
- Removed `ui_modules` — not used yet
- Removed `migrations` — not used yet
- Removed `writes_to` from wizard steps — NullHub no longer writes config
- Added `dynamic_select` step type — for live data like models
- Added `dynamic_source` — tells NullHub how to fetch options at runtime

### Wizard Step Types

| Type | UI | Data |
|------|-----|------|
| `select` | Dropdown/radio | Single value from options |
| `multi_select` | Checkboxes | Array of values from options |
| `secret` | Password input | String (masked) |
| `text` | Text input | String |
| `number` | Number input | Integer |
| `toggle` | Switch | Boolean |
| `dynamic_select` | Dropdown loaded at runtime | Single value, options fetched via CLI |

### Conditional Steps

Steps can have a `condition` that controls visibility:

```json
{
  "condition": {
    "step": "provider",
    "equals": "openrouter"
  }
}
```

Supported operators: `equals`, `not_equals`, `contains` (for multi_select values).

## Component Changes

### nullclaw

Has full onboard already. Changes:

**`--export-manifest`**: Serialize `known_providers`, memory backends, tunnel options, autonomy levels, channel list into Manifest JSON. Generated from the same data structures that `runWizard()` uses.

**`--list-models`**: Already has `fetchModels()`. Wrap it to output JSON array to stdout.

**`--from-json`**: Extended `runQuickSetup()` that accepts all fields including channels. Reads JSON, fills Config, calls `cfg.save()` and `scaffoldWorkspace()`.

Wizard steps (8):
1. provider (select, 29 options)
2. api_key (secret, conditional on provider != ollama)
3. model (dynamic_select via --list-models)
4. memory (select: sqlite, markdown, memory, none, etc.)
5. tunnel (select: none, cloudflare, ngrok, tailscale)
6. autonomy (select: supervised, autonomous, fully_autonomous)
7. channels (multi_select: telegram, discord, slack, etc.)
8. gateway_port (number, default 3000)

Channel-specific config (tokens, URLs) collected as sub-steps conditional on channel selection.

### nullboiler

No onboard currently. Add:

**`--export-manifest`**: Static JSON. Simple wizard.

**`--from-json`**: Write `config.json` from answers.

Wizard steps (3):
1. port (number, default 8080)
2. api_token (secret, optional)
3. db_path (text, default "nullboiler.db")

### nulltickets

No onboard currently. Add:

**`--export-manifest`**: Static JSON. Minimal wizard.

**`--from-json`**: Write `config.json` from answers. Currently has no config file — add one.

Wizard steps (2):
1. port (number, default 7700)
2. db_path (text, default "nulltickets.db")

## NullHub Changes

### Remove
- `manifests/` directory — no longer needed
- `src/wizard/config_writer.zig` — component generates config
- `src/wizard/engine.zig` — validation on component side
- Config generation code in `orchestrator.zig`

### Modify
- `Manifest` schema (`src/core/manifest.zig`): remove `config`, `ui_modules`, `migrations`, `writes_to`; add `dynamic_select` step type
- `orchestrator.install()`: remove config generation step, add `--from-json` invocation
- `wizard.zig` GET handler: run `component --export-manifest` instead of reading `manifests/`
- `wizard.zig` POST handler: run `component --from-json` instead of config_writer

### Add
- Helper to run component binary and capture stdout (`src/core/component_cli.zig`)
- New API endpoint: `GET /api/wizard/{component}/models?provider=X&api_key=Y` — proxies to `--list-models`

## Git Strategy

- **nullclaw**: feature branch from main, PR
- **nullboiler**: feature branch from main, PR
- **nulltickets**: feature branch from main, PR
- **nullhub**: direct to main (no prod)
