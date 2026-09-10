# Data for the artifact (measured 2026-09-09/10 on this machine, all local Claude Code transcripts)

Source commands: `./custom_bins/claude-usage-audit --model-usage --days 21` (worktree copy, commit 3a1cdaf) and `python3 tmp/exposure_by_session_model.py [start end]`. Raw outputs: tmp/audit_run.txt, tmp/native_by_day.txt.

## Definitions

- Native failure: a transcript tool_result whose content starts with `<model> is temporarily unavailable (<reason>), so auto mode cannot determine the safety of <tool> right now.` One per tool_use id.
- Bound call: an assistant tool_use for Bash, PowerShell, Monitor, Agent or Task — the tools that reach the auto-mode classifier in auto mode. Upper bound on classifier calls (allow rules and cached verdicts skip it).
- Gateway: the model-router loopback proxy set as ANTHROPIC_BASE_URL. On before 2026-08-18, off 08-18 to 09-06, on from 09-06.

## Failures per 100 bound calls by day (native, all sessions)

| day | failures | bound calls | per 100 | CLI versions | gateway |
|---|---|---|---|---|---|
| 08-19 | 0 | 1169 | 0 | 2.1.234–236 | off |
| 08-20 | 0 | 502 | 0 | 2.1.235–238 | off |
| 08-21 | 0 | 688 | 0 | 2.1.238 | off |
| 08-24 | 0 | 660 | 0 | 2.1.235, 241 | off |
| 08-25 | 0 | 76 | 0 | 2.1.245–246 | off |
| 08-26 | 0 | 958 | 0 | 2.1.245–246 | off |
| 08-27 | 0 | 2741 | 0 | 2.1.246–248 | off |
| 08-28 | 0 | 3998 | 0 | 2.1.247–251 | off |
| 08-29 | 0 | 3451 | 0 | 2.1.250–251 | off |
| 08-30 | 0 | 1978 | 0 | 2.1.251 | off |
| 08-31 | 0 | 2605 | 0 | 2.1.251 | off |
| 09-01 | 0 | 3635 | 0 | 2.1.251–258 | off |
| 09-02 | 0 | 503 | 0 | 2.1.252–258 | off |
| 09-03 | 0 | 155 | 0 | 2.1.258–259 | off (default model → fable this day) |
| 09-04 | 0 | 23 | 0 | 2.1.260 | off |
| 09-05 | 0 | 24 | 0 | 2.1.260–261 | off |
| 09-06 | 212 | 2604 | 8.1 | 2.1.260–263 | ON (rewired) |
| 09-07 | 23 | 1003 | 2.3 | 2.1.263 | on |
| 09-08 | 391 | 2415 | 16.2 | 2.1.263 | on |
| 09-09 | 93 | 365 | 25.5 | 2.1.263, 266 | on |

## Failures / bound calls by period × session (conversation) model

| period | gateway | Fable 5 | Fable 5.1 | Opus 5 | Sonnet 5 | GPT-5.6 Sol | GPT-6 Astra | classifier named in failures |
|---|---|---|---|---|---|---|---|---|
| 08-01..08-18 | on | 62/3606 (1.7%) | — | 91/14007 (0.6%) | 0/1083 | 0/4652 | — | Fable: `claude-opus-5[1m]`; Opus: `claude-opus-5` |
| 08-19..09-05 | off | 0/6194 | 0/517 | 0/16737 | 0/540 | — | — | none |
| 09-06 | on | — | 175/1529 (11.4%) | 5/345 (1.4%, classifier `astra`) | 0/96 | 22/154 (14.3%) | 10/426 (2.3%) | `claude-opus-5[1m]` (astra for GPT-Astra sessions) |
| 09-07 | on | — | 22/82 (26.8%) | 0/67 | 0/19 | 0/583 | 1/252 | `claude-opus-5[1m]` |
| 09-08 | on | — | 382/1087 (35.1%) | 0/144 | 0/61 | 6/789 | 3/334 | `claude-opus-5[1m]` |
| 09-09 | on | — | 93/245 (38.0%) | 0/71 | — | — | — | `claude-opus-5[1m]` |

Totals 09-06..09-09: Fable 5.1 672/2943 (22.8%); Opus 5 5/627; Sonnet 5 0/176; GPT sessions 42/2538.

## Router log (requests routed per day, model as requested; the log has no status codes)

| day | claude-opus-5 | claude-fable-5-1 | claude-sonnet-5 | haiku-4-5 | sol/astra |
|---|---|---|---|---|---|
| 09-06 | 1205 | 763 | 45 | 451 | 343 / 1970 |
| 09-07 | 213 | 140 | 46 | 333 | 931 / 1646 |
| 09-08 | 2341 | 1755 | 249 | 676 | 2357 / 1371 |
| 09-09 | 525 | 343 | 30 | 823 | 3 / 2 |

Reading: Opus 5 sessions made 144 bound calls on 09-08 yet the router carried 2341 Opus 5 requests, so most Opus 5 traffic is the Fable sessions' classifier. Sonnet 5 requests (249) sit near the Opus/Sonnet sessions' classifier volume (144+61 bound calls). Consistent with the docs: Fable session → Opus classifier; other sessions → Sonnet 5 classifier.

## Quota at 2026-09-09 09:07Z (statusline cache)

five-hour 30%; seven-day all models 59%; seven-day Fable-scoped 100% (critical), resets 09-12 19:00Z, previous reset 09-05 19:00Z. The fine period spanned resets on 08-21, 08-28, 09-04 with Fable 5 sessions active (6194 bound calls) and zero failures, so quota alone does not explain the pattern.

## Docs quoted (code.claude.com, fetched 2026-09-09)

- "The classifier runs on Claude Sonnet 5 by default rather than on your /model selection. … or on an Opus model when the session runs on a Fable model."
- "The session's first auto-mode request validates the Sonnet 5 default … After that validation settles, the classifier's model doesn't change for the session."
- errors reference: `rate-limited` = 429 on the classifier model; no automatic approval; interactive sessions prompt, background sessions deny. No client-side retry (also issue anthropics/claude-code#74248).
- "Claude Code selects the classifier model, so which reason you see isn't something you configure."
- Actions matching allow rules resolve before the classifier; broad rules (Bash(*), interpreters, Agent, Monitor) are dropped in auto mode; narrow rules like Bash(npm test) stay.

## Fixes, with the evidence for each

1. Session model off Fable (Opus 5 or Sonnet 5): 0/627 and 0/176 through the gateway on the bad days. Default `model` is `opus` since 2026-09-10 05:08Z. Background jobs inherit the default (`claude --bg --model` overrides per job). Cost: lose Fable as the default.
2. Gateway off for Fable sessions: 0/6194 Fable 5 and 0/517 Fable 5.1 in the fine period. Per-session: `CLAUDE_RC_OVERRIDE=1` wrapper; global: `model-router-wire off`. Cost: lose the foreign-model picker rows and agents.
3. Narrow `Bash(<cmd> <sub> *)` allow rules in global settings: fewer bound calls reach the classifier. Partial; each rule is a command class that runs unclassified. Candidates being mined (allow-rule-miner subagent).
4. Not available: choosing the classifier model (docs); client-side retry (does not exist); `permissions.allow` broad rules (dropped in auto mode).

## Open question and the test that settles it

Why does the gateway make the Fable sessions' Opus classifier fail? Every failure names `claude-opus-5[1m]`, the 1M-context variant, while the router log shows the request as `claude-opus-5` (it does not log beta headers). Test: one Fable session with the gateway off for an hour of shell work; if a failure occurs, read the classifier name in its diagnostic. `[1m]` absent ⇒ the gateway adds the 1M variant; present ⇒ another cause. Zero failures reproduces the fine period.

## Limits

Failures are retained tool_result rows only; the CLI records no successful classifier calls, so rates are failures over an upper bound on calls. Session model per failure is the newest assistant model earlier in the same file (a mid-session model switch blurs it). The parser is wording-locked to CLI 2.1.263/266 text.
