#!/usr/bin/env bash
# SessionStart — emit plugin_version so Warp can track the install.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/should-use-structured.sh"

if ! should_use_structured; then
    exit 0
fi

if ! command -v jq &>/dev/null; then
    echo "warp plugin: jq is required for Warp notifications (e.g. brew install jq)" >&2
    exit 0
fi

source "$SCRIPT_DIR/build-payload.sh"

INPUT=$(cat)

PLUGIN_VERSION=$(jq -r '.version // "unknown"' "$SCRIPT_DIR/../plugin.json" 2>/dev/null)

BODY=$(build_payload "$INPUT" "session_start" \
    --arg plugin_version "$PLUGIN_VERSION")
"$SCRIPT_DIR/warp-notify.sh" "warp://cli-agent" "$BODY"
