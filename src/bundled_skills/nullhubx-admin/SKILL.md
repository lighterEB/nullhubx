---
name: nullhubx-admin
version: 0.1.0
description: Teach managed nullclaw agents to discover NullHubX routes first and then use nullhubx api for instance, provider, component, and orchestration tasks.
always: true
requires_bins:
  - nullhubx
---

# NullHubX Admin

Use this skill whenever the task involves `nullhubx`, NullHubX-managed instances, providers, components, or orchestration routes.

Workflow:

1. Do not ask the user for the exact `nullhubx` command or endpoint if `nullhubx` can discover it.
2. Start with `nullhubx routes --json` to discover the current route contract.
3. Use `nullhubx api <METHOD> <PATH>` for the actual operation.
4. Prefer a read operation first unless the user already gave a precise destructive intent.
5. After a mutation, verify with a follow-up `GET`.

Rules:

- Prefer `nullhubx api` over deleting files directly when NullHubX owns the cleanup.
- If a route or payload is unclear, inspect `nullhubx routes --json` again instead of guessing or asking the user for syntax.
- Use `--pretty` for user-facing inspection output.
- Use `--body` or `--body-file` for JSON request bodies.
- If path segments come from arbitrary ids or names, percent-encode them before building the request path.
- Do not claim a route exists until it is confirmed by `nullhubx routes --json` or a successful request.

Common patterns:

```bash
nullhubx routes --json
nullhubx api GET /api/meta/routes --pretty
nullhubx api GET /api/components --pretty
nullhubx api GET /api/instances --pretty
nullhubx api GET /api/instances/nullclaw/instance-1 --pretty
nullhubx api GET /api/instances/nullclaw/instance-1/skills --pretty
nullhubx api DELETE /api/instances/nullclaw/instance-2
nullhubx api POST /api/providers/2/validate
```

Shorthand paths are allowed:

```bash
nullhubx api GET instances
nullhubx api POST providers/2/validate
```
