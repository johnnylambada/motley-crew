# /mcimplement — Implement, Review, and Merge

When the user sends `/mcimplement <issue_numbers>`, execute this automated workflow for each issue sequentially.

## Arguments
- `<issue_numbers>` — One or more GitHub issue numbers, space-separated (required)
- Examples: `/mcimplement 42` or `/mcimplement 42 43 44`

## Scoping

1. Read `IDENTITY.md` to determine your role and project.
2. **If Project Lead:** Use your project config from `~/.config/motley-crew/projects/<project>.json`.
3. **If Chief of Staff:** The user must specify which project, or infer from the issue number by checking all project repos.

Get the repo path and GitHub repo from the project config:
```json
{
  "repo": "git@github.com:toolguard/toolguard.git",
  "checkout_path": "~/projects/toolguard/lead/"
}
```

## GitHub token
```bash
TOKEN=$(cat ~/.config/motley-crew/github-token)
```

## Workflow

### Step 1: Fetch Issue Details
```bash
curl -s -H "Authorization: token $TOKEN" -H "Accept: application/vnd.github.v3+json" \
  "https://api.github.com/repos/<owner>/<repo>/issues/<issue_number>"
```
Extract title, body, and labels.

**📢 Post to Discord:** "🔍 Read issue #N: **<title>** — starting implementation."

### Step 2: Pick a Worker

Check for available **named workers** using `sessions_list` or `agents_list`:
- Look for a worker agent matching the project (e.g., `toolguard-worker-alice`)
- Prefer a Sonnet-class worker for implementation
- If no named worker exists, fall back to `sessions_spawn` (ephemeral sub-agent)

**📢 Post to Discord:** "🛠️ Assigning #N to **<worker-name>**..."

### Step 3: Send Task to Worker

Send the implementation task to the worker via `sessions_send`:

```
sessions_send(agentId="<worker-agent-id>", message="
Implement issue #N: <title>

Issue details:
<body>

Instructions:
1. Pull latest: cd code && git pull
2. Create branch: feature/<descriptive-name> or fix/<descriptive-name>
3. Implement the fix/feature
4. Run build and tests
5. Commit and push
6. Open a PR against main referencing issue #N
7. Report back with: branch name, PR number, files changed, test results, design decisions
")
```

**📢 Post to Discord:** "⏳ Waiting for **<worker-name>** to implement #N..."

Poll for the worker's response using `sessions_send` or check back periodically. The worker will report back when done.

When the worker responds:
- **📢 On success:** "✅ **<worker-name>** done — PR #X opened on branch `<branch>`. Starting review..."
- **📢 On failure:** "❌ **<worker-name>** failed: <reason>. Investigating..."

### Step 4: Review

**📢 Post to Discord:** "🔎 Reviewing PR #X..."

For reviews, either:
- **If an Opus-class named worker exists:** Send the review task to that worker via `sessions_send`
- **Otherwise:** Spawn an Opus sub-agent with label `review-<issue_number>` (ephemeral is OK for reviews)

Review task:
- Review the full diff: `git diff main <branch>`
- Focus on: security, correctness, race conditions, edge cases, code style
- **Report back** with: findings list, verdict (APPROVE / APPROVE WITH MINOR FIXES / REQUEST CHANGES)

**📢 Post to Discord:** "⏳ Waiting for review..."

When the review returns:
- **📢 Post to Discord:** "📋 Review result: **<verdict>**" (include a brief summary of findings)

### Step 5: Handle Review Result

**If APPROVE:** Go to Step 7 (merge).

**If APPROVE WITH MINOR FIXES:**
- **📢 Post to Discord:** "🔧 Applying minor fixes from review..."
- Send fixes to the implementation worker via `sessions_send` (they have the context)
- Or fix directly if trivial
- Go to Step 7 (merge)

**If REQUEST CHANGES:**
- **📢 Post to Discord:** "🔄 Review requested changes. Sending back to **<worker-name>**... (cycle N/3)"
- Send the review feedback to the implementation worker via `sessions_send`
- The worker already has context from the first implementation — this is where permanent workers shine
- Go back to Step 4 (re-review)
- Maximum 3 review cycles — if still not passing, report to user for manual intervention

### Step 6: (Loop back to Step 4 if needed)

### Step 7: Merge

**📢 Post to Discord:** "🚀 Merging #N..."

```bash
cd <checkout_path>
git checkout main && git merge <branch> && git push origin main
```
Close the GitHub issue:
```bash
curl -s -X PATCH -H "Authorization: token $TOKEN" \
  "https://api.github.com/repos/<owner>/<repo>/issues/<issue_number>" \
  -d '{"state":"closed"}'
```

### Step 8: Report

**📢 Post to Discord:** "✅ #N — done! PR #X merged, issue closed. <one-line summary of what changed>"

## Multiple Issues
1. Process **sequentially** — finish one completely before starting the next
2. After each: report status (e.g. "✅ #42 done. Starting #43...")
3. If one fails after max review cycles, skip it, report failure, continue
4. Final summary of all issues: succeeded, failed, skipped

## Key Rules
- **Use named workers first** — fall back to ephemeral sub-agents only if no named worker exists
- **Never run parallel workers on the same repo** — they clobber each other's branches
- **Workers must always report back** — silence is not acceptable
- **Sonnet implements, Opus reviews** — never the other way around
- **All tests must pass** before PR and before merge
- **Max 3 review cycles** — escalate to human if stuck
- **Named workers retain context** — send review feedback back to the same worker that implemented (they already know the code)
