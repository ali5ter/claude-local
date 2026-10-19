#!/usr/bin/env bash
#
# smoke.sh - Exercise claude-local.sh without a model server or Claude Code
#
# Runs the parts of the script that need no network: --help, --version, the
# config-file precedence, and the unreachable-server and bad-option paths. Uses a
# port nothing listens on, so no real Ollama is contacted.
#
# Author: Alister Lewis-Bowen <alister@lewis-bowen.org>
# Version: 1.0.0
# Date: 2026-10-19
# License: MIT
#
# Usage: tests/smoke.sh
#
# Dependencies: bash 4.0+, curl, jq
#
# Exit codes:
#   0 - Every check passed
#   1 - A check failed

set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/claude-local.sh"
DEAD_URL="http://127.0.0.1:9"
FAILED=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Run a check and report it.
# @param $1  Description
# @param $2  Expected exit code
# @param $3  Regex the combined output must match
# @param $@  Command to run
# @return 0; records a failure in FAILED
check() {
  local desc="$1" want_rc="$2" want_re="$3" rc=0 out
  shift 3
  out="$("$@" 2>&1)" || rc=$?
  if [[ "$rc" == "$want_rc" && "$out" =~ $want_re ]]; then
    echo "ok   $desc"
  else
    echo "FAIL $desc (exit $rc, wanted $want_rc; output: $out)"
    FAILED=1
  fi
}

# Dependencies the script needs even for the offline paths, so a missing one fails here, not in a check.
for cmd in curl jq; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "FAIL missing $cmd"; exit 1; }
done

# A fake claude on PATH so the dependency check passes; it never runs because the server is unreachable.
printf '#!/usr/bin/env bash\nexit 0\n' >"$TMP/claude"
chmod +x "$TMP/claude"
export PATH="$TMP:$PATH"
export CLAUDE_LOCAL_CONFIG="$TMP/none"

check "--help prints usage" 0 'Usage: claude-local' "$SCRIPT" --help
check "--version prints the version" 0 '^claude-local [0-9]+\.[0-9]+\.[0-9]+$' "$SCRIPT" --version
check "unknown option is rejected" 1 'Unknown option: --bogus' "$SCRIPT" --bogus
check "--model without a value is rejected" 1 '--model needs a value' "$SCRIPT" --model
check "--url without a value is rejected" 1 '--url needs a value' "$SCRIPT" --url ""
if curl -sf --max-time 2 http://localhost:11434/api/version >/dev/null; then
  echo "skip unreachable default server (an Ollama answers on localhost:11434)"
else
  check "unreachable default server says how to configure" 1 'no OLLAMA_HOST_URL is set' env -u OLLAMA_HOST_URL "$SCRIPT"
fi
check "unreachable configured server is reported" 1 "not reachable at $DEAD_URL" "$SCRIPT" --url "$DEAD_URL"
check "unreachable server from the environment is reported" 1 "not reachable at $DEAD_URL" \
  env OLLAMA_HOST_URL="$DEAD_URL" "$SCRIPT"

printf 'OLLAMA_HOST_URL=%s\n' "$DEAD_URL" >"$TMP/env"
check "config file sets the server" 1 "not reachable at $DEAD_URL" env CLAUDE_LOCAL_CONFIG="$TMP/env" "$SCRIPT"
check "environment beats the config file" 1 'not reachable at http://127.0.0.1:10' \
  env CLAUDE_LOCAL_CONFIG="$TMP/env" OLLAMA_HOST_URL=http://127.0.0.1:10 "$SCRIPT"
check "flag beats the environment" 1 'not reachable at http://127.0.0.1:11' \
  env CLAUDE_LOCAL_CONFIG="$TMP/env" OLLAMA_HOST_URL=http://127.0.0.1:10 "$SCRIPT" --url http://127.0.0.1:11

exit "$FAILED"
