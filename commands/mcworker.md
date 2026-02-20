# /mcworker — Spawn a Worker

When the user sends `/mcworker <template>`, spawn a new permanent worker for this project.

## Arguments
- `<template>` — Worker template name (required). e.g., `dev-sonnet`, `reviewer-opus`, `qa-sonnet`
- Examples: `/mcworker dev-sonnet` or `/mcworker reviewer-opus`

## Scoping

1. Read `IDENTITY.md` to determine your project.
2. Read project config from `~/.config/motley-crew/projects/<project>.json` to get the repo URL.
3. **This command only works for Project Leads**, not the CoS.

## Workflow

### Step 1: Validate template
Check that the template exists:
```bash
ls ~/motley-crew/templates/<template>.md
```
If not found, list available templates and ask the user to pick one.

### Step 2: Run spawn script
```bash
~/motley-crew/scripts/spawn-worker.sh <template> <repo_url>
```

This creates:
- Worker with random human name
- Personalized SOUL.md from template
- Fresh code checkout with git identity configured
- IDENTITY.md, AGENTS.md, initial memory

### Step 3: Report
Tell the user:
- Worker name (e.g., "Alice Sonnet Developer")
- Workspace path
- Template used
- That the worker is ready for task assignment

## Available Templates

| Template | Model | Role |
|----------|-------|------|
| `dev-opus` | Opus | Senior developer (complex tasks) |
| `dev-sonnet` | Sonnet | Developer (standard tasks) |
| `dev-haiku` | Haiku | Developer (simple/fast tasks) |
| `dev-grok` | Grok | Developer (evaluation) |
| `dev-minimax` | MiniMax | Developer (evaluation) |
| `reviewer-opus` | Opus | Code reviewer |
| `qa-sonnet` | Sonnet | QA / test writer |
| `docs-sonnet` | Sonnet | Documentation writer |

## Notes
- Workers are permanent — they persist until the project is removed
- They cost nothing when idle (no running process)
- Each worker gets its own code checkout (no conflicts)
