# Model Evaluation — Software Lead Role

Models tested as the `toolguard-lead` agent (Tom). Updated as we learn more.

| Model | Worked as Lead? | Notes |
|-------|----------------|-------|
| `anthropic/claude-opus-4-6` | ✅ Yes | Gold standard. Self-driving, reliable tool use, handles complex multi-step workflows. Expensive. |
| `anthropic/claude-sonnet-4-6` | ✅ Yes | Good balance. Capable lead, reliable tool chains. Current default for Tom. |
| `openrouter/google/gemini-2.5-flash` | ❌ No | Stops between steps waiting for human confirmation. Timed out on `/mcstatus` (typing TTL 2min). Could not send email autonomously. Not agentic enough for lead role. |
| `minimax/minimax-01` | ❌ No | Used as code reviewer only — not tested as full lead. Did not work well enough to continue. |

## Summary

- **Use Sonnet or Opus for leads** — anything requiring autonomous multi-step tool execution
- **Flash/cheap models are not agentic enough** — they stall, wait for confirmation, timeout on complex tool chains
- **Workers** (implementation tasks with explicit instructions) may work on cheaper models — not yet tested
