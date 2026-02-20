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
Extract title, body, and labels. Confirm to user what's being implemented.

### Step 2: Sonnet Implements
Spawn a sub-agent (Sonnet, default model) with label `impl-<issue_number>`:
- Read the issue details
- Read relevant source files in the project checkout
- Create branch `feature/<descriptive-name>` or `fix/<descriptive-name>` off main
- Implement the fix/feature
- Run build and test commands from project config (or detect from repo)
- Commit and push
- Open a PR against main with clear description referencing the issue
- **Report back** with: branch name, PR number, files changed, test results, design decisions

Timeout: 900s (15 min). If it times out, check for uncommitted work and finish manually.

### Step 3: Opus Reviews
Once Sonnet's PR is ready, spawn an Opus sub-agent with label `review-<issue_number>`:
- Model: `anthropic/claude-opus-4-6`
- Review the full diff: `git diff main <branch>`
- Focus on: security, correctness, race conditions, edge cases, code style
- **Report back** with: findings list, verdict (APPROVE / APPROVE WITH MINOR FIXES / REQUEST CHANGES)

Timeout: 450s (7.5 min).

### Step 4: Handle Review Result

**If APPROVE:** Go to Step 6 (merge).

**If APPROVE WITH MINOR FIXES:**
- Fix the minor issues directly (no sub-agent needed for small fixes)
- Commit and push
- Go to Step 6 (merge)

**If REQUEST CHANGES:**
- Fix all issues listed by Opus (directly if straightforward, or spawn Sonnet if complex)
- Commit and push
- Go back to Step 3 (Opus re-reviews)
- Maximum 3 review cycles — if still not passing, report to user for manual intervention

### Step 5: (Loop back to Step 3 if needed)

### Step 6: Merge
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

### Step 7: Report
Tell user: issue closed, PR merged, summary of what was done.

## Multiple Issues
1. Process **sequentially** — finish one completely before starting the next
2. After each: report status (e.g. "✅ #42 done. Starting #43...")
3. If one fails after max review cycles, skip it, report failure, continue
4. Final summary of all issues: succeeded, failed, skipped

## Key Rules
- **Never run parallel sub-agents on the same repo** — they clobber each other's branches
- **Sub-agents must always report back** — silence is not acceptable
- **Sonnet implements, Opus reviews** — never the other way around
- **All tests must pass** before PR and before merge
- **Max 3 review cycles** — escalate to human if stuck
