#!/usr/bin/env bash
# StopFailure — turn ended due to an API / runtime error.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/should-use-structured.sh"

if ! should_use_structured; then
    exit 0
fi

source "$SCRIPT_DIR/build-payload.sh"

INPUT=$(cat)

ERROR_TYPE=$(echo "$INPUT" | jq -r '.error // empty' 2>/dev/null)
ERROR_MESSAGE=$(echo "$INPUT" | jq -r '.last_assistant_message // .lastAssistantMessage // .errorDetails // empty' 2>/dev/null)
QUERY=$(echo "$INPUT" | jq -r '.prompt // .query // empty' 2>/dev/null)

if [ -n "$QUERY" ] && [ ${#QUERY} -gt 200 ]; then
    QUERY="${QUERY:0:197}..."
fi
if [ -n "$ERROR_MESSAGE" ] && [ ${#ERROR_MESSAGE} -gt 200 ]; then
    ERROR_MESSAGE="${ERROR_MESSAGE:0:197}..."
fi

BODY=$(build_payload "$INPUT" "stop_failure" \
    --arg query "$QUERY" \
    --arg response "$ERROR_MESSAGE" \
    --arg error_type "$ERROR_TYPE")

"$SCRIPT_DIR/warp-notify.sh" "warp://cli-agent" "$BODY"
