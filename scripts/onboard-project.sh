#!/bin/bash
set -euo pipefail

# onboard-project.sh — Add a new project to Motley Crew
#
# Usage: onboard-project.sh <project-name> <repo-url> [lead-name]
#
# This script:
#   1. Creates a Discord channel for the project lead
#   2. Creates the lead agent workspace with SOUL.md, MEMORY.md, AGENTS.md
#   3. Clones the project repo
#   4. Generates an OpenClaw config snippet for the new agent + binding
#   5. Creates a project config file for future reference
#
# Prerequisites:
#   - DISCORD_BOT_TOKEN env var (or ~/.config/motley-crew/discord-token file)
#   - DISCORD_GUILD_ID env var (or defaults to Motley Crew server)
#   - OpenClaw installed and configured on the host
#
# After running, you must:
#   1. Merge the generated config into openclaw.json
#   2. Restart the gateway

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
TEMPLATES_DIR="$REPO_ROOT/templates"

# --- Args ---
PROJECT="${1:?Usage: onboard-project.sh <project-name> <repo-url> [lead-name]}"
REPO_URL="${2:?Usage: onboard-project.sh <project-name> <repo-url> [lead-name]}"
LEAD_NAME="${3:-}"

# --- Defaults ---
AGENTS_ROOT="${AGENTS_ROOT:-$HOME/agents}"
PROJECTS_ROOT="${PROJECTS_ROOT:-$HOME/projects}"
CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/motley-crew}"
OPENCLAW_CONFIG="${OPENCLAW_CONFIG:-$HOME/.openclaw/openclaw.json}"

# Discord config
DISCORD_BOT_TOKEN="${DISCORD_BOT_TOKEN:-}"
DISCORD_GUILD_ID="${DISCORD_GUILD_ID:-}"

if [ -z "$DISCORD_BOT_TOKEN" ] && [ -f "$CONFIG_DIR/discord-token" ]; then
    DISCORD_BOT_TOKEN=$(cat "$CONFIG_DIR/discord-token")
fi

if [ -z "$DISCORD_BOT_TOKEN" ]; then
    echo "ERROR: DISCORD_BOT_TOKEN not set and $CONFIG_DIR/discord-token not found"
    exit 1
fi

if [ -z "$DISCORD_GUILD_ID" ] && [ -f "$CONFIG_DIR/guild-id" ]; then
    DISCORD_GUILD_ID=$(cat "$CONFIG_DIR/guild-id")
fi

if [ -z "$DISCORD_GUILD_ID" ]; then
    echo "ERROR: DISCORD_GUILD_ID not set and $CONFIG_DIR/guild-id not found"
    echo "Save your Discord server ID to $CONFIG_DIR/guild-id"
    exit 1
fi

# --- Auto-pick lead name if not provided ---
# Convention: first letter matches project name
if [ -z "$LEAD_NAME" ]; then
    FIRST_LETTER=$(echo "$PROJECT" | head -c1 | tr '[:lower:]' '[:upper:]')
    NAMES_FILE="$SCRIPT_DIR/names.txt"
    if [ -f "$NAMES_FILE" ]; then
        LEAD_NAME=$(grep -i "^${FIRST_LETTER}" "$NAMES_FILE" | head -1 || true)
    fi
    if [ -z "$LEAD_NAME" ]; then
        LEAD_NAME="${FIRST_LETTER}lead"
        echo "WARNING: No name starting with '$FIRST_LETTER' found in names.txt, using '$LEAD_NAME'"
    fi
fi

LEAD_NAME_LOWER=$(echo "$LEAD_NAME" | tr '[:upper:]' '[:lower:]')
AGENT_ID="${PROJECT}-lead"
LEAD_WORKSPACE="$AGENTS_ROOT/leads/$LEAD_NAME_LOWER"
PROJECT_DIR="$PROJECTS_ROOT/$PROJECT"

echo "=== Onboarding project: $PROJECT ==="
echo "  Repo:       $REPO_URL"
echo "  Lead:       $LEAD_NAME"
echo "  Agent ID:   $AGENT_ID"
echo "  Workspace:  $LEAD_WORKSPACE"
echo "  Code:       $PROJECT_DIR/lead/"
echo ""

# --- Check for conflicts ---
if [ -d "$LEAD_WORKSPACE" ]; then
    echo "ERROR: Lead workspace already exists: $LEAD_WORKSPACE"
    echo "If re-onboarding, remove it first with: rm -rf $LEAD_WORKSPACE"
    exit 1
fi

# --- Step 1: Create Discord channel ---
echo "Step 1: Creating Discord channel #$PROJECT..."

# Find or create PROJECTS category
CATEGORIES=$(curl -s -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
    "https://discord.com/api/v10/guilds/$DISCORD_GUILD_ID/channels")

PROJECTS_CATEGORY_ID=$(echo "$CATEGORIES" | python3 -c "
import json, sys
channels = json.load(sys.stdin)
for c in channels:
    if c.get('type') == 4 and c.get('name','').upper() == 'PROJECTS':
        print(c['id'])
        break
" 2>/dev/null || true)

if [ -z "$PROJECTS_CATEGORY_ID" ]; then
    echo "  Creating PROJECTS category..."
    PROJECTS_CATEGORY_ID=$(curl -s -X POST \
        -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"PROJECTS\", \"type\": 4}" \
        "https://discord.com/api/v10/guilds/$DISCORD_GUILD_ID/channels" | \
        python3 -c "import json,sys; print(json.load(sys.stdin)['id'])")
fi

# Create the project channel
CHANNEL_RESPONSE=$(curl -s -X POST \
    -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"$PROJECT\", \"type\": 0, \"parent_id\": \"$PROJECTS_CATEGORY_ID\", \"topic\": \"Project lead: $LEAD_NAME | Repo: $REPO_URL\"}" \
    "https://discord.com/api/v10/guilds/$DISCORD_GUILD_ID/channels")

CHANNEL_ID=$(echo "$CHANNEL_RESPONSE" | python3 -c "import json,sys; print(json.load(sys.stdin)['id'])" 2>/dev/null || true)

if [ -z "$CHANNEL_ID" ]; then
    echo "ERROR: Failed to create Discord channel"
    echo "$CHANNEL_RESPONSE"
    exit 1
fi

echo "  Created #$PROJECT (ID: $CHANNEL_ID)"

# --- Step 2: Create lead workspace ---
echo "Step 2: Creating lead workspace..."

mkdir -p "$LEAD_WORKSPACE/memory"

# Parse lead template
TEMPLATE_FILE="$TEMPLATES_DIR/lead.md"
if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "ERROR: Lead template not found: $TEMPLATE_FILE"
    exit 1
fi

# Extract SOUL.md content (after frontmatter) and substitute placeholders
sed '1,/^---$/d; 1,/^---$/d' "$TEMPLATE_FILE" | \
    sed "s/{NAME}/$LEAD_NAME/g; s/{PROJECT}/$PROJECT/g" \
    > "$LEAD_WORKSPACE/SOUL.md"

# Create IDENTITY.md
cat > "$LEAD_WORKSPACE/IDENTITY.md" << ENDID
# IDENTITY.md

- **Name:** $LEAD_NAME
- **Role:** Project Lead
- **Project:** $PROJECT
- **Agent ID:** $AGENT_ID
- **Model:** anthropic/claude-sonnet-4-20250514
- **Git name:** $LEAD_NAME Sonnet Lead
- **Git email:** forge-lead@motleycrew.ai
- **Repo:** $REPO_URL
- **Discord channel:** #$PROJECT ($CHANNEL_ID)
- **Created:** $(date -u +"%Y-%m-%dT%H:%M:%SZ")
ENDID

# Create AGENTS.md
cat > "$LEAD_WORKSPACE/AGENTS.md" << 'ENDAGENTS'
# AGENTS.md — Project Lead Instructions

## Every Session

1. Read `SOUL.md` — who you are
2. Read `IDENTITY.md` — your project and role
3. Read `MEMORY.md` — project knowledge
4. Read `memory/` — recent daily notes

## Code

Your project code is at the path in IDENTITY.md. Always pull before starting work:
```bash
cd <code-path> && git pull
```

## Memory

- `MEMORY.md` — project architecture, decisions, conventions, key files
- `memory/YYYY-MM-DD.md` — daily notes (what happened, decisions, blockers)

Keep MEMORY.md current. It's how you maintain deep project knowledge across sessions.

## Workers

You have permanent workers. To assign a task:
1. Pick the right worker for the job
2. Give clear requirements
3. Review their PR
4. Merge or request changes

## Reporting

- Post status updates to your Discord channel
- Respond to CoS requests concisely
- When blocked, flag it immediately

## Git

- Workers create feature branches and PRs
- You review and merge (or request changes)
- Never commit directly to main
ENDAGENTS

# Create initial MEMORY.md (will be filled during codebase review)
cat > "$LEAD_WORKSPACE/MEMORY.md" << ENDMEM
# $PROJECT — Project Memory

## Overview
- **Repo:** $REPO_URL
- **Lead:** $LEAD_NAME
- **Onboarded:** $(date +%Y-%m-%d)

## Architecture
_(To be filled after initial codebase review)_

## Key Files
_(To be filled after initial codebase review)_

## Build & Test
_(To be filled after initial codebase review)_

## Conventions
_(To be filled after initial codebase review)_

## Open Issues
_(To be filled after initial codebase review)_
ENDMEM

# Create first daily note
cat > "$LEAD_WORKSPACE/memory/$(date +%Y-%m-%d).md" << ENDDAY
# $(date +%Y-%m-%d) — Onboarding

## Created
- Project: $PROJECT
- Repo: $REPO_URL
- Discord: #$PROJECT ($CHANNEL_ID)
- Status: Awaiting initial codebase review
ENDDAY

# Copy command runbooks
COMMANDS_DIR="$REPO_ROOT/commands"
if [ -d "$COMMANDS_DIR" ]; then
    mkdir -p "$LEAD_WORKSPACE/commands"
    cp "$COMMANDS_DIR"/*.md "$LEAD_WORKSPACE/commands/"
    echo "  Copied command runbooks to workspace"
fi

echo "  Created workspace at $LEAD_WORKSPACE"

# --- Step 3: Clone repository ---
echo "Step 3: Cloning repository..."

mkdir -p "$PROJECT_DIR/workers"
git clone "$REPO_URL" "$PROJECT_DIR/lead" 2>&1

# Configure git identity
cd "$PROJECT_DIR/lead"
git config user.name "$LEAD_NAME Sonnet Lead"
git config user.email "forge-lead@motleycrew.ai"

echo "  Cloned to $PROJECT_DIR/lead/"

# --- Step 4: Create project config ---
echo "Step 4: Saving project config..."

mkdir -p "$CONFIG_DIR/projects"
cat > "$CONFIG_DIR/projects/${PROJECT}.json" << ENDJSON
{
  "name": "$PROJECT",
  "repo": "$REPO_URL",
  "github_repo": "$(echo "$REPO_URL" | sed 's|.*github.com[:/]||; s|\.git$||')",
  "lead_agent_id": "$AGENT_ID",
  "lead_name": "$LEAD_NAME",
  "discord_channel_id": "$CHANNEL_ID",
  "lead_workspace": "$LEAD_WORKSPACE",
  "checkout_path": "$PROJECT_DIR/lead/",
  "worker_checkout_base": "$PROJECT_DIR/workers/",
  "default_branch": "main",
  "created": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
ENDJSON

echo "  Saved to $CONFIG_DIR/projects/${PROJECT}.json"

# --- Step 5: Generate OpenClaw config snippet ---
echo ""
echo "=== OpenClaw config changes needed ==="
echo ""
echo "Add to agents.list:"
echo ""
cat << ENDAGENT
  {
    "id": "$AGENT_ID",
    "name": "$LEAD_NAME ($PROJECT Lead)",
    "workspace": "$LEAD_WORKSPACE",
    "model": "anthropic/claude-sonnet-4-20250514"
  }
ENDAGENT
echo ""
echo "Add to bindings:"
echo ""
cat << ENDBINDING
  {
    "match": {
      "channel": "discord",
      "peer": { "kind": "channel", "id": "$CHANNEL_ID" }
    },
    "agentId": "$AGENT_ID"
  }
ENDBINDING
echo ""
echo "Add to channels.discord.guilds.$DISCORD_GUILD_ID.channels:"
echo ""
cat << ENDCHANNEL
  "$CHANNEL_ID": {
    "requireMention": false
  }
ENDCHANNEL
echo ""

# --- Step 6: Post introduction ---
echo "Step 5: Posting introduction to Discord..."

INTRO_MSG="👋 **#$PROJECT is now live!**\n\nLead: **$LEAD_NAME** (Sonnet)\nRepo: \`$REPO_URL\`\n\n$LEAD_NAME will do an initial codebase review and then be ready for work."

curl -s -X POST \
    -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"content\": \"$INTRO_MSG\"}" \
    "https://discord.com/api/v10/channels/$CHANNEL_ID/messages" > /dev/null

echo "  Posted introduction to #$PROJECT"

echo ""
echo "=== Onboarding complete! ==="
echo ""
echo "Next steps:"
echo "  1. Add the config snippet above to $OPENCLAW_CONFIG"
echo "  2. Restart the OpenClaw gateway"
echo "  3. Talk to $LEAD_NAME in #$PROJECT to trigger codebase review"
echo ""
