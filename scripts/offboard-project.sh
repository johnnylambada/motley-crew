#!/bin/bash
set -euo pipefail

# offboard-project.sh — Remove a project from Motley Crew
#
# Usage: offboard-project.sh <project-name> [--archive]
#
# This script:
#   1. Archives lead memory (if --archive)
#   2. Removes all workers for the project
#   3. Removes the lead workspace
#   4. Archives the Discord channel
#   5. Removes the project config
#
# Does NOT modify openclaw.json — you must remove the agent and binding manually.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# --- Args ---
PROJECT="${1:?Usage: offboard-project.sh <project-name> [--archive]}"
ARCHIVE="${2:-}"

# --- Defaults ---
AGENTS_ROOT="${AGENTS_ROOT:-$HOME/agents}"
PROJECTS_ROOT="${PROJECTS_ROOT:-$HOME/projects}"
CONFIG_DIR="${CONFIG_DIR:-$HOME/.config/motley-crew}"
ARCHIVE_DIR="${ARCHIVE_DIR:-$HOME/agents/archive}"

PROJECT_CONFIG="$CONFIG_DIR/projects/${PROJECT}.json"

if [ ! -f "$PROJECT_CONFIG" ]; then
    echo "ERROR: Project config not found: $PROJECT_CONFIG"
    exit 1
fi

# Parse project config
LEAD_NAME=$(python3 -c "import json; print(json.load(open('$PROJECT_CONFIG'))['lead_name'])")
LEAD_WORKSPACE=$(python3 -c "import json; print(json.load(open('$PROJECT_CONFIG'))['lead_workspace'])")
CHANNEL_ID=$(python3 -c "import json; print(json.load(open('$PROJECT_CONFIG'))['discord_channel_id'])")
REPO_URL=$(python3 -c "import json; print(json.load(open('$PROJECT_CONFIG'))['repo'])")

echo "=== Offboarding project: $PROJECT ==="
echo "  Lead:      $LEAD_NAME"
echo "  Workspace: $LEAD_WORKSPACE"
echo "  Channel:   $CHANNEL_ID"
echo ""

read -p "Are you sure? This will remove all project data. [y/N] " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# --- Step 1: Archive memory ---
if [ "$ARCHIVE" = "--archive" ]; then
    echo "Step 1: Archiving memory..."
    mkdir -p "$ARCHIVE_DIR/$PROJECT-$(date +%Y%m%d)"
    
    if [ -d "$LEAD_WORKSPACE/memory" ]; then
        cp -r "$LEAD_WORKSPACE/memory" "$ARCHIVE_DIR/$PROJECT-$(date +%Y%m%d)/lead-memory"
    fi
    if [ -f "$LEAD_WORKSPACE/MEMORY.md" ]; then
        cp "$LEAD_WORKSPACE/MEMORY.md" "$ARCHIVE_DIR/$PROJECT-$(date +%Y%m%d)/lead-MEMORY.md"
    fi
    echo "  Archived to $ARCHIVE_DIR/$PROJECT-$(date +%Y%m%d)/"
else
    echo "Step 1: Skipping archive (use --archive to preserve memory)"
fi

# --- Step 2: Remove workers ---
echo "Step 2: Removing workers..."
"$SCRIPT_DIR/remove-project.sh" "$REPO_URL" "$AGENTS_ROOT/workers" "$ARCHIVE_DIR" 2>/dev/null || echo "  No workers found."

# --- Step 3: Remove lead workspace ---
echo "Step 3: Removing lead workspace..."
if [ -d "$LEAD_WORKSPACE" ]; then
    rm -rf "$LEAD_WORKSPACE"
    echo "  Removed $LEAD_WORKSPACE"
fi

# --- Step 4: Remove code checkouts ---
echo "Step 4: Removing code checkouts..."
if [ -d "$PROJECTS_ROOT/$PROJECT" ]; then
    rm -rf "$PROJECTS_ROOT/$PROJECT"
    echo "  Removed $PROJECTS_ROOT/$PROJECT"
fi

# --- Step 5: Archive Discord channel ---
echo "Step 5: Archiving Discord channel..."

DISCORD_BOT_TOKEN="${DISCORD_BOT_TOKEN:-}"
if [ -z "$DISCORD_BOT_TOKEN" ] && [ -f "$CONFIG_DIR/discord-token" ]; then
    DISCORD_BOT_TOKEN=$(cat "$CONFIG_DIR/discord-token")
fi

if [ -n "$DISCORD_BOT_TOKEN" ]; then
    # Send farewell message
    curl -s -X POST \
        -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"content\": \"📦 Project **$PROJECT** has been offboarded. This channel is now archived.\"}" \
        "https://discord.com/api/v10/channels/$CHANNEL_ID/messages" > /dev/null

    # Archive the channel (set archived flag via permission overwrite to deny Send Messages)
    # Discord doesn't have a true "archive" API — we rename and move to an ARCHIVE category
    GUILD_ID="${DISCORD_GUILD_ID:-}"
    if [ -z "$GUILD_ID" ] && [ -f "$CONFIG_DIR/guild-id" ]; then
        GUILD_ID=$(cat "$CONFIG_DIR/guild-id")
    fi

    curl -s -X PATCH \
        -H "Authorization: Bot $DISCORD_BOT_TOKEN" \
        -H "Content-Type: application/json" \
        -d "{\"name\": \"archived-$PROJECT\"}" \
        "https://discord.com/api/v10/channels/$CHANNEL_ID" > /dev/null
    
    echo "  Renamed channel to #archived-$PROJECT"
else
    echo "  WARNING: No Discord token — channel not archived"
fi

# --- Step 6: Remove project config ---
echo "Step 6: Removing project config..."
rm -f "$PROJECT_CONFIG"
echo "  Removed $PROJECT_CONFIG"

echo ""
echo "=== Offboarding complete! ==="
echo ""
echo "Manual steps remaining:"
echo "  1. Remove the '$PROJECT-lead' agent from openclaw.json agents.list"
echo "  2. Remove the binding for channel $CHANNEL_ID from openclaw.json bindings"
echo "  3. Remove channel $CHANNEL_ID from guilds config"
echo "  4. Restart the OpenClaw gateway"
echo ""
