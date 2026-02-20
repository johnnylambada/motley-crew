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

- **Sort order:** `botblocker`-labeled first (red background), then `human`-labeled (yellow background), then rest. Within groups, sort by milestone priority then issue number.
- **HTML table columns:** `#`, `Title` (linked), `Labels`, `Milestone`, `Status/Deps`
- If CoS (multi-project): group issues by project with `<h3>` headers
- **Summary line** with counts: open, botblockers, human action needed
- **All commentary goes BELOW the table** — recently closed, action items, critical path notes

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
- Color coding: `botblocker` red (#ffcccc), `human` yellow (#fff3cd)
- Include recently closed issues (last 10) below the table
