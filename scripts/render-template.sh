#!/usr/bin/env bash
set -euo pipefail

# render-template.sh — Render a Mustache template with variables
#
# Usage: render-template.sh <template-file> [VAR=value ...]
#
# Strips YAML frontmatter (between --- delimiters) and renders
# Mustache placeholders using mo.
#
# Variables can be passed as arguments or exported in the environment.
#
# Examples:
#   render-template.sh templates/lead.md NAME=Tom PROJECT=toolguard
#   NAME=Tom PROJECT=toolguard render-template.sh templates/lead.md

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MO="$SCRIPT_DIR/lib/mo"

if [ ! -f "$MO" ]; then
    echo "ERROR: mo not found at $MO" >&2
    echo "Run: curl -sSL https://raw.githubusercontent.com/tests-always-included/mo/master/mo -o $MO" >&2
    exit 1
fi

TEMPLATE="${1:?Usage: render-template.sh <template-file> [VAR=value ...]}"
shift

if [ ! -f "$TEMPLATE" ]; then
    echo "ERROR: Template not found: $TEMPLATE" >&2
    exit 1
fi

# Export any VAR=value arguments
for arg in "$@"; do
    if [[ "$arg" == *=* ]]; then
        export "$arg"
    fi
done

# Strip YAML frontmatter (content between first pair of --- lines)
# Then render through mo
awk '
    BEGIN { in_front=0; past_front=0 }
    /^---$/ {
        if (!past_front) {
            if (in_front) { past_front=1; next }
            else { in_front=1; next }
        }
    }
    past_front || !in_front { print }
' "$TEMPLATE" | "$MO"
