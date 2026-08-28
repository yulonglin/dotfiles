---
name: second-opinion
description: Route a second opinion to a different model family - Fable, codex-companion, openrouter-cli, OpenCode. Use for "second opinion", "sanity check this", "ask another model", "adversarial review", "am I wrong".
---

# Second Opinions

A second opinion is only worth its cost when it comes from a **different model family**. Another call to the model that is already stuck reliably produces agreeing-sounding text, because it shares the priors that produced the stuck answer. That is the whole point of this skill: route the question somewhere with genuinely different priors.

## Ask for one when the cost is justified

Three triggers, all of them cheap relative to being wrong:

- **The same approach has failed twice.** Not two symptoms of one bug — two genuine attempts at the same goal. A third attempt from the same reasoning is the least likely to differ.
- **A high-ambiguity design call.** Two or more viable architectures, and the trade-off axis is judgement rather than measurement.
- **Corroborating a high-stakes conclusion.** Before a result ships, a spend commitment, or an irreversible change.

Outside those, skip it. A second opinion on scoped, settled work buys latency and nothing else.

## Every channel is amnesiac — brief it fully

None of these channels can see the conversation. Unlike `advisor`, which is forwarded the whole transcript automatically, everything here starts blank.

So every brief is **self-contained**: what the system is, what was tried, what happened, what the actual question is, and the constraints that make the obvious answer wrong. A brief that says "does this look right?" gets an answer about a system the model invented. Paste the code, the error, and the relevant config rather than naming them.

## Pick the channel by what you want critiqued

| You want | Channel | Invocation |
|---|---|---|
| Judgement, architecture, research taste | Fable subagent | Agent tool, `model: "fable"` |
| Code-level critique of a diff | `codex-companion` | Monitor tool, `adversarial-review` |
| Critique of a written plan | `codex-companion` | Monitor tool, `plan-review` |
| Open-ended investigation | `codex-companion` | Monitor tool, `task` |
| One non-Anthropic family's view | `openrouter-cli` | `openrouter-cli ask <alias> "<prompt>"` |
| A multi-family panel plus synthesis | `openrouter-cli` | `openrouter-cli fusion "<prompt>"` |
| Agentic coding by a non-GPT model | OpenCode | `opencode run -m openrouter/<slug> "<prompt>"` |

GPT is the exception to the OpenCode line: **`codex-companion` stays the GPT agentic-coding route**, and OpenCode covers everything else.

## Non-Anthropic models CANNOT be reached through subagents

This is a hard constraint, not a preference, and it has bitten before.

An agent's frontmatter `model:` name resolves **only against api.anthropic.com**. Naming a non-Anthropic model there produces one of two outcomes, and the second is much worse than the first:

- It hard-fails with "There's an issue with the selected model".
- It answers from Claude **wearing another family's label** — which silently fabricates a multi-family result. A panel that is secretly one model agreeing with itself is worse than no panel, because it looks like corroboration.

The `kimi-k3`, `glm-5.3`, `qwen3.8-max` and `muse-spark-1.2` agent files were deleted on 2026-08-25 for exactly this. Do not recreate them. The model-router gateway that once made such names resolve is unwired, because it hard-disables Remote Control.

**The CLI is the only sanctioned route to a non-Anthropic family.**

## The configured models

Aliases live in `config/openrouter-models.toml`, which is the single source of truth. Use the alias, not the raw slug.

| Alias | Slug | Notes |
|---|---|---|
| `glm` | `z-ai/glm-5.3` | |
| `kimi` | `moonshotai/kimi-k3` | |
| `qwen` | `qwen/qwen3.8-max` | |
| `deepseek` | `deepseek/deepseek-v4-pro-0813` | pinned checkpoint, not the rolling name |
| `muse` | `meta/muse-spark-1.2` | |
| `gemini` | `google/gemini-3.7-flash` | |
| `grok` | `x-ai/grok-4.6` | newest x-ai line — see the version trap below |
| `gpt55pro` | `openai/gpt-5.5-pro` | **$30/M in, $180/M out** — ~6x the non-pro model |

Two things to hold onto:

- **`gpt55pro` is deliberately not in the default fusion panel.** It is roughly six times the price of its non-pro sibling, so it must be asked for explicitly: `openrouter-cli ask gpt55pro "..."`, or `--panel gpt55pro,...`. There is no opt-in flag in the schema; keeping it out of `panel` *is* the mechanism.
- **x-ai version numbers are not chronological.** `grok-4.20` belongs to an OLDER line than `grok-4.6`. "Pick the biggest number" selects the wrong model here, which is why the drift checker ranks by the catalog's `created` timestamp instead of parsing versions.

The default `fusion` panel is seven models, one per company: `glm`, `kimi`, `qwen`, `deepseek`, `muse`, `gemini`, `grok`. Panel members are written as aliases so repointing a `[[models]]` entry updates the panel too. OpenAI is absent on cost grounds; GPT opinions come from `codex-companion`.

`fusion` fails closed on a degraded panel: OpenRouter keeps `status: "ok"` on partial panel failures, so the CLI verifies the tool-call record before presenting anything as a full panel. If it refuses, believe it — a collapsed panel presented as corroboration is the exact failure this tooling exists to prevent.

## Model IDs drift, so the check is scheduled

Model slugs are renamed and retired continuously, and a stale slug fails in a way nobody notices. This is not hypothetical: on 2026-08-28 the `judge` was found pointing at `anthropic/claude-opus-4-8`, which the catalog spells `claude-opus-4.8`, so **every `fusion` call had been failing** — invisibly, because the old `models --check` validated only the `[[models]]` table and never the judge or the panel.

`openrouter-cli drift` closes that. It checks **every** slug the config can spend money on — judge, panel and models — against the live catalog, and reports three things:

- **gone** — the slug is not in the catalog, so any call naming it fails outright. Suggests live models from the same family, newest first, which catches a misspelling.
- **superseded** — still working, but a newer checkpoint exists in the same family.
- **expiring** — the catalog gives it a retirement date inside a year. (Far-future sentinel dates like `2098-12-31` mean "no expiry" and are ignored.)

It needs **no API key**: the OpenRouter catalog endpoint is public. Exit code is `0` when clean and `3` when drift is found.

### Reading the report and forcing a check

A systemd user timer runs it monthly and leaves the report on disk:

- `~/.local/state/openrouter-drift/drift-report.md` — the readable version
- `~/.local/state/openrouter-drift/drift.json` — the same findings, machine-readable

Run it by hand at any time with `openrouter-cli drift`, or force the scheduled job with `systemctl --user start openrouter-drift.service`. Check the schedule with `systemctl --user list-timers openrouter-drift.timer`.

**The report file is the signal, deliberately — not the unit's exit state.** `reset-failed.timer` clears failed-unit state hourly on this box, so a finding recorded as a unit failure would be erased before anyone saw it. The service therefore declares exit 3 a success and writes its finding to disk.

**The timer never edits the TOML.** It reports; the edit stays a human decision, because swapping a model changes both spend and results. Apply a finding by editing `config/openrouter-models.toml` by hand and re-running `openrouter-cli drift` to confirm it is clean.

Ranking configured models by capability index is a separate, manual command: `openrouter-cli refresh` (Epoch ECI needs no key; the Artificial Analysis index needs `AA_API_KEY`). Attribution to Epoch AI and artificialanalysis.ai is required by their licences wherever those numbers appear.

## Keys are per-project, never global

`openrouter-cli ask` and `fusion` spend money and so need `OPENROUTER_API_KEY`. Secrets on this machine are **not** globally exported — that is the supply-chain defense, not a misconfiguration. Two sanctioned routes:

- `setup-envrc` in the repo that needs it, so direnv provides it persistently.
- `with-secrets OPENROUTER_API_KEY -- openrouter-cli fusion "..."` for a one-shot.

`with-secrets` is a **zsh function**, so it is unavailable to systemd units and non-shell callers; those use `dotfiles-secrets shell KEY` or `jkeys exec`. `openrouter-cli drift` sidesteps all of this by needing no key.

## OpenCode is the non-GPT agentic-coding route

`codex-companion` gives GPT a real agentic loop over the code. OpenCode is the equivalent for every other family, driving OpenRouter models against a working tree.

```
opencode run -m openrouter/x-ai/grok-4.6 "<self-contained brief>"
```

Config lives at `~/.config/opencode/opencode.json`; a project-level `./opencode.json` overrides it. The repo template is `config/opencode/opencode.json` and it uses `{env:OPENROUTER_API_KEY}` rather than an on-disk key, so OpenCode sees a key only when launched from a repo with direnv set up, or under `with-secrets`.

**Do not run OpenCode's `/connect` command.** It writes the resolved key in plaintext to `~/.local/share/opencode/auth.json`, which is precisely the global-key-on-disk situation the per-project model exists to avoid.

### If OpenCode says its postinstall did not run

That error means the guard is working. `opencode-ai` declares a `postinstall` script, and this machine sets `ignore-scripts=true` (bun ignores lifecycle scripts by default), so the npm shim is inert.

**Do not re-enable lifecycle scripts and do not add the `anomalyco` tap** — both need Yulong's explicit approval, and neither is necessary. The real binaries ship as platform packages that bun already installed; `custom_bins/opencode` finds them directly, running no lifecycle script. Where Homebrew exists, `brew install opencode` from homebrew-core is better still — it has Linux bottles as well as macOS, and a bottle has no install script to block.

## Related

- `advisor` — the one channel that already has the conversation; no brief needed.
- `config/openrouter-models.toml` — aliases, panel, judge.
- `custom_bins/openrouter-cli` — `models`, `drift`, `refresh`, `ask`, `fusion`.
- `claude/rules/safety.md` — the supply-chain rules that constrain how any of this gets installed.
