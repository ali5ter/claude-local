# Changelog

All notable changes to claude-local are documented here.

## [1.0.0] — 2026-10-19

First release as its own repository. The script began as `scripts/claude-local.sh` (1.2.5) in
[ai-local-first](https://github.com/ali5ter/ai-local-first), where it was tied to that repo's `.env` and helper
library.

### Changes from the ai-local-first version

- Settings come from flags, the environment, then `~/.config/claude-local/env` (or `CLAUDE_LOCAL_CONFIG`), instead of
  a `.env` in the repo. The model variables are now `CLAUDE_LOCAL_MODEL` and `CLAUDE_LOCAL_HARD_MODEL`.
- New `--url` and `--version` flags.
- `pfb` is optional: without it, output falls back to plain text.
- A model that is not installed lists the models that are.
- Error messages no longer refer to the other repo's scripts and docs.
