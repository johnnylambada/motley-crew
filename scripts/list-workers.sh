#!/bin/bash
set -euo pipefail

# list-workers.sh — List all workers and their status
#
# Usage: list-workers.sh [workspace-root]

WORKSPACE_ROOT="${1:-$HOME/agents/workers}"

if [ ! -d "$WORKSPACE_ROOT" ]; then
    echo "No workers found."
    exit 0
fi

printf "%-12s %-15s %-10s %-8s %s\n" "NAME" "TEMPLATE" "ROLE" "MODEL" "CREATED"
printf "%-12s %-15s %-10s %-8s %s\n" "----" "--------" "----" "-----" "-------"

for worker_dir in "$WORKSPACE_ROOT"/*/; do
    [ -d "$worker_dir" ] || continue
    
    identity_file="$worker_dir/IDENTITY.md"
    [ -f "$identity_file" ] || continue
    
    name=$(grep "^\- \*\*Name:\*\*" "$identity_file" | sed 's/.*\*\* //')
    template=$(grep "^\- \*\*Template:\*\*" "$identity_file" | sed 's/.*\*\* //')
    role=$(grep "^\- \*\*Role:\*\*" "$identity_file" | sed 's/.*\*\* //')
    model=$(grep "^\- \*\*Model:\*\*" "$identity_file" | sed 's/.*\*\* //')
    created=$(grep "^\- \*\*Created:\*\*" "$identity_file" | sed 's/.*\*\* //' | cut -dT -f1)
    
    # Shorten model name
    case "$model" in
        *opus*)    model_short="Opus" ;;
        *sonnet*)  model_short="Sonnet" ;;
        *haiku*)   model_short="Haiku" ;;
        *grok*)    model_short="Grok" ;;
        *minimax*) model_short="MiniMax" ;;
        *)         model_short="$model" ;;
    esac
    
    printf "%-12s %-15s %-10s %-8s %s\n" "$name" "$template" "$role" "$model_short" "$created"
done
