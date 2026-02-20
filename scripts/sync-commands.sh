#!/bin/bash
set -euo pipefail

# sync-commands.sh — Copy command runbooks to all agent workspaces
#
# Usage: sync-commands.sh [agents-root]
#
# Copies commands/*.md from the motley-crew repo to:
#   - CoS workspace (~/agents/cos/commands/)
#   - All lead workspaces (~/agents/leads/*/commands/)
#
# Run this after updating command runbooks.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
COMMANDS_DIR="$REPO_ROOT/commands"
AGENTS_ROOT="${1:-$HOME/agents}"

if [ ! -d "$COMMANDS_DIR" ]; then
    echo "ERROR: No commands directory at $COMMANDS_DIR"
    exit 1
fi

COUNT=0

# CoS
COS_DIR="$AGENTS_ROOT/cos/commands"
if [ -d "$AGENTS_ROOT/cos" ]; then
    mkdir -p "$COS_DIR"
    cp "$COMMANDS_DIR"/*.md "$COS_DIR/"
    echo "  Updated: cos"
    COUNT=$((COUNT + 1))
fi

# Leads
if [ -d "$AGENTS_ROOT/leads" ]; then
    for lead_dir in "$AGENTS_ROOT/leads"/*/; do
        [ -d "$lead_dir" ] || continue
        mkdir -p "${lead_dir}commands"
        cp "$COMMANDS_DIR"/*.md "${lead_dir}commands/"
        name=$(basename "$lead_dir")
        echo "  Updated: $name"
        COUNT=$((COUNT + 1))
    done
fi

echo "Synced commands to $COUNT agent(s)."
