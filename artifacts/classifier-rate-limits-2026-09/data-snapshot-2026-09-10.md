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

## 2026-09-06 split at 09:00 — the natural experiment (added 2026-09-10, `onset_0906.py`)

The router began listening at 09:07 UTC and the wiring commit landed at 09:25, while CLI 2.1.263 sessions had been running since 03:00. Splitting the single day at 09:00 holds CLI version, session model, machine and account fixed and varies only the gateway.

Denominator: Bash, PowerShell, Monitor, Agent, Task and **SendMessage** — the tools the permission-modes docs put through the classifier. Failures on any other tool are excluded from every rate below and reported separately. ~~An earlier cut counted SendMessage failures (104 of them) against a denominator that omitted SendMessage~~ corrected 2026-09-10 after a council review; every figure in this section is the recomputed one.

Restricted to CLI 2.1.263, failures / classifier-bound calls:

| session model | before 09:00 | from 09:00 |
|---|---|---|
| Fable 5.1 | 0/720 | 172/793 (21.7%) |
| Opus 5 | 0/198 | 5/107 (4.7%) |
| Sonnet 5 | 0/87 | 0/9 |
| Opus 4.8 | 0/1 | 0/36 |
| GPT-5.6 Sol | 0/0 | 22/172 (12.8%) |
| GPT-6 Astra | 0/0 | 10/652 (1.5%) |
| Kimi K3 | 0/0 | 0/16 |
| Haiku 4.5 | 0/0 | 0/3 |
| **all models, 2.1.263** | **0/1006** | **209/1788** |

Context rows, not part of the held-fixed comparison: CLI 2.1.261 sessions 0/190 before and 0/42 after; CLI 2.1.260 sessions 0/7 and 0/3; all sessions on every version 0/1203 before and 209/1833 after.

Excluded from every count above: 3 failures on tools with no denominator (Edit 1, an MCP browser tool 2).

Hourly onset (failures / classifier-bound calls; a call is counted in the hour of its tool use, a failure in the hour of its tool result):

| hour UTC | 2.1.260 | 2.1.261 | 2.1.263 |
|---|---|---|---|
| 00 | — | 0/6 | — |
| 01 | — | 0/65 | — |
| 02 | — | 0/37 | — |
| 03 | — | 0/53 | 0/128 |
| 04 | — | 0/1 | 0/107 |
| 05 | — | 0/1 | 0/195 |
| 06 | — | — | 0/39 |
| 07 | — | — | 0/154 |
| 08 | 0/7 | 0/27 | 0/383 |
| 09 | — | 0/37 | 2/287 |
| 10 | — | 0/5 | 0/177 |
| 11 | — | — | 15/483 |
| 12 | — | — | 13/272 |
| 13 | 0/3 | — | 98/278 |
| 14 | — | — | 42/249 |
| 15 | — | — | 39/42 |

Cautions. A session fixes its base URL at launch, so sessions started before the rewire but still running after it sit in the "after" column without the gateway; that dilutes the after column toward zero. The 2.1.261 row is not a control — its calls sit on the same machine-wide setting. Opus 5 is near zero rather than at it: the five failures name `astra` as the classifier, not `claude-opus-5[1m]`, which fits a session routed to a foreign model whose last recorded assistant model was Opus 5. Per-model rows now sum exactly to the 209 total. Across every version this counter records 3,036 classifier-bound calls for the day against the audit's 2,604, because it counts SendMessage and the audit does not.

The by-day and by-period figures elsewhere in this snapshot are still on the earlier denominator, so their rates run high and are not directly comparable with this section. `split_gateway_vs_cli.py`, vendored beside this file, also predates the fix. Recomputing both is outstanding.

## 2026-09-10 with CLI 2.1.267 (added 2026-09-10)

Fable 5.1 sessions: 0 failures in 78 classifier-bound calls, gateway still on. Not evidence of a fix — the CLI version, the signed-in account and the default model all changed the same morning, and 78 calls is thin against the 637 that produced 175 failures on 6 September.

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
2. Gateway off for Fable sessions: 0/720 Fable 5.1 classifier-bound calls before the 09:00 split on 09-06 against 172/793 after it, same CLI and account; the fine period corroborates at 0/6194 Fable 5 and 0/517 Fable 5.1. Per-session: `CLAUDE_RC_OVERRIDE=1` wrapper; global: `model-router-wire off`. Cost: lose the foreign-model picker rows and agents.
3. Narrow `Bash(<cmd> <sub> *)` allow rules in global settings: fewer bound calls reach the classifier. Partial; each rule is a command class that runs unclassified. Candidates being mined (allow-rule-miner subagent).
4. Not available: choosing the classifier model (docs); client-side retry (does not exist); `permissions.allow` broad rules (dropped in auto mode).

## Open question and the test that settles it

Why does the gateway make the Fable sessions' Opus classifier fail? Every failure names `claude-opus-5[1m]`, the 1M-context variant, while the router log shows the request as `claude-opus-5` (it records no beta header and no upstream status).

~~Test: one Fable session with the gateway off for an hour of shell work; if a failure occurs, read the classifier name in its diagnostic.~~ Superseded 2026-09-10 by the within-day split above, which establishes the gateway's causal role and leaves only the mechanism open; with the gateway off there is no failure and so no diagnostic to read.

Next test: one Fable 5.1 session with the gateway on and `CLAUDE_CODE_MAX_CONTEXT_TOKENS` removed or lowered to a standard window. `config/model-router.toml` sets `declared-context-window = 258400` and `model-router-wire apply` renders it into that settings key; a client that believes its window is 258,400 tokens has a reason to request the 1M-context beta. If the classifier named in a failure loses the `[1m]` suffix, the declared window is the mechanism; if it survives, the router adds the beta itself and its outbound headers are the next place to log.

## Limits

Failures are retained tool_result rows only; the CLI records no successful classifier calls, so rates are failures over an upper bound on calls. Session model per failure is the newest assistant model earlier in the same file (a mid-session model switch blurs it). The parser is wording-locked to CLI 2.1.263/266 text.
