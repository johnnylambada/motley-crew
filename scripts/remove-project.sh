#!/bin/bash
set -euo pipefail

# remove-project.sh — Remove all workers for a project and archive their memory
#
# Usage: remove-project.sh <project-repo-url> [workspace-root] [archive-dir]
#
# This is the ONLY way workers get removed — when the entire project is decommissioned.

REPO_URL="${1:?Usage: remove-project.sh <project-repo-url> [workspace-root] [archive-dir]}"
WORKSPACE_ROOT="${2:-$HOME/agents/workers}"
ARCHIVE_DIR="${3:-$HOME/agents/archive}"

if [ ! -d "$WORKSPACE_ROOT" ]; then
    echo "No workers found."
    exit 0
fi

echo "=== Removing workers for project: $REPO_URL ==="
echo ""

REMOVED=0
for worker_dir in "$WORKSPACE_ROOT"/*/; do
    [ -d "$worker_dir" ] || continue
    
    identity_file="$worker_dir/IDENTITY.md"
    [ -f "$identity_file" ] || continue
    
    worker_repo=$(grep "^\- \*\*Project repo:\*\*" "$identity_file" | sed 's/.*\*\* //')
    
    if [ "$worker_repo" = "$REPO_URL" ]; then
        name=$(grep "^\- \*\*Name:\*\*" "$identity_file" | sed 's/.*\*\* //')
        
        # Archive memory
        mkdir -p "$ARCHIVE_DIR"
        archive_name="${name}-$(date +%Y%m%d)"
        if [ -d "$worker_dir/memory" ]; then
            cp -r "$worker_dir/memory" "$ARCHIVE_DIR/$archive_name"
            echo "  Archived memory: $ARCHIVE_DIR/$archive_name"
        fi
        
        # Remove workspace
        rm -rf "$worker_dir"
        echo "  Removed worker: $name"
        REMOVED=$((REMOVED + 1))
    fi
done

echo ""
echo "Removed $REMOVED worker(s)."
