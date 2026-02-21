#!/bin/bash
set -euo pipefail

# spawn-worker.sh — Create a new permanent worker from a template
#
# Usage: spawn-worker.sh <template> <project-repo-url> [workspace-root]
#
# Example: spawn-worker.sh dev-sonnet git@github.com:toolguard/toolguard.git
#
# Creates a worker with:
#   - Random human first name
#   - Personalized SOUL.md from template
#   - Fresh code checkout
#   - Git identity configured

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEMPLATES_DIR="$REPO_ROOT/templates"

# --- Args ---
TEMPLATE="${1:?Usage: spawn-worker.sh <template> <project-repo-url> [workspace-root]}"
REPO_URL="${2:?Usage: spawn-worker.sh <template> <project-repo-url> [workspace-root]}"
WORKSPACE_ROOT="${3:-$HOME/agents/workers}"

TEMPLATE_FILE="$TEMPLATES_DIR/${TEMPLATE}.md"
if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "ERROR: Template not found: $TEMPLATE_FILE"
    echo "Available templates:"
    ls "$TEMPLATES_DIR"/*.md 2>/dev/null | xargs -I{} basename {} .md
    exit 1
fi

NAMES_FILE="$SCRIPT_DIR/names.txt"
if [ ! -f "$NAMES_FILE" ]; then
    echo "ERROR: Names file not found: $NAMES_FILE"
    exit 1
fi

# --- Parse template frontmatter ---
parse_frontmatter() {
    local file="$1"
    local key="$2"
    # Extract value from YAML frontmatter between --- markers
    sed -n '/^---$/,/^---$/p' "$file" | grep "^${key}:" | head -1 | sed "s/^${key}:[[:space:]]*//"
}

MODEL=$(parse_frontmatter "$TEMPLATE_FILE" "model")
GIT_IDENTITY=$(parse_frontmatter "$TEMPLATE_FILE" "git_identity")

# Derive role from template name
case "$TEMPLATE" in
    dev-*)       ROLE="Developer" ;;
    reviewer-*)  ROLE="Reviewer" ;;
    qa-*)        ROLE="QA" ;;
    docs-*)      ROLE="Writer" ;;
    *)           ROLE="Worker" ;;
esac

# Derive model short name
case "$MODEL" in
    *opus*)    MODEL_SHORT="Opus" ;;
    *sonnet*)  MODEL_SHORT="Sonnet" ;;
    *haiku*)   MODEL_SHORT="Haiku" ;;
    *grok*)    MODEL_SHORT="Grok" ;;
    *minimax*) MODEL_SHORT="MiniMax" ;;
    *)         MODEL_SHORT="AI" ;;
esac

# --- Pick a unique name ---
EXISTING_NAMES=""
if [ -d "$WORKSPACE_ROOT" ]; then
    EXISTING_NAMES=$(ls "$WORKSPACE_ROOT" 2>/dev/null | tr '[:upper:]' '[:lower:]')
fi

NAME=""
while IFS= read -r candidate; do
    candidate_lower=$(echo "$candidate" | tr '[:upper:]' '[:lower:]')
    if ! echo "$EXISTING_NAMES" | grep -q "^${candidate_lower}$"; then
        NAME="$candidate"
        break
    fi
done < <(shuf "$NAMES_FILE")

if [ -z "$NAME" ]; then
    echo "ERROR: All names are taken! Add more to $NAMES_FILE"
    exit 1
fi

NAME_LOWER=$(echo "$NAME" | tr '[:upper:]' '[:lower:]')
WORKER_DIR="$WORKSPACE_ROOT/$NAME_LOWER"
GIT_NAME="$NAME $MODEL_SHORT $ROLE"
GIT_EMAIL="${GIT_IDENTITY:-forge-dev}@motleycrew.ai"

echo "=== Spawning worker ==="
echo "  Name:     $NAME"
echo "  Template: $TEMPLATE"
echo "  Model:    $MODEL"
echo "  Role:     $ROLE"
echo "  Git:      $GIT_NAME <$GIT_EMAIL>"
echo "  Workspace: $WORKER_DIR"
echo ""

# --- Create workspace ---
mkdir -p "$WORKER_DIR/memory" "$WORKER_DIR/tasks"

# --- Clone repo ---
echo "Cloning $REPO_URL..."
git clone "$REPO_URL" "$WORKER_DIR/code" 2>&1
echo ""

# --- Configure git identity ---
cd "$WORKER_DIR/code"
git config user.name "$GIT_NAME"
git config user.email "$GIT_EMAIL"

# --- Extract SOUL.md from template ---
"$SCRIPT_DIR/render-template.sh" "$TEMPLATE_FILE" "NAME=$NAME" "PROJECT=$PROJECT_NAME" > "$WORKER_DIR/SOUL.md"

# Prepend the worker's name to SOUL.md
SOUL_CONTENT=$(cat "$WORKER_DIR/SOUL.md")
cat > "$WORKER_DIR/SOUL.md" << ENDSOUL
# $NAME — $MODEL_SHORT $ROLE

Your name is **$NAME**. You are a $ROLE on the Motley Crew team.

$SOUL_CONTENT
ENDSOUL

# --- Create IDENTITY.md ---
cat > "$WORKER_DIR/IDENTITY.md" << ENDID
# IDENTITY.md

- **Name:** $NAME
- **Template:** $TEMPLATE
- **Model:** $MODEL
- **Role:** $ROLE
- **Git name:** $GIT_NAME
- **Git email:** $GIT_EMAIL
- **Project repo:** $REPO_URL
- **Created:** $(date -u +"%Y-%m-%dT%H:%M:%SZ")
ENDID

# --- Create AGENTS.md ---
cat > "$WORKER_DIR/AGENTS.md" << ENDAGENTS
# AGENTS.md — Worker Instructions

## Every Session

1. Read \`SOUL.md\` — who you are
2. Read \`IDENTITY.md\` — your role and project
3. Read \`memory/\` — recent context

## Code

Your project code is at \`code/\`. Always pull before starting a new task:
\`\`\`bash
cd code && git pull
\`\`\`

## Memory

Write daily notes to \`memory/YYYY-MM-DD.md\`. Capture:
- What you worked on
- Decisions made
- Blockers or concerns
- Things to remember for next time

## Reporting

After every task, report back to your lead with:
- What you did
- Branch name and key commits
- Test results
- Any concerns

## Git

Your commits are attributed as: **$GIT_NAME <$GIT_EMAIL>**

Always work on feature branches, never commit to main.
ENDAGENTS

# --- Create initial memory ---
cat > "$WORKER_DIR/memory/$(date +%Y-%m-%d).md" << ENDMEM
# $(date +%Y-%m-%d) — First day

## Created
- Template: $TEMPLATE
- Model: $MODEL
- Role: $ROLE
- Project: $REPO_URL
ENDMEM

echo "=== Worker $NAME created successfully ==="
echo ""
echo "Workspace: $WORKER_DIR"
echo "To assign a task, send a message to the worker's session."
