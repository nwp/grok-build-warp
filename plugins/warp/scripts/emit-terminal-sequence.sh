#!/usr/bin/env bash
# Emits an OSC terminal escape sequence for Grok Build hooks.
#
# Grok Stop hooks parse stdout for stop-decision JSON, so OSC must never go
# to stdout. The proven path (Warp interim file-write bridge) is stderr only.
#
# Usage:
#   source "$SCRIPT_DIR/emit-terminal-sequence.sh"
#   SEQ=$(printf '\033]777;notify;%s;%s\007' "$TITLE" "$BODY")
#   emit_terminal_sequence "$SEQ"

emit_terminal_sequence() {
    local seq="$1"
    [ -z "$seq" ] && return 0

    # stderr reaches the PTY for Grok hook processes; never dual-write to
    # /dev/tty (would double-fire OSC and can error in headless/CI).
    printf '%s' "$seq" >&2
    return 0
}
