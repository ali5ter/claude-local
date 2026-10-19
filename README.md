# claude-local

Start a [Claude Code](https://claude.com/claude-code) session on a local model served by
[Ollama](https://ollama.com), with every environment variable the session needs set together and nothing written to
disk.

```console
❯ claude-local --switchable

🏠 Claude Code on a local model
   Model: qwen3.6:35b-a3b-coding via http://192.168.1.63:11434 (Ollama)
   Switchable: /model sonnet = qwen3.6:35b-a3b-coding, /model opus = qwen3.8:27b (each switch reloads the conversation)
   Inference runs on 192.168.1.63; tools and files stay here. This session does not use your Claude subscription
   Context window: 131072 tokens
```

Plain `claude` is untouched. Everything the script sets is for that one process, so the same machine can run a cloud
session in the next terminal, and `~/.claude` and its symlinks are left exactly as they are. Your real configuration
(`CLAUDE.md`, skills, hooks) loads as usual.

## Why a script

Claude Code picks its backend from environment variables, and a local session needs several of them set together.
A few are easy to forget, and two took an afternoon each to find:

- **The base URL.** `ANTHROPIC_BASE_URL` pointed at Ollama, which serves Anthropic's Messages API. No auth token is
  set: Ollama needs none, and a placeholder makes Claude Code warn that its claude.ai connectors are disabled.
- **Every model alias.** Claude Code makes background calls to a small model by name (haiku), and Ollama has no model
  called that. So haiku, sonnet, opus and fable are all mapped to the local model, and the `/model` picker shows the
  real model name and a use-case description instead of Anthropic's labels.
- **The phone-home switches.** `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`, `DISABLE_TELEMETRY`,
  `DISABLE_ERROR_REPORTING` and `DISABLE_AUTOUPDATER`. Without them, a session pointed entirely at a local model still
  opens connections to Anthropic and to a Google Cloud host.
- **The real context window.** For a model it does not recognise, Claude Code assumes 200k tokens, so it would carry
  on past Ollama's window while Ollama silently dropped the start of the conversation.
  `CLAUDE_CODE_MAX_CONTEXT_TOKENS` tells it the real number, so it compacts in time. The script reads that number from
  the Ollama process when the server is on the same machine.
- **The one-million-token trap.** Even with that set, Claude Code's "default" model setting resolves to a
  one-million-token variant that ignores the number above. `CLAUDE_CODE_DISABLE_1M_CONTEXT` turns that variant off.

The story behind it is in
[Running AI Locally — What I've Learned](https://different.com/posts/local-first-llm-setup/). The measurements, model
evaluations and server setup scripts it came from are in
[ai-local-first](https://github.com/ali5ter/ai-local-first).

## Install

```bash
brew install ali5ter/tap/claude-local
```

Or copy `claude-local.sh` anywhere on your `PATH`. It is a single file.

Requirements:

- [Claude Code](https://claude.com/claude-code)
- [Ollama](https://ollama.com) recent enough to serve the Anthropic Messages API (`/v1/messages`), on this machine or
  another one you can reach, with at least one model pulled
- `curl` and `jq`
- [pfb](https://github.com/ali5ter/pfb) for the terminal output shown above; without it the script prints plain text
- `lsof`, only for `--audit`

Tested with Claude Code 2.1.292 and Ollama 0.40.5 on macOS. Several of the variables above are undocumented Claude Code
internals and can change between releases; if a session stops behaving as described, please open an issue with the
Claude Code version.

## Use

```bash
claude-local                                   # a session on the default model, Ollama on this machine
claude-local --model gpt-oss:20b               # another installed model
claude-local --url http://192.168.1.63:11434   # Ollama on another machine
claude-local --switchable                      # two models in one session (see below)
claude-local --audit                           # list outside connections when the session ends
claude-local --enable-auto-mode                # Claude Code's auto mode on from the start (Shift+Tab toggles)
claude-local -- -p "Reply with exactly: ok"    # everything after -- goes to claude
```

| Flag | Effect |
| ---- | ------ |
| `-u`, `--url URL` | Ollama server (default `OLLAMA_HOST_URL`, else `http://localhost:11434`) |
| `-m`, `--model MODEL` | Model for the session (default `CLAUDE_LOCAL_MODEL`) |
| `-s`, `--switchable` | Make `/model opus` switch to the second model |
| `-H`, `--hard-model MODEL` | Use this as the second model; implies `--switchable` |
| `-a`, `--audit` | List connections beyond loopback and the model server on exit (needs `lsof`) |
| `-e`, `--enable-auto-mode` | Enable Claude Code auto mode |
| `-V`, `--version` | Print the version |
| `-h`, `--help` | Usage |

## Configure

Settings come from flags, then the environment, then a config file: `~/.config/claude-local/env`, or the path in
`CLAUDE_LOCAL_CONFIG`. Copy [`env.template`](env.template) there and uncomment what you need.

| Variable | Meaning | Default |
| -------- | ------- | ------- |
| `OLLAMA_HOST_URL` | Ollama server | `http://localhost:11434` |
| `OLLAMA_CONTEXT_LENGTH` | Context window the server runs with | read from the local server, else 32768 |
| `CLAUDE_LOCAL_MODEL` | Model for the session | `qwen3.6:35b-a3b-coding` |
| `CLAUDE_LOCAL_HARD_MODEL` | Second model for `--switchable` | `qwen3.8:27b` |

The model defaults are the two models I run on a 64GB Mac Studio; set your own. A model that is not installed is
refused with the list of models that are.

### Two models in one session

Claude Code's `/model` command only chooses between its own aliases, so the only way to get two local models into one
session is to map two of them. With `--switchable`, sonnet and haiku go to the main model and opus and fable go to a
second, slower one for writing and judgement-heavy work. `/model opus` switches to it and `/model sonnet` back. Each
switch makes Ollama load the other model and re-read the conversation, so a long session pauses while that happens.
That is why it is a flag and not the default.

### Ollama on another machine

Set `OLLAMA_HOST_URL` (or pass `--url`) to the address the server binds to, and only inference moves: Claude Code, its
tools and the files it edits stay where you are sitting. This works across a LAN or a VPN. The one thing the script
cannot do from another machine is read the server's context window, so set `OLLAMA_CONTEXT_LENGTH` to the value the
server runs with, or 32768 is assumed and you get a warning.

On the server, Ollama must listen on a reachable address (`OLLAMA_HOST=192.168.1.63:11434`, say). Ollama has no
authentication, so bind it to a specific address on a network you trust, never `0.0.0.0` on an open one.

### The context window

A real session starts with about 19.5k tokens of Claude Code's own system prompt. Below a 64k window the script warns,
because there is little room left for work. 128k is a good target; on a 30B mixture-of-experts model it costs about
1GB of memory over the default. The setting is `OLLAMA_CONTEXT_LENGTH` in the server's environment.

### Network audit

`--audit` samples the session's connections every 0.3s with `lsof` and, on exit, lists any endpoint other than
loopback and the model server. It is evidence rather than proof, because sampling can miss a very short connection.
With the switches above set, a session on a local model has shown no outside connections.

## Compared with `ollama launch claude`

Ollama ships its own command to wire Claude Code to a local model. This script differs in that it writes nothing to
disk, sets the context window and the one-million-token guard, turns the non-essential traffic off, maps the model
picker, supports two models in one session and a server on another machine, and can audit the session's connections.
I have not examined what `ollama launch` writes, so this is a description of what this script does, not a claim about
what that command lacks.

## Develop

```bash
shellcheck -x claude-local.sh tests/*.sh
markdownlint '*.md'
tests/smoke.sh          # offline checks: flags, precedence, error paths
```

Releases are annotated tags (`v1.2.3`); the release workflow publishes GitHub release notes and updates the Homebrew
formula.

## License

[MIT](LICENSE), copyright Alister Lewis-Bowen.
