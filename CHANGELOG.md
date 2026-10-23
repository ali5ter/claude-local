# Changelog

All notable changes to claude-local are documented here.

## [Unreleased]

- The README says to press `s`, not Enter, in the `/model` picker: Enter saves the row's alias as Claude Code's default
  model for new sessions, so plain `claude` would start on Sonnet or Opus afterwards.
- Release notes come from this file's section for the tag instead of GitHub's generated notes, which were empty
  without pull requests.
- The "Tested with" line is gone from the README; the Claude Code minimum for the picker remains.
- The README opens with a recorded demo of a real session (`examples/claude-local_demo.gif`, made with vhs from
  `examples/claude-local_demo.tape` through `examples/run_vhs.sh`) in place of a pasted banner.
- The release workflow's tap update is a no-op when the formula already points at the tag, instead of failing on
  "nothing to commit".

## [1.1.0] — 2026-10-19

- The `/model` picker lists the local models under their real names again, through a `modelPicker` lineup passed with
  `--settings`. On Claude Code 2.1.292 the `ANTHROPIC_DEFAULT_*_MODEL_NAME` variables no longer reached the picker;
  the lineup does, and it needs Claude Code 2.1.242 or later.
- Fast mode is turned off for the session (`CLAUDE_CODE_DISABLE_FAST_MODE`), since `/fast` would route to an
  Anthropic model.
- New `--dry-run` flag prints the environment and command a session would start with.

## [1.0.1] — 2026-10-19

- README and changelog no longer link to an unpublished post or name a private repo.
- The audit trap satisfies SC2015 on the shellcheck version in CI; no behaviour change.

## [1.0.0] — 2026-10-19

First release as its own repository. The script began as a `scripts/claude-local.sh` (1.2.5) inside the private
repo that holds my local AI setup, where it was tied to that repo's `.env` and helper library.

### Changes from that version

- Settings come from flags, the environment, then `~/.config/claude-local/env` (or `CLAUDE_LOCAL_CONFIG`), instead of
  a `.env` in the repo. The model variables are now `CLAUDE_LOCAL_MODEL` and `CLAUDE_LOCAL_HARD_MODEL`.
- New `--url` and `--version` flags.
- `pfb` is optional: without it, output falls back to plain text.
- A model that is not installed lists the models that are.
- Error messages no longer refer to the other repo's scripts and docs.
