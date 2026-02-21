#!/usr/bin/env bash
set -euo pipefail

# deploy.sh — Push repo changes to a remote mcbox and sync agents
#
# Usage: deploy.sh [--dry-run]
#
# Dogfoods git pull + sync-agents.sh on the remote machine.
#
# Config: reads from .deploy.env (repo root) or ~/.config/motley-crew/deploy.env
#
# Required config variables:
#   MC_HOST     — hostname or IP of the mcbox (e.g., atari400.local)
#   MC_USER     — SSH user on mcbox (e.g., motleycrew)
#   MC_REPO_PATH — path to motley-crew repo on mcbox (e.g., ~/Documents/motley-crew)
#
# Optional:
#   MC_BRANCH   — branch to pull (default: current branch)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# --- Help ---
if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    cat << 'EOF'
deploy.sh — Push repo changes to a remote mcbox and sync agents

USAGE:
  deploy.sh [--dry-run]

WHAT IT DOES:
  1. git push (ensure GitHub is current)
  2. SSH to mcbox → git pull
  3. SSH to mcbox → sync-agents.sh (propagate to all agents)

CONFIG:
  Reads from .deploy.env (repo root) or ~/.config/motley-crew/deploy.env

  Required:
    MC_HOST=atari400.local      # mcbox hostname
    MC_USER=motleycrew          # SSH user
    MC_REPO_PATH=~/Documents/motley-crew  # repo path on mcbox

  Optional:
    MC_BRANCH=main              # branch to pull (default: current)

SETUP:
  cp .deploy.env.example .deploy.env
  # Edit .deploy.env with your values
  # .deploy.env is gitignored

OPTIONS:
  --dry-run    Show what would happen without doing it
EOF
    exit 0
fi

# --- Parse args ---
DRY_RUN=false
SYNC_ARGS=""
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=true; SYNC_ARGS="--dry-run"; shift ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

# --- Load config ---
CONFIG_FILE=""
if [ -f "$REPO_ROOT/.deploy.env" ]; then
    CONFIG_FILE="$REPO_ROOT/.deploy.env"
elif [ -f "$HOME/.config/motley-crew/deploy.env" ]; then
    CONFIG_FILE="$HOME/.config/motley-crew/deploy.env"
fi

if [ -z "$CONFIG_FILE" ]; then
    echo "ERROR: No deploy config found." >&2
    echo "Create .deploy.env in the repo root or ~/.config/motley-crew/deploy.env" >&2
    echo "See .deploy.env.example for the format." >&2
    exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

MC_HOST="${MC_HOST:?MC_HOST not set in $CONFIG_FILE}"
MC_USER="${MC_USER:?MC_USER not set in $CONFIG_FILE}"
MC_REPO_PATH="${MC_REPO_PATH:?MC_REPO_PATH not set in $CONFIG_FILE}"
MC_BRANCH="${MC_BRANCH:-$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)}"

echo "=== deploy.sh ==="
echo "  Target: $MC_USER@$MC_HOST"
echo "  Repo:   $MC_REPO_PATH"
echo "  Branch: $MC_BRANCH"
echo "  Dry run: $DRY_RUN"
echo ""

# --- Step 1: git push ---
echo "Step 1: Pushing to GitHub..."
if $DRY_RUN; then
    echo "  [dry-run] Would run: git push"
else
    cd "$REPO_ROOT"
    git push origin "$MC_BRANCH" 2>&1 | sed 's/^/  /'
fi
echo ""

# --- Step 2: git pull on mcbox ---
echo "Step 2: Pulling on $MC_HOST..."
if $DRY_RUN; then
    echo "  [dry-run] Would SSH and git pull"
else
    ssh "$MC_USER@$MC_HOST" "cd $MC_REPO_PATH && git fetch origin && git checkout $MC_BRANCH && git pull origin $MC_BRANCH" 2>&1 | sed 's/^/  /'
fi
echo ""

# --- Step 3: sync agents ---
echo "Step 3: Syncing agents on $MC_HOST..."
if $DRY_RUN; then
    ssh "$MC_USER@$MC_HOST" "cd $MC_REPO_PATH && ./scripts/sync-agents.sh --dry-run" 2>&1 | sed 's/^/  /'
else
    ssh "$MC_USER@$MC_HOST" "cd $MC_REPO_PATH && ./scripts/sync-agents.sh $SYNC_ARGS" 2>&1 | sed 's/^/  /'
fi
echo ""

echo "=== Deploy complete ==="
