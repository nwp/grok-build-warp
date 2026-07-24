#!/usr/bin/env bash
# Tests for the Warp Grok Build plugin hook scripts.
#
# Usage: ./tests/test-hooks.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)"
PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$SCRIPT_DIR/build-payload.sh"

PASSED=0
FAILED=0

assert_eq() {
    local test_name="$1"
    local expected="$2"
    local actual="$3"
    if [ "$expected" = "$actual" ]; then
        echo "  ✓ $test_name"
        PASSED=$((PASSED + 1))
    else
        echo "  ✗ $test_name"
        echo "    expected: $expected"
        echo "    actual:   $actual"
        FAILED=$((FAILED + 1))
    fi
}

assert_json_field() {
    local test_name="$1"
    local json="$2"
    local field="$3"
    local expected="$4"
    local actual
    actual=$(echo "$json" | jq -r "$field" 2>/dev/null)
    assert_eq "$test_name" "$expected" "$actual"
}

assert_contains() {
    local test_name="$1"
    local haystack="$2"
    local needle="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        echo "  ✓ $test_name"
        PASSED=$((PASSED + 1))
    else
        echo "  ✗ $test_name"
        echo "    expected to contain: $needle"
        echo "    actual:   $haystack"
        FAILED=$((FAILED + 1))
    fi
}

echo "=== build-payload.sh ==="

echo ""
echo "--- Common fields (snake_case) ---"
PAYLOAD=$(build_payload '{"session_id":"sess-123","cwd":"/Users/alice/my-project"}' "stop")
assert_json_field "v is 1" "$PAYLOAD" ".v" "1"
assert_json_field "agent is grok" "$PAYLOAD" ".agent" "grok"
assert_json_field "event is stop" "$PAYLOAD" ".event" "stop"
assert_json_field "session_id extracted" "$PAYLOAD" ".session_id" "sess-123"
assert_json_field "cwd extracted" "$PAYLOAD" ".cwd" "/Users/alice/my-project"
assert_json_field "project is basename of cwd" "$PAYLOAD" ".project" "my-project"

echo ""
echo "--- Common fields (camelCase / Grok) ---"
PAYLOAD=$(build_payload '{"sessionId":"sess-camel","cwd":"/tmp/gproj"}' "prompt_submit")
assert_json_field "sessionId maps to session_id" "$PAYLOAD" ".session_id" "sess-camel"
assert_json_field "cwd from camelCase envelope" "$PAYLOAD" ".cwd" "/tmp/gproj"
assert_json_field "project from camelCase cwd" "$PAYLOAD" ".project" "gproj"
assert_json_field "agent remains grok" "$PAYLOAD" ".agent" "grok"

echo ""
echo "--- Common fields with missing data ---"
PAYLOAD=$(build_payload '{}' "stop")
assert_json_field "empty session_id" "$PAYLOAD" ".session_id" ""
assert_json_field "empty cwd" "$PAYLOAD" ".cwd" ""
assert_json_field "empty project" "$PAYLOAD" ".project" ""

echo ""
echo "--- Extra args are merged ---"
PAYLOAD=$(build_payload '{"sessionId":"s1","cwd":"/tmp/proj"}' "stop" \
    --arg query "hello" \
    --arg response "world")
assert_json_field "query merged" "$PAYLOAD" ".query" "hello"
assert_json_field "response merged" "$PAYLOAD" ".response" "world"
assert_json_field "common fields still present" "$PAYLOAD" ".session_id" "s1"

echo ""
echo "--- Stop event ---"
PAYLOAD=$(build_payload '{"sessionId":"s1","cwd":"/tmp/proj"}' "stop" \
    --arg query "write a haiku" \
    --arg response "Memory is safe, the borrow checker stands guard")
assert_json_field "event is stop" "$PAYLOAD" ".event" "stop"
assert_json_field "query present" "$PAYLOAD" ".query" "write a haiku"
assert_json_field "response present" "$PAYLOAD" ".response" "Memory is safe, the borrow checker stands guard"

echo ""
echo "--- Session start with plugin_version ---"
PAYLOAD=$(build_payload '{"sessionId":"s1","cwd":"/tmp/proj"}' "session_start" \
    --arg plugin_version "1.0.0")
assert_json_field "event is session_start" "$PAYLOAD" ".event" "session_start"
assert_json_field "plugin_version present" "$PAYLOAD" ".plugin_version" "1.0.0"
assert_json_field "agent is grok on session_start" "$PAYLOAD" ".agent" "grok"

echo ""
echo "--- Idle prompt event ---"
PAYLOAD=$(build_payload '{"sessionId":"s1","cwd":"/tmp/proj"}' "idle_prompt" \
    --arg summary "Grok is waiting for your input")
assert_json_field "event is idle_prompt" "$PAYLOAD" ".event" "idle_prompt"
assert_json_field "summary present" "$PAYLOAD" ".summary" "Grok is waiting for your input"

echo ""
echo "--- Tool complete ---"
PAYLOAD=$(build_payload '{"sessionId":"s1","cwd":"/tmp/proj"}' "tool_complete" \
    --arg tool_name "run_terminal_command")
assert_json_field "event is tool_complete" "$PAYLOAD" ".event" "tool_complete"
assert_json_field "tool_name present" "$PAYLOAD" ".tool_name" "run_terminal_command"

echo ""
echo "--- Stop failure ---"
PAYLOAD=$(build_payload '{"sessionId":"s1","cwd":"/tmp/proj"}' "stop_failure" \
    --arg error_type "rate_limit" \
    --arg response "Too many requests")
assert_json_field "event is stop_failure" "$PAYLOAD" ".event" "stop_failure"
assert_json_field "error_type present" "$PAYLOAD" ".error_type" "rate_limit"

echo ""
echo "--- JSON special characters in values ---"
PAYLOAD=$(build_payload '{"sessionId":"s1","cwd":"/tmp/proj"}' "stop" \
    --arg query 'what does "hello world" mean?' \
    --arg response 'It means greeting. Use: printf("hello")')
assert_json_field "quotes in query preserved" "$PAYLOAD" ".query" 'what does "hello world" mean?'
assert_json_field "parens in response preserved" "$PAYLOAD" ".response" 'It means greeting. Use: printf("hello")'

echo ""
echo "--- Protocol version negotiation ---"

unset WARP_CLI_AGENT_PROTOCOL_VERSION
PAYLOAD=$(build_payload '{"sessionId":"s1","cwd":"/tmp"}' "stop")
assert_json_field "defaults to v1 when env var absent" "$PAYLOAD" ".v" "1"

export WARP_CLI_AGENT_PROTOCOL_VERSION=1
PAYLOAD=$(build_payload '{"sessionId":"s1","cwd":"/tmp"}' "stop")
assert_json_field "v1 when warp declares 1" "$PAYLOAD" ".v" "1"

export WARP_CLI_AGENT_PROTOCOL_VERSION=99
PAYLOAD=$(build_payload '{"sessionId":"s1","cwd":"/tmp"}' "stop")
assert_json_field "capped to plugin current when warp is ahead" "$PAYLOAD" ".v" "1"

PLUGIN_CURRENT_PROTOCOL_VERSION=5
export WARP_CLI_AGENT_PROTOCOL_VERSION=3
PAYLOAD=$(build_payload '{"sessionId":"s1","cwd":"/tmp"}' "stop")
assert_json_field "uses warp version when plugin is ahead" "$PAYLOAD" ".v" "3"
PLUGIN_CURRENT_PROTOCOL_VERSION=1

unset WARP_CLI_AGENT_PROTOCOL_VERSION

echo ""
echo "=== should-use-structured.sh ==="

source "$SCRIPT_DIR/should-use-structured.sh"

echo ""
echo "--- No protocol version → legacy ---"
unset WARP_CLI_AGENT_PROTOCOL_VERSION
unset WARP_CLIENT_VERSION
should_use_structured
assert_eq "no protocol version returns false" "1" "$?"

echo ""
echo "--- Protocol set, no client version → legacy ---"
export WARP_CLI_AGENT_PROTOCOL_VERSION=1
unset WARP_CLIENT_VERSION
should_use_structured
assert_eq "missing WARP_CLIENT_VERSION returns false" "1" "$?"

echo ""
echo "--- Protocol set, dev version → always structured ---"
export WARP_CLI_AGENT_PROTOCOL_VERSION=1
export WARP_CLIENT_VERSION="v0.2026.03.30.08.43.dev_00"
should_use_structured
assert_eq "dev version returns true" "0" "$?"

echo ""
echo "--- Protocol set, broken stable version → legacy ---"
export WARP_CLIENT_VERSION="v0.2026.03.25.08.24.stable_05"
should_use_structured
assert_eq "exact broken stable version returns false" "1" "$?"

echo ""
echo "--- Protocol set, newer stable version → structured ---"
export WARP_CLIENT_VERSION="v0.2026.04.01.08.00.stable_00"
should_use_structured
assert_eq "newer stable version returns true" "0" "$?"

echo ""
echo "--- Protocol set, broken preview version → legacy ---"
export WARP_CLIENT_VERSION="v0.2026.03.25.08.24.preview_05"
should_use_structured
assert_eq "exact broken preview version returns false" "1" "$?"

echo ""
echo "--- Protocol set, newer preview version → structured ---"
export WARP_CLIENT_VERSION="v0.2026.04.01.08.00.preview_00"
should_use_structured
assert_eq "newer preview version returns true" "0" "$?"

unset WARP_CLI_AGENT_PROTOCOL_VERSION
unset WARP_CLIENT_VERSION

echo ""
echo "=== emit-terminal-sequence.sh ==="

source "$SCRIPT_DIR/emit-terminal-sequence.sh"

STDOUT_CAPTURE=$(
    emit_terminal_sequence "osc-body" 2>/tmp/warp-emit-test-stderr.$$
    true
)
STDERR_CAPTURE=$(cat /tmp/warp-emit-test-stderr.$$ 2>/dev/null || true)
rm -f /tmp/warp-emit-test-stderr.$$

assert_eq "emit writes nothing to stdout" "" "$STDOUT_CAPTURE"
assert_eq "emit writes sequence to stderr" "osc-body" "$STDERR_CAPTURE"

echo ""
echo "=== Hook integration (structured enabled) ==="

export WARP_CLI_AGENT_PROTOCOL_VERSION=1
export WARP_CLIENT_VERSION="v0.2026.04.01.08.00.stable_00"
export GROK_PLUGIN_ROOT="$PLUGIN_DIR"

echo ""
echo "--- SessionStart OSC ---"
ERR=$(printf '%s' '{"hookEventName":"SessionStart","sessionId":"t1","cwd":"/tmp/proj"}' \
    | bash "$SCRIPT_DIR/on-session-start.sh" 2>&1 >/tmp/warp-ss-stdout.$$)
SS_STDOUT=$(cat /tmp/warp-ss-stdout.$$ 2>/dev/null || true)
rm -f /tmp/warp-ss-stdout.$$

assert_eq "session_start stdout empty" "" "$SS_STDOUT"
assert_contains "session_start OSC sentinel" "$ERR" "warp://cli-agent"
assert_contains "session_start OSC agent grok" "$ERR" '"agent":"grok"'
assert_contains "session_start OSC event" "$ERR" '"event":"session_start"'
assert_contains "session_start OSC plugin_version" "$ERR" '"plugin_version":"1.0.0"'
assert_contains "session_start OSC session_id" "$ERR" '"session_id":"t1"'

echo ""
echo "--- Stop OSC (camelCase + lastAssistantMessage) ---"
ERR=$(printf '%s' '{"hookEventName":"Stop","sessionId":"t2","cwd":"/tmp/proj","reason":"end_turn","lastAssistantMessage":"All done.","stopHookActive":false}' \
    | bash "$SCRIPT_DIR/on-stop.sh" 2>&1 >/tmp/warp-stop-stdout.$$)
STOP_STDOUT=$(cat /tmp/warp-stop-stdout.$$ 2>/dev/null || true)
rm -f /tmp/warp-stop-stdout.$$

assert_eq "stop stdout empty" "" "$STOP_STDOUT"
assert_contains "stop OSC agent grok" "$ERR" '"agent":"grok"'
assert_contains "stop OSC event" "$ERR" '"event":"stop"'
assert_contains "stop OSC response" "$ERR" '"response":"All done."'

echo ""
echo "--- Stop skips session-end reason ---"
ERR=$(printf '%s' '{"sessionId":"t3","cwd":"/tmp","reason":"shutdown"}' \
    | bash "$SCRIPT_DIR/on-stop.sh" 2>&1)
assert_eq "stop skips shutdown (no OSC)" "" "$ERR"

echo ""
echo "--- Stop skips stopHookActive ---"
ERR=$(printf '%s' '{"sessionId":"t4","cwd":"/tmp","stopHookActive":true,"reason":"end_turn","lastAssistantMessage":"x"}' \
    | bash "$SCRIPT_DIR/on-stop.sh" 2>&1)
assert_eq "stop skips stopHookActive" "" "$ERR"

echo ""
echo "--- Prompt submit ---"
ERR=$(printf '%s' '{"sessionId":"t5","cwd":"/tmp","prompt":"hello grok"}' \
    | bash "$SCRIPT_DIR/on-prompt-submit.sh" 2>&1)
assert_contains "prompt_submit event" "$ERR" '"event":"prompt_submit"'
assert_contains "prompt_submit query" "$ERR" '"query":"hello grok"'

echo ""
echo "--- Structured disabled exits silently ---"
unset WARP_CLI_AGENT_PROTOCOL_VERSION
unset WARP_CLIENT_VERSION
for HOOK in on-session-start.sh on-prompt-submit.sh on-stop.sh on-post-tool-use.sh on-notification.sh on-stop-failure.sh; do
    printf '%s' '{}' | bash "$SCRIPT_DIR/$HOOK" >/dev/null 2>&1
    assert_eq "$HOOK exits 0 without protocol version" "0" "$?"
done

# Clean up
unset WARP_CLI_AGENT_PROTOCOL_VERSION
unset WARP_CLIENT_VERSION
unset GROK_PLUGIN_ROOT

echo ""
echo "=== Results: $PASSED passed, $FAILED failed ==="

if [ "$FAILED" -gt 0 ]; then
    exit 1
fi
