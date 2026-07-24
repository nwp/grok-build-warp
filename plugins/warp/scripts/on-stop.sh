#!/usr/bin/env bash
# Stop — task complete notification.
# Grok provides lastAssistantMessage; do not scrape Claude-style JSONL transcripts.
# Never write to stdout (Grok parses Stop stdout for stop-decision control).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/should-use-structured.sh"

if ! should_use_structured; then
    exit 0
fi

source "$SCRIPT_DIR/build-payload.sh"

INPUT=$(cat)

# Skip while a stop gate is already active (continuation loop).
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // .stopHookActive // false' 2>/dev/null)
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
    exit 0
fi

# Skip session-end observe fires (channel close / shutdown).
REASON=$(echo "$INPUT" | jq -r '.reason // empty' 2>/dev/null)
case "$REASON" in
    channel_closed|shutdown) exit 0 ;;
esac

QUERY=$(echo "$INPUT" | jq -r '.prompt // .query // empty' 2>/dev/null)
RESPONSE=$(echo "$INPUT" | jq -r '.last_assistant_message // .lastAssistantMessage // empty' 2>/dev/null)

if [ -n "$QUERY" ] && [ ${#QUERY} -gt 200 ]; then
    QUERY="${QUERY:0:197}..."
fi
if [ -n "$RESPONSE" ] && [ ${#RESPONSE} -gt 200 ]; then
    RESPONSE="${RESPONSE:0:197}..."
fi

BODY=$(build_payload "$INPUT" "stop" \
    --arg query "$QUERY" \
    --arg response "$RESPONSE")

"$SCRIPT_DIR/warp-notify.sh" "warp://cli-agent" "$BODY"
