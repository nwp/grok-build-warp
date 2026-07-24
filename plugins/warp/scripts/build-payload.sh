#!/usr/bin/env bash
# Builds a structured JSON notification payload for warp://cli-agent.
#
# Usage: source this file, then call build_payload with event-specific fields.
#
# Example:
#   source "$(dirname "${BASH_SOURCE[0]}")/build-payload.sh"
#   BODY=$(build_payload "$INPUT" "stop" \
#       --arg query "$QUERY" \
#       --arg response "$RESPONSE")
#
# Extracts common fields (session_id, cwd, project) from the hook stdin JSON
# (passed as $1), accepting both camelCase (Grok) and snake_case (Claude-compat).

PLUGIN_CURRENT_PROTOCOL_VERSION=1

# Negotiate protocol version with Warp: min(plugin_current, warp_declared).
# Falls back to 1 when Warp does not advertise a version.
negotiate_protocol_version() {
    local warp_version="${WARP_CLI_AGENT_PROTOCOL_VERSION:-1}"
    if [ "$warp_version" -lt "$PLUGIN_CURRENT_PROTOCOL_VERSION" ] 2>/dev/null; then
        echo "$warp_version"
    else
        echo "$PLUGIN_CURRENT_PROTOCOL_VERSION"
    fi
}

build_payload() {
    local input="$1"
    local event="$2"
    shift 2

    local protocol_version
    protocol_version=$(negotiate_protocol_version)

    local session_id cwd project
    session_id=$(echo "$input" | jq -r '.session_id // .sessionId // empty' 2>/dev/null)
    cwd=$(echo "$input" | jq -r '.cwd // empty' 2>/dev/null)
    project=""
    if [ -n "$cwd" ]; then
        project=$(basename "$cwd")
    fi

    # Extra args should be jq flag pairs: --arg key "value" or --argjson key '...'
    jq -nc \
        --argjson v "$protocol_version" \
        --arg agent "grok" \
        --arg event "$event" \
        --arg session_id "$session_id" \
        --arg cwd "$cwd" \
        --arg project "$project" \
        "$@" \
        '{v:$v, agent:$agent, event:$event, session_id:$session_id, cwd:$cwd, project:$project} + $ARGS.named'
}
