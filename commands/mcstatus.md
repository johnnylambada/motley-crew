# /mcstatus — Open Issues Status Email

When the user sends `/mcstatus`, execute this workflow.

## Scoping

1. Read `IDENTITY.md` to determine your role.
2. **If Project Lead:** Read your project config from `~/.config/motley-crew/projects/<project>.json` to get the repo URL.
3. **If Chief of Staff:** Iterate over all `~/.config/motley-crew/projects/*.json` files for a cross-project view.

## Steps

### 1. Fetch open issues

For each repo in scope:
```bash
TOKEN=$(cat ~/.config/motley-crew/github-token)
REPO="<owner>/<repo>"  # from project config
curl -s -H "Authorization: token $TOKEN" -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/$REPO/issues?state=open&per_page=100"
```
Filter out pull requests (items with `pull_request` key).

### 2. Build HTML email

Split issues into three sections in this order:

**Section 1 — 🚦 Ready for AI** (green background `#d4edda`):
- Issues with NO `human` or `botblocker` labels
- These can be worked on immediately without human input
- Sort by milestone priority then issue number

**Section 2 — 🙋 Needs Human** (yellow background `#fff3cd`):
- Issues labeled `human`
- Humans must act before AI can proceed

**Section 3 — 🚫 Bot Blockers** (red background `#ffcccc`):
- Issues labeled `botblocker`
- Blocked on external dependencies

Each section has its own `<h3>` header and table. Skip empty sections.

- **HTML table columns:** `#`, `Title` (linked), `Labels`, `Milestone`, `Status/Deps`
- If CoS (multi-project): group by project with `<h2>` headers, then sections within each project
- **Summary line** with counts: ready for AI, needs human, bot blockers
- **All commentary goes BELOW the sections** — recently closed, action items, critical path notes

### 3. Send via email

Use the ToolGuard shim to send:
```bash
echo '<MCP JSON>' | ~/.toolguard/bin/toolguard shim --config ~/.toolguard/toolguard.yaml 2>/dev/null
```
- **To:** john.lombardo@gmail.com
- **Subject:** `Motley Crew — <Project> Issues (<date>)` (or `All Projects` for CoS)
- **body_format:** html
- **user_google_email:** atari400clawbot@gmail.com

If the shim is not available (ToolGuard not installed), fall back to posting the summary directly in the Discord channel as a message.

### 4. Confirm

Tell the user the email was sent (or that you posted the summary to Discord).

## Notes
- Parse dependency info from issue bodies when available
- Color coding: ready `#d4edda` green, `human` `#fff3cd` yellow, `botblocker` `#ffcccc` red
- Include recently closed issues (last 10) below the sections
- An issue can appear in multiple sections if it has multiple relevant labels — use the most restrictive (botblocker > human > ready)
