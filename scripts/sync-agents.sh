#!/usr/bin/env bash
set -euo pipefail

# sync-agents.sh — Propagate repo changes to all live agents
#
# Usage: sync-agents.sh [--agents-root <path>] [--dry-run]
#
# After updating motley-crew (git pull), run this to push changes
# to all leads, workers, and CoS.
#
# What it syncs (repo-owned):
#   - commands/*.md → agent commands/ dirs
#   - SOUL.md (re-rendered from templates using agent's IDENTITY.md)
#   - AGENTS.md (from repo template, if present)
#
# What it never touches (agent-owned):
#   - MEMORY.md, memory/*.md
#   - IDENTITY.md
#   - USER.md, TOOLS.md, HEARTBEAT.md
#
# Reads agent identity (name, project, template) from each agent's
# IDENTITY.md to substitute template placeholders.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
RENDER="$SCRIPT_DIR/render-template.sh"
COMMANDS_DIR="$REPO_ROOT/commands"
TEMPLATES_DIR="$REPO_ROOT/templates"

# --- Parse args ---
AGENTS_ROOT=""
DRY_RUN=false

while [ $# -gt 0 ]; do
    case "$1" in
        --agents-root) AGENTS_ROOT="$2"; shift 2 ;;
        --dry-run)     DRY_RUN=true; shift ;;
        -h|--help)
            cat << 'EOF'
sync-agents.sh — Propagate repo changes to all live agents

USAGE:
  sync-agents.sh [--agents-root <path>] [--dry-run]

OPTIONS:
  --agents-root <path>  Override agents directory (default: auto-detect)
  --dry-run             Show what would change without writing

WHAT IT SYNCS (repo-owned):
  commands/*.md    → agent commands/ dirs
  SOUL.md          → re-rendered from template + agent IDENTITY.md
  AGENTS.md        → from repo template (if agents-template.md exists)

WHAT IT NEVER TOUCHES (agent-owned):
  MEMORY.md, memory/*.md, IDENTITY.md, USER.md, TOOLS.md, HEARTBEAT.md

TYPICAL USAGE:
  cd ~/Documents/motley-crew
  git pull
  ./scripts/sync-agents.sh
EOF
            exit 0
            ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# --- Auto-detect agents root ---
if [ -z "$AGENTS_ROOT" ]; then
    # Check config dir for project configs that list agent paths
    CONFIG_DIR="${MC_CONFIG_DIR:-$HOME/.config/motley-crew}"
    if [ -d "$CONFIG_DIR/projects" ]; then
        # Extract lead_workspace dirs to find the agents root
        FIRST_WORKSPACE=$(python3 -c "
import json, os, glob
for f in sorted(glob.glob('$CONFIG_DIR/projects/*.json')):
    with open(f) as fh:
        d = json.load(fh)
        ws = d.get('lead_workspace', '')
        if ws:
            # agents root is two levels up from leads/<name>/
            print(os.path.dirname(os.path.dirname(ws)))
            break
" 2>/dev/null || true)
        if [ -n "$FIRST_WORKSPACE" ]; then
            AGENTS_ROOT="$FIRST_WORKSPACE"
        fi
    fi
fi

if [ -z "$AGENTS_ROOT" ]; then
    AGENTS_ROOT="$HOME/agents"
fi

echo "=== sync-agents.sh ==="
echo "  Repo:   $REPO_ROOT"
echo "  Agents: $AGENTS_ROOT"
echo "  Dry run: $DRY_RUN"
echo ""

UPDATED=0
SKIPPED=0

# --- Helper: update file if changed ---
update_file() {
    local src="$1"
    local dst="$2"
    local label="$3"

    if [ ! -f "$src" ]; then
        return
    fi

    if [ -f "$dst" ] && diff -q "$src" "$dst" > /dev/null 2>&1; then
        SKIPPED=$((SKIPPED + 1))
        return
    fi

    if $DRY_RUN; then
        echo "  [dry-run] Would update: $label"
    else
        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"
        echo "  ✅ Updated: $label"
    fi
    UPDATED=$((UPDATED + 1))
}

# --- Helper: update file from string content ---
update_file_content() {
    local content="$1"
    local dst="$2"
    local label="$3"

    if [ -f "$dst" ]; then
        existing=$(cat "$dst")
        if [ "$content" = "$existing" ]; then
            SKIPPED=$((SKIPPED + 1))
            return
        fi
    fi

    if $DRY_RUN; then
        echo "  [dry-run] Would update: $label"
    else
        mkdir -p "$(dirname "$dst")"
        printf '%s\n' "$content" > "$dst"
        echo "  ✅ Updated: $label"
    fi
    UPDATED=$((UPDATED + 1))
}

# --- Helper: read IDENTITY.md for template variables ---
read_identity() {
    local identity_file="$1"
    # Parse key: value pairs from IDENTITY.md
    python3 -c "
import re, sys
with open('$identity_file') as f:
    for line in f:
        m = re.match(r'[-*]\s+\*\*(\w+):\*\*\s*(.*)', line)
        if m:
            key = m.group(1).upper().strip()
            val = m.group(2).strip()
            print(f'{key}={val}')
" 2>/dev/null || true
}

# --- Helper: detect template type for an agent ---
detect_template() {
    local agent_dir="$1"
    local identity_file="$agent_dir/IDENTITY.md"

    if [ ! -f "$identity_file" ]; then
        echo ""
        return
    fi

    local role=$(grep -i '\*\*Role:\*\*' "$identity_file" | head -1 | sed 's/.*\*\*Role:\*\*\s*//' | tr '[:upper:]' '[:lower:]' | xargs)

    case "$role" in
        "project lead") echo "lead" ;;
        *)
            # Check for template field in IDENTITY.md
            local tmpl=$(grep -i '\*\*Template:\*\*' "$identity_file" | head -1 | sed 's/.*\*\*Template:\*\*\s*//' | xargs)
            echo "$tmpl"
            ;;
    esac
}

# --- Sync commands to an agent ---
sync_commands() {
    local agent_dir="$1"
    local agent_name="$2"

    if [ ! -d "$COMMANDS_DIR" ]; then
        return
    fi

    for cmd_file in "$COMMANDS_DIR"/*.md; do
        [ -f "$cmd_file" ] || continue
        local basename=$(basename "$cmd_file")
        update_file "$cmd_file" "$agent_dir/commands/$basename" "$agent_name/commands/$basename"
    done
}

# --- Sync SOUL.md for an agent ---
sync_soul() {
    local agent_dir="$1"
    local agent_name="$2"
    local template_type="$3"

    if [ -z "$template_type" ]; then
        return
    fi

    local template_file="$TEMPLATES_DIR/${template_type}.md"
    if [ ! -f "$template_file" ]; then
        echo "  ⚠️  Template not found for $agent_name: $template_file"
        return
    fi

    # Read identity variables
    local identity_file="$agent_dir/IDENTITY.md"
    if [ ! -f "$identity_file" ]; then
        echo "  ⚠️  No IDENTITY.md for $agent_name, skipping SOUL.md"
        return
    fi

    # Render template in a subshell to avoid env leakage between agents
    local rendered
    rendered=$(
        # Export variables from IDENTITY.md
        vars=$(read_identity "$identity_file")
        while IFS= read -r line; do
            [ -n "$line" ] && export "$line"
        done <<< "$vars"
        "$RENDER" "$template_file"
    )

    update_file_content "$rendered" "$agent_dir/SOUL.md" "$agent_name/SOUL.md"
}

# --- Process a single agent ---
process_agent() {
    local agent_dir="$1"
    local agent_name="$2"

    if [ ! -d "$agent_dir" ]; then
        return
    fi

    echo "Agent: $agent_name"

    # Sync commands
    sync_commands "$agent_dir" "$agent_name"

    # Detect template and sync SOUL.md
    local template_type
    template_type=$(detect_template "$agent_dir")
    sync_soul "$agent_dir" "$agent_name" "$template_type"
}

# --- Process CoS ---
if [ -d "$AGENTS_ROOT/cos" ]; then
    process_agent "$AGENTS_ROOT/cos" "cos"
fi

# --- Process leads ---
if [ -d "$AGENTS_ROOT/leads" ]; then
    for lead_dir in "$AGENTS_ROOT/leads"/*/; do
        [ -d "$lead_dir" ] || continue
        name=$(basename "$lead_dir")
        process_agent "$lead_dir" "leads/$name"
    done
fi

# --- Process workers ---
# Workers live under project checkout dirs, find them via project configs
CONFIG_DIR="${MC_CONFIG_DIR:-$HOME/.config/motley-crew}"
if [ -d "$CONFIG_DIR/projects" ]; then
    for config_file in "$CONFIG_DIR/projects"/*.json; do
        [ -f "$config_file" ] || continue
        worker_base=$(python3 -c "import json; print(json.load(open('$config_file')).get('worker_checkout_base',''))" 2>/dev/null || true)
        if [ -n "$worker_base" ] && [ -d "$worker_base" ]; then
            for worker_dir in "$worker_base"/*/; do
                [ -d "$worker_dir" ] || continue
                # Workers have their workspace inside the checkout
                # Look for IDENTITY.md to confirm it's a worker
                if [ -f "$worker_dir/IDENTITY.md" ]; then
                    name=$(basename "$worker_dir")
                    process_agent "$worker_dir" "workers/$name"
                fi
            done
        fi
    done
fi

echo ""
echo "=== Done: $UPDATED updated, $SKIPPED unchanged ==="
