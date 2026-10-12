# Coding Conventions

## Python

Stack: `uv` (packages, Python versions, CLI tools), `ruff` (lint + format), `ty` (types, beta), `just` (tasks), `cyclopts` (CLIs), `pydantic-settings` (config/env), `pydantic` (validation), `pytest`, `httpx`, `anyio`.

Invoke via `uv run` (`--no-sync` when deps are unchanged); read `.eval` logs with Inspect AI's `read_eval_log()`. **Never call `sys.path.insert` at import time — it crashes the session.** Pass data as pydantic `BaseModel`/`dataclass`, not `pd.DataFrame`; JSONL for intermediates, pandas only at the pipeline edge. Copy shared configs, don't mutate them. Rewrite shell in Python past ~50 lines.

## Any language

**Parallelize embarrassingly parallel loops by default** — background N independent iterations and wait (`asyncio.gather`, `Promise.all`, `cmd & … wait`). Sequential only for real ordering dependencies, shared mutable state, or OS-level exclusivity.

**Deliver as commit → push → PR → review → merge.** The `pr_after_push` hook opens a draft PR. **Review is 1–2 rounds**: must-fix changes a real output (a label, a number, what a user or monitor sees) or is a real security risk, shown on real data; a constructed attack is a follow-up listed in the PR. Merge it yourself when simple (docs, rules, one file, tests green, nothing under settings, hooks or secrets), else ask. Merges never block results.

**Shell scripts are zsh** (`#!/usr/bin/env zsh`): modern everywhere without Homebrew, unlike bash 5 on a Mac. Existing bash converts when touched; the cloud bootstrap stays bash since it installs zsh. `shellcheck` bash files; it cannot parse zsh, so a zsh file gets `zsh -n` (pre-commit runs it), never a `# shellcheck shell=bash` line. Idioms agents get wrong:

- Prompt with `read "var?Prompt: "` — `read -p` reads a coprocess in zsh.
- Arrays are 1-indexed.
- `$var` does not word-split, so `${=var}` when you want it.
- `setopt null_glob` before a glob that may match nothing.
- UTC/ISO-8601 timestamps: `$(utc_date)`, `$(utc_timestamp)`.

TypeScript over JS; bun over npm; Biome over ESLint+Prettier. Available: `rg` `fd` `fzf` `bat` `eza` `z` `delta` `jq` `jless` `dust` `duf` `sd` `trash` `gws`, and `any2md <input>` → Markdown; usage detail in `fast-cli`. Piped output that looks stuck is usually block buffering — `stdbuf -oL` or Python's `-u`.

**Promote a scratch script once it has run three or more times, at least once unchanged, with a foreseeable next use.** A PATH command goes to `custom_bins/`, a repo task to that repo's `scripts/` or `justfile`, a shell wrapper to `config/aliases/<topic>.sh`, an importable helper into the owning package, a procedure Claude reruns into a skill. Promotion means argument parsing, `--help`, real exit codes and no hardcoded absolute paths; a renamed copy is not promotion. Search first, delete the original, and port what it does today.

For service, proxy, hook or updater changes, apply `~/.claude/checklists/local-services.md` first.
