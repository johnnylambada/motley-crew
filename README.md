# Motley Crew 🎸

A replicable multi-agent AI team framework. One human (or team) manages multiple AI projects through a hierarchy of specialized agents, all coordinated through Discord.

## Concept

Motley Crew gives you a **Chief of Staff** (CoS) AI that orchestrates **Project Leads** and **ephemeral Workers** across your repos. Think of it as an AI workforce manager:

```
Human(s)
└── Chief of Staff (permanent, Opus)
    ├── Project Lead: ProjectA (permanent, Sonnet)
    │   └── Workers (ephemeral, from templates)
    ├── Project Lead: ProjectB (permanent, Sonnet)
    │   └── Workers (ephemeral)
    └── ...
```

Workers are spawned from **templates** — reusable profiles that define model, tools, and personality. When a task is done, the worker is destroyed and its workspace cleaned up.

## Quick Start

> 🚧 Under construction — see [docs/architecture.md](docs/architecture.md) for the full design.

1. Fork this repo
2. Set up a Discord server with the [channel layout](docs/architecture.md#discord-layout)
3. Configure OpenClaw on your host machine
4. Onboard your first project

## Documentation

- **[Architecture](docs/architecture.md)** — Full system design, agent types, communication patterns
- **[Templates](templates/)** — Worker templates (dev, reviewer, QA, docs)

## Requirements

- [OpenClaw](https://github.com/openclaw/openclaw) — AI agent framework
- A Discord server with bot access
- A machine to host the agents (Mac Mini, VPS, etc.)

## License

MIT
