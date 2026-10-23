#!/usr/bin/env bash
#
# run_vhs.sh - Generate the demo GIFs from the .tape files with vhs
#
# Records one or every .tape file in this directory. The tapes start a real
# session with the repo's claude-local.sh, so Ollama must be reachable with the
# configured models installed, and claude must be logged in. Recording from
# inside a Claude Code session is fine: the nested-session markers Claude Code
# exports are cleared first, so the recorded session does not warn about them.
#
# Author: Alister Lewis-Bowen <alister@lewis-bowen.org>
# Version: 1.0.0
# Date: 2026-10-23
# License: MIT
#
# Usage: examples/run_vhs.sh [tape]
#   tape  A .tape file to record, or omit to record every *.tape here except config.tape
#
# Dependencies: bash 4.0+, vhs (https://github.com/charmbracelet/vhs)
#
# Exit codes:
#   0 - Success
#   1 - vhs not installed

set -euo pipefail

tape="${1:-all}"

if ! command -v vhs >/dev/null 2>&1; then
  echo "vhs is not installed. Install it (brew install vhs) or see https://github.com/charmbracelet/vhs" >&2
  exit 1
fi

# https://github.com/charmbracelet/vhs/issues/419
unset PROMPT_COMMAND

# Clear the markers a parent Claude Code session exports, so the recorded session
# starts clean instead of treating itself as a child session.
for name in $(compgen -A variable | grep -E '^(CLAUDECODE|CLAUDE_CODE_|CLAUDE_PID|CLAUDE_EFFORT)' || true); do
  unset "$name"
done

cd "$(dirname "${BASH_SOURCE[0]}")"

if [[ "$tape" != "all" ]]; then
  vhs "$tape"
else
  for tape in *.tape; do
    # Skip the shared configuration file that the others source
    [[ "$tape" == "config.tape" ]] && continue
    vhs "$tape"
  done
fi
