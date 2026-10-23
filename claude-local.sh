#!/usr/bin/env bash
#
# claude-local.sh - Start Claude Code against a local Ollama model
#
# Runs one Claude Code session with its model requests sent to Ollama instead of
# Anthropic. Plain `claude` is untouched: everything here is an environment
# variable set for this one process, and nothing is written to any configuration
# file, so ~/.claude and its symlinks are left exactly as they are.
#
# Claude Code picks its backend from environment variables, so a local session
# needs several set together and a few easy to forget:
#   - the base URL, so requests go to Ollama (no token: Ollama needs none, and a
#     placeholder makes Claude Code warn that its claude.ai connectors are disabled)
#   - every model alias (haiku, sonnet, opus, fable) mapped to the local model,
#     because Claude Code makes background calls to a small model by name and
#     Ollama has no model called that
#   - telemetry, error reporting, autoupdate and other non-essential traffic off,
#     so a local session does not still contact vendors (measured: it does by
#     default)
#   - the real context window (CLAUDE_CODE_MAX_CONTEXT_TOKENS): Claude Code assumes
#     200k for a model it does not know, so without this it would not compact before
#     Ollama silently truncated at its own, smaller window
#   - the 1M-context variant off (CLAUDE_CODE_DISABLE_1M_CONTEXT): the "default" model
#     and the opusplan setting resolve to a "[1m]" model that Claude Code treats as a
#     one-million-token window, ignoring the variable above
# Your real configuration (CLAUDE.md, skills, hooks) loads as usual, which is the
# point: it is how a real session behaves.
#
# The model server need not be on this machine: set OLLAMA_HOST_URL to another
# machine's address (over the LAN or a VPN) and only inference moves; Claude Code,
# its tools and the files it edits stay here. The server's context window cannot be
# read from a remote process, so set OLLAMA_CONTEXT_LENGTH to match the server.
#
# With --switchable, two models are available in one session. Claude Code's /model
# command only switches between its aliases, so sonnet and haiku map to the main model
# and opus (and fable) map to a second, slower model for writing and judgement-heavy
# work. Type /model opus to switch to it and /model sonnet to switch back. Each switch
# makes Ollama load the other model and read the conversation again, so a long session
# pauses while that happens. Without the flag every alias is the one model.
#
# The /model picker is given its own lineup (the modelPicker setting, passed with
# --settings so nothing is written to disk): one row per local model, titled with the
# real model name and a short use-case description, replacing Anthropic's rows. The
# ANTHROPIC_DEFAULT_*_MODEL_NAME variables are set as well, but on Claude Code 2.1.292
# with a Claude subscription login they no longer reached the picker; the lineup does.
# Fast mode is turned off too, since /fast would route to an Anthropic model.
#
# With --audit, connections made by the session are sampled and any endpoint other
# than loopback and the model server is listed when it exits. That is evidence, not
# proof: sampling every 0.3s can miss very short connections.
#
# Settings come from flags, then the environment, then the config file
# ($CLAUDE_LOCAL_CONFIG, default ~/.config/claude-local/env; see env.template).
#
# Author: Alister Lewis-Bowen <alister@lewis-bowen.org>
# Version: 1.2.0
# Date: 2026-10-23
# License: MIT
#
# Usage: claude-local [-u|--url URL] [-m|--model MODEL] [-s|--switchable] [-H|--hard-model MODEL]
#                     [-a|--audit] [-e|--enable-auto-mode] [-n|--dry-run] [-V|--version] [-h|--help]
#                     [-- claude args ...]
#
#   -u, --url URL             Ollama server (default: OLLAMA_HOST_URL, else http://localhost:11434)
#   -m, --model M             Model for the session (default: CLAUDE_LOCAL_MODEL)
#   -s, --switchable          Make /model opus switch to the second model (CLAUDE_LOCAL_HARD_MODEL)
#   -H, --hard-model M        Use M as the second model; implies --switchable
#   -a, --audit               List connections beyond loopback and the model server on exit (needs lsof)
#   -e, --enable-auto-mode    Enable Claude Code auto-mode (Shift+Tab to toggle)
#   -n, --dry-run             Print the environment and command a session would start with, without
#                             contacting the server or starting Claude Code
#   -V, --version             Print the version and exit
#
#   Everything after -- is passed to claude, for example:
#     claude-local --audit -- -p "Reply with exactly: ok"
#
# Dependencies: bash 4.0+, claude, curl, jq; pfb for nicer output; lsof only with --audit
#
# Exit codes:
#   Claude's own exit status on a normal run
#   1 - Missing dependency, Ollama unreachable, or the model is not installed

set -euo pipefail

VERSION="1.2.0"
CONFIG_FILE="${CLAUDE_LOCAL_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/claude-local/env}"

# Settings the config file may set. The environment wins over the file, so the
# values present before the file is read are kept.
ENV_URL="${OLLAMA_HOST_URL:-}"
ENV_CONTEXT="${OLLAMA_CONTEXT_LENGTH:-}"
ENV_MODEL="${CLAUDE_LOCAL_MODEL:-}"
ENV_HARD_MODEL="${CLAUDE_LOCAL_HARD_MODEL:-}"
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck disable=SC1090  # user-supplied file, not present at lint time
  source "$CONFIG_FILE"
fi
OLLAMA_HOST_URL="${ENV_URL:-${OLLAMA_HOST_URL:-}}"
OLLAMA_CONTEXT_LENGTH="${ENV_CONTEXT:-${OLLAMA_CONTEXT_LENGTH:-}}"
CLAUDE_LOCAL_MODEL="${ENV_MODEL:-${CLAUDE_LOCAL_MODEL:-qwen3.6:35b-a3b-coding}}"
CLAUDE_LOCAL_HARD_MODEL="${ENV_HARD_MODEL:-${CLAUDE_LOCAL_HARD_MODEL:-qwen3.8:27b}}"

# Remember whether the server address was configured, so an unreachable default can say how to configure it.
URL_CONFIGURED=0
[[ -n "$OLLAMA_HOST_URL" ]] && URL_CONFIGURED=1
OLLAMA_HOST_URL="${OLLAMA_HOST_URL:-http://localhost:11434}"

AUDIT=0
AUDIT_LOG=""
SAMPLER_PID=""
AUTO_MODE=0
DRY_RUN=0

# Minimal stand-in for pfb (https://github.com/ali5ter/pfb) when it is not installed,
# covering the calls this script makes. Install pfb for the real thing.
if ! command -v pfb >/dev/null 2>&1; then
  pfb() {
    local kind="$1" msg="${2:-}" icon="${3:-}"
    case "$kind" in
      heading) printf '\n%s %s\n' "${icon:-#}" "$msg" ;;
      subheading) printf '   %s\n' "$msg" ;;
      success) printf '   ✓ %s\n' "$msg" ;;
      info) printf '   • %s\n' "$msg" ;;
      warn) printf '   ! %s\n' "$msg" >&2 ;;
      error) printf '   ✗ %s\n' "$msg" >&2 ;;
      *) printf '   %s\n' "$msg" ;;
    esac
  }
fi

# Print usage text.
# @return 0
usage() {
  sed -n '/^# Usage:/,/^# Dependencies:/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//'
}

# Print the command that installs a package on this system.
# @param $1  Package name
# @return 0; prints "sudo apt install X" on Debian-based systems, "brew install X" with Homebrew, else a generic hint
install_hint() {
  if [[ "$1" == pfb ]]; then
    echo "brew install ali5ter/tap/pfb, or see https://github.com/ali5ter/pfb"
  elif command -v apt-get >/dev/null 2>&1; then
    echo "sudo apt install $1"
  elif command -v brew >/dev/null 2>&1; then
    echo "brew install $1"
  else
    echo "install $1 with your package manager"
  fi
}

# Print the host part of OLLAMA_HOST_URL (no scheme, port or path).
# @return 0; prints the host
server_host() {
  local rest="${OLLAMA_HOST_URL#*://}"
  rest="${rest%%/*}"
  if [[ "$rest" == \[* ]]; then
    rest="${rest#\[}"
    echo "${rest%%]*}"
  else
    echo "${rest%%:*}"
  fi
}

# Resolve a host name or address to an IPv4 address.
# @param $1  Host name or IPv4 address
# @return 0; prints the address, or nothing if it cannot be resolved
resolve_ip() {
  local host="$1"
  if [[ "$host" =~ ^[0-9]+(\.[0-9]+){3}$ ]]; then
    echo "$host"
  elif command -v getent >/dev/null 2>&1; then
    getent ahostsv4 "$host" 2>/dev/null | awk 'NR==1 {print $1}' || true
  else
    dscacheutil -q host -a name "$host" 2>/dev/null | awk '/^ip_address:/ {print $2; exit}' || true
  fi
}

# Print this machine's IPv4 addresses, one per line (ip on Linux, ifconfig on macOS).
# @return 0; prints nothing if neither tool is available
local_addresses() {
  if command -v ip >/dev/null 2>&1; then
    ip -4 -o addr show 2>/dev/null | awk '{split($4, a, "/"); print a[1]}'
  else
    ifconfig 2>/dev/null | awk '$1 == "inet" {print $2}'
  fi
}

# Check whether the model server runs on this machine.
# @return 0 if OLLAMA_HOST_URL names loopback or one of this machine's own addresses, 1 otherwise
server_is_local() {
  local host ip
  host="$(server_host)"
  case "$host" in localhost | 127.* | ::1) return 0 ;; esac
  ip="$(resolve_ip "$host")"
  [[ -n "$ip" ]] || return 1
  [[ "$ip" == 127.* ]] && return 0
  local_addresses | grep -qxF "$ip"
}

# Print the distinct remote addresses in a connection log, leaving out loopback and
# the model server, which are expected traffic.
# @param $1  File of "local->remote" rows written by a connection sampler
# @return 0; prints a comma-separated list, or nothing
unexpected_endpoints() {
  local allowed
  allowed="$(resolve_ip "$(server_host)")"
  awk -F'->' 'NF > 1 {sub(/:[0-9]+$/, "", $2); print $2}' "$1" \
    | grep -vE '^(127\.0\.0\.1|\[::1\]|localhost)$' | grep -vxF "${allowed:-none}" | sort -u | paste -sd, - || true
}

# Print the models installed on the server, one tag per line.
# @return 0; prints nothing if the server cannot be read
installed_models() {
  curl -sf --connect-timeout 5 --max-time 10 "$OLLAMA_HOST_URL/api/tags" | jq -r '.models[].name' 2>/dev/null || true
}

# Verify required commands exist, Ollama answers, and every named model is installed.
# lsof is needed only for --audit, so a machine without it can still start a session.
# @param $@  One or more model tags
# @return 0 on success; exits 1 with an actionable message otherwise
check_prerequisites() {
  local cmd msg
  local -a needed=(claude curl jq)
  ((AUDIT)) && needed+=(lsof)
  for cmd in "${needed[@]}"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      msg="Missing dependency: $cmd. Install it ($(install_hint "$cmd"))"
      [[ "$cmd" == lsof ]] && msg+=", or drop --audit"
      pfb error "$msg and re-run."
      exit 1
    fi
  done
  if ! curl -sf --connect-timeout 5 --max-time 10 "$OLLAMA_HOST_URL/api/version" >/dev/null; then
    if ((URL_CONFIGURED)); then
      pfb error "Ollama is not reachable at $OLLAMA_HOST_URL. Check that the server is running and bound to that address, and the network between you."
    else
      pfb error "Ollama is not reachable at the default $OLLAMA_HOST_URL and no OLLAMA_HOST_URL is set."
      pfb subheading "For Ollama on this machine: start it (ollama serve, or the Ollama app) and re-run."
      pfb subheading "For a server elsewhere: pass --url, or set OLLAMA_HOST_URL in $CONFIG_FILE (see env.template)."
    fi
    exit 1
  fi
  local model tag installed
  installed="$(installed_models)"
  for model in "$@"; do
    tag="$model"
    [[ "$tag" == *:* ]] || tag="$tag:latest"
    if ! grep -qxF "$tag" <<<"$installed"; then
      pfb error "Model $model is not installed on $(server_host). Pull it with 'ollama pull $model' or choose one with --model."
      if [[ -n "$installed" ]]; then
        pfb subheading "Installed: $(paste -sd, - <<<"$installed" | sed 's/,/, /g')"
      fi
      exit 1
    fi
  done
}

# Print the /model picker lineup as a JSON settings object: one row per local model,
# titled with the model name, replacing Claude Code's built-in rows.
# @param $1  Main model and its description ($2)
# @param $3  Second model and its description ($4); omitted from the lineup when it equals $1
# @return 0; prints compact JSON
picker_settings() {
  jq -cn --arg m "$1" --arg md "$2" --arg o "$3" --arg od "$4" '{
    modelPicker: {
      options: ([{model: "sonnet", label: $m, description: $md}]
        + (if $o != $m then [{model: "opus", label: $o, description: $od}] else [] end)),
      replaceBuiltInOptions: true
    }
  }'
}

# Print the context window requests get from the Ollama server.
# Order: OLLAMA_CONTEXT_LENGTH, then the local server's environment (only when the server
# is on this machine, so another machine's Ollama is never mistaken for it), else 32768.
# @return 0; prints the token count
server_context_length() {
  if [[ -n "$OLLAMA_CONTEXT_LENGTH" ]]; then
    echo "$OLLAMA_CONTEXT_LENGTH"
    return 0
  fi
  local pid value=""
  if server_is_local; then
    pid="$(pgrep -f 'ollama serve' | head -1 || true)"
    if [[ -n "$pid" ]]; then
      value="$(ps eww -p "$pid" 2>/dev/null | tr ' ' '\n' | sed -n 's/^OLLAMA_CONTEXT_LENGTH=//p' | head -1 || true)"
    fi
  else
    pfb warn "Cannot read the context window of the remote server $(server_host); assuming 32768."
    pfb warn "Set OLLAMA_CONTEXT_LENGTH in $CONFIG_FILE to the value the server runs with."
  fi
  echo "${value:-32768}"
}

# Sample the session's network connections into AUDIT_LOG until this shell exits.
# Watches the whole process group, so child processes of claude are included.
# @param $1  PID whose process group is sampled
# @side_effects Appends "local->remote" rows to AUDIT_LOG every 0.3s
sample_session() {
  local parent="$1" pgid
  pgid="$(ps -o pgid= -p "$parent" | tr -d ' ')"
  while kill -0 "$parent" 2>/dev/null; do
    lsof -nP -a -g "$pgid" -i 2>/dev/null | awk 'NR>1 {print $9}' >>"$AUDIT_LOG" || true
    sleep 0.3
  done
}

# Stop the sampler and print the distinct endpoints it saw other than loopback and
# the model server (EXIT trap).
# @side_effects Removes the sampler process; prints a summary when auditing
finish_audit() {
  if [[ -n "$SAMPLER_PID" ]]; then kill "$SAMPLER_PID" 2>/dev/null || true; fi
  ((AUDIT)) || return 0
  local external
  external="$(unexpected_endpoints "$AUDIT_LOG")"
  echo
  if [[ -z "$external" ]]; then
    pfb success "Network audit: no connections beyond loopback and the model server (log: $AUDIT_LOG)"
  else
    pfb warn "Network audit: connections to $external (log: $AUDIT_LOG)"
  fi
}

# Exit when a flag that takes a value has none.
# @param $1  The flag
# @param $2  Its value, if any
# @return 0 when a non-empty value follows; exits 1 with a message otherwise
need_value() {
  if (($# < 2)) || [[ -z "$2" ]]; then
    pfb error "$1 needs a value."
    exit 1
  fi
}

# Entry point.
# @param $@  Flags, then optionally -- and arguments for claude
main() {
  local model="$CLAUDE_LOCAL_MODEL" hard_model="$CLAUDE_LOCAL_HARD_MODEL" switchable=0
  local -a claude_args=()
  while (($#)); do
    case "$1" in
      -u | --url)
        need_value "$@"
        OLLAMA_HOST_URL="$2"
        URL_CONFIGURED=1
        shift
        ;;
      -m | --model)
        need_value "$@"
        model="$2"
        shift
        ;;
      -s | --switchable) switchable=1 ;;
      -H | --hard-model)
        need_value "$@"
        hard_model="$2"
        switchable=1
        shift
        ;;
      -a | --audit) AUDIT=1 ;;
      -e | --enable-auto-mode) AUTO_MODE=1 ;;
      -n | --dry-run) DRY_RUN=1 ;;
      -V | --version) echo "claude-local $VERSION"; exit 0 ;;
      -h | --help) usage; exit 0 ;;
      --)
        shift
        claude_args=("$@")
        break
        ;;
      *) pfb error "Unknown option: $1 (see --help; put claude's own arguments after --)"; exit 1 ;;
    esac
    shift
  done
  local opus_model="$model" start_model="$model"
  local sonnet_desc opus_desc
  sonnet_desc="Everyday work (Ollama)"
  opus_desc="$sonnet_desc"
  local -a to_check=("$model")
  if ((switchable)); then
    opus_model="$hard_model"
    start_model="sonnet"
    sonnet_desc="Everyday work, faster (Ollama)"
    opus_desc="Writing and judgement, slower (Ollama)"
    to_check+=("$hard_model")
  fi
  ((DRY_RUN)) || check_prerequisites "${to_check[@]}"

  local window picker
  window="$(server_context_length)"
  picker="$(picker_settings "$model" "$sonnet_desc" "$opus_model" "$opus_desc")"

  pfb heading "Claude Code on a local model" "🏠"
  pfb subheading "Model: $model via $OLLAMA_HOST_URL (Ollama)"
  if ((switchable)); then
    pfb subheading "Switchable: /model sonnet = $model, /model opus = $hard_model (each switch reloads the conversation)"
  fi
  if server_is_local; then
    pfb subheading "Inference stays on this machine; this session does not use your Claude subscription"
  else
    pfb subheading "Inference runs on $(server_host); tools and files stay here. This session does not use your Claude subscription"
  fi
  pfb subheading "Context window: $window tokens"
  if ((window < 65536)); then
    pfb warn "A real session starts with about 19.5k tokens of Claude Code's own prompt, leaving $((window - 19500)) for work."
    pfb warn "Raise OLLAMA_CONTEXT_LENGTH on the server (131072 costs about 1GB of memory on a 30B-A3B model)."
  fi
  ((AUDIT)) && pfb subheading "Network audit on"
  ((AUTO_MODE)) && pfb subheading "Auto-mode enabled (Shift+Tab to toggle)"
  echo

  local -a auto_mode_args=()
  ((AUTO_MODE)) && auto_mode_args+=(--enable-auto-mode)
  local -a session_env=(
    "ANTHROPIC_API_KEY="
    "ANTHROPIC_BASE_URL=$OLLAMA_HOST_URL"
    "ANTHROPIC_DEFAULT_HAIKU_MODEL=$model" "ANTHROPIC_DEFAULT_SONNET_MODEL=$model"
    "ANTHROPIC_DEFAULT_OPUS_MODEL=$opus_model" "ANTHROPIC_DEFAULT_FABLE_MODEL=$opus_model"
    "ANTHROPIC_DEFAULT_SONNET_MODEL_NAME=$model" "ANTHROPIC_DEFAULT_SONNET_MODEL_DESCRIPTION=$sonnet_desc"
    "ANTHROPIC_DEFAULT_OPUS_MODEL_NAME=$opus_model" "ANTHROPIC_DEFAULT_OPUS_MODEL_DESCRIPTION=$opus_desc"
    "ANTHROPIC_DEFAULT_FABLE_MODEL_NAME=$opus_model" "ANTHROPIC_DEFAULT_FABLE_MODEL_DESCRIPTION=$opus_desc"
    "ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME=$model" "ANTHROPIC_DEFAULT_HAIKU_MODEL_DESCRIPTION=Background tasks (Ollama)"
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1 DISABLE_TELEMETRY=1 DISABLE_ERROR_REPORTING=1 DISABLE_AUTOUPDATER=1
    "CLAUDE_CODE_MAX_CONTEXT_TOKENS=$window" CLAUDE_CODE_DISABLE_1M_CONTEXT=1 CLAUDE_CODE_DISABLE_FAST_MODE=1
  )
  local -a command=(claude --model "$start_model" --settings "$picker" "${auto_mode_args[@]}" "${claude_args[@]}")

  if ((DRY_RUN)); then
    printf 'env \\\n'
    printf '  %q \\\n' "${session_env[@]}"
    local quoted
    quoted="$(printf '%q ' "${command[@]}")"
    echo "  ${quoted% }"
    return 0
  fi

  if ((AUDIT)); then
    AUDIT_LOG="$(mktemp)"
    sample_session "$$" >/dev/null 2>&1 &
    SAMPLER_PID=$!
  fi
  trap finish_audit EXIT

  local rc=0
  env "${session_env[@]}" "${command[@]}" || rc=$?
  return "$rc"
}

main "$@"
