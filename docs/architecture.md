# Motley Crew Architecture

## Overview

Motley Crew is an AI workforce manager. One human (or team) manages multiple AI projects through a hierarchy of specialized agents, coordinated through Discord and powered by [OpenClaw](https://github.com/openclaw/openclaw).

The system is designed to be **forkable** — someone else should be able to point it at their machine, Discord server, and project repos and have a working AI team. All project-specific config lives outside the repo.

## Agent Hierarchy

```
Human(s)
└── Chief of Staff (permanent, Opus)
    ├── Project Lead: ToolGuard (permanent, Sonnet)
    │   └── Workers (ephemeral, from templates)
    ├── Project Lead: Polly (permanent, Sonnet)
    │   └── Workers (ephemeral)
    └── ... more projects
```

### Agent Types

| Type | Persistent? | Model | Purpose |
|------|------------|-------|---------|
| Chief of Staff | Yes | Opus | Orchestration, delegation, priorities, human interface |
| Project Lead | Yes (per project) | Sonnet | Knows codebase, architecture, issues. Breaks down tasks, manages workers |
| Worker | No (per task) | Template-defined | Implementation, review, QA, docs. Created per task, destroyed after |

### Chief of Staff (CoS)

The CoS is the primary human interface. It:

- Receives high-level requests ("implement issue #42", "status update")
- Delegates to the appropriate project lead
- Tracks progress across all projects
- Posts roll-ups and alerts to `#status`
- Can be bypassed — humans can talk directly to project leads via their Discord channels

**Model:** Opus (highest capability for orchestration and judgment)

### Project Leads

Each project gets a permanent lead agent that:

- Has deep knowledge of its codebase (persistent memory, permanent checkout)
- Breaks down tasks into worker-sized pieces
- Selects appropriate worker templates per task
- Reviews worker output before merging
- Reports status to CoS and to its Discord channel

**Model:** Sonnet (good balance of capability and cost for sustained work)

### Workers

Ephemeral agents spawned from [templates](../templates/). They:

- Get a fresh code checkout on creation
- Execute a single task (implement, review, test, document)
- Report results back to the lead that spawned them
- Are destroyed after completion (workspace cleaned up)

**Model:** Defined by template (Opus, Sonnet, Haiku, Grok, MiniMax, etc.)

**Worker count:** 3–5 per lead, tunable per project. Not hardcoded.

## Code Isolation

Each agent gets its own code checkout (**Option C** — agent-owned directories):

- **Project leads** have a permanent checkout in their workspace
- **Workers** get a fresh clone on creation, cleaned up on completion
- **No shared working directories** — collisions are structurally impossible
- **Branch naming:** `<agent-id>/<feature>` (e.g., `forge-dev/issue-42`)
- **Disk estimate:** ~50MB per checkout × 10 agents = ~500MB (trivial)

This means no coordination is needed for concurrent work. Two workers on different tasks never touch the same files.

## Identity & Attribution

GitHub accounts are shared at the **template role level**, not per-worker:

| Role | Git Identity | Used By |
|------|-------------|---------|
| `forge-dev` | All dev templates | Implementation commits, PRs |
| `forge-review` | All reviewer templates | Review comments, approvals |
| `forge-qa` | All QA templates | Test commits |
| `forge-docs` | All docs templates | Documentation commits |

Commit messages include provenance:

```
feat: implement vault key rotation (#42)

Template: dev-sonnet | Model: claude-sonnet-4 | Task: impl-42
```

Workers don't need Discord accounts — they report back to the lead via `sessions_send`, and the lead posts to Discord.

## Discord Layout

```
Discord Server: "Motley Crew"
├── GENERAL
│   ├── #command          (CoS — primary human interface)
│   └── #status           (CoS posts roll-ups, alerts)
├── PROJECTS
│   ├── #toolguard        (ToolGuard lead)
│   ├── #polly            (Polly lead)
│   └── ...               (created per project onboarding)
└── ADMIN
    ├── #logs             (system events, worker lifecycle)
    └── #costs            (spend tracking — optional)
```

Each project lead gets its own channel. Humans can talk to the CoS in `#command` or go directly to a lead in its project channel.

## Communication Patterns

```
┌─────────┐  Discord #command   ┌─────┐  sessions_send   ┌──────┐
│  Human  │◄───────────────────►│ CoS │◄────────────────►│ Lead │
└─────────┘                     └─────┘                   └──────┘
     │                                                       │
     │  Discord #project                                     │ sessions_spawn
     └──────────────────────────────────►│                   ▼
                                         │              ┌────────┐
                                         └─────────────►│ Worker │
                                                        └────────┘
```

| From | To | Mechanism |
|------|-----|-----------|
| Human → CoS | Discord `#command` |
| Human → Lead | Discord project channel (bypass CoS) |
| CoS → Lead | `sessions_send` |
| Lead → Worker | `sessions_spawn` (ephemeral) |
| Worker → Lead | Report back on completion (built into spawn) |
| Lead → CoS | Status updates, completion reports |
| CoS → Human | Summaries in `#command` or `#status` |

## Worker Lifecycle

```
1. Lead decides a task needs a worker
2. Lead selects template (dev-sonnet, reviewer-opus, etc.)
         │
         ▼
3. System creates ephemeral agent workspace
4. Fresh code checkout into workspace
5. Template SOUL.md + task prompt injected
         │
         ▼
6. Worker executes task
7. Worker reports results to lead
         │
         ▼
8. Workspace cleaned up (code checkout deleted)
```

Workers are like serverless functions for AI — spin up, do work, report, clean up. No persistent state.

## Host Requirements

The host machine runs:

- **OpenClaw Gateway** (multi-agent mode)
- **Discord Bot** (connected to the Discord server)
- Agent workspaces (one directory per permanent agent + ephemeral worker dirs)

Recommended: Mac Mini or VPS with ≥8GB RAM, ≥50GB disk. Needs to run multiple concurrent OpenClaw sessions.

## Multi-Human Support

The architecture naturally supports teams:

- Discord roles control who can talk to CoS and leads
- CoS tracks which human made which request
- Project channels provide shared visibility (natural standup)

Not optimized for v1, but no architectural changes needed to support it later.

## Replicability

To use Motley Crew for your own projects:

1. **Fork this repo**
2. **Set up a Discord server** with the channel layout above
3. **Create a Discord bot** and connect it to OpenClaw
4. **Configure your host machine** — install OpenClaw, set up agent workspaces
5. **Onboard projects** — run the onboarding script with your repo URLs
6. **Configure templates** — adjust models, add custom templates as needed

All project-specific config (repos, API keys, Discord channel IDs) lives in environment/config files, not in the repo.
