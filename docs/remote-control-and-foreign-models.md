# Remote Control + non-Claude models: use the tool layer, not the transport layer

**Verified against Claude Code v2.1.252 on 2026-09-01.** Raw evidence (gitignored, session-local): `tmp/rc-multimodel-research.txt`, `tmp/rc-gate-probe.txt`, `tmp/ban-risk-research.txt`, `tmp/council-out.txt`, brief at `tmp/council-brief.md`. The verbatim bundle excerpts and terms quotes below are the durable copy.

## Bottom line

**Build the tool layer. Do not route at the transport layer.** Three findings, in order of how much they should change your plans:

1. **Claude Code silently falls back to your default model when it does not recognise a model ID.** Measured: `--model not-a-real-model-xyz` returned an answer from `claude-opus-5`, with only a stderr warning. This is the single most important result here, and it is a safety finding, not an architecture one — see below.
2. **Native Remote Control and a non-Claude `/model` menu are mutually exclusive by construction** in this binary. Not a bug, and not something a proxy fixes.
3. **The transport route (a local router) is technically open — the gate is a string check with no TLS pinning — but I am recommending against it**, because the payoff collapsed under testing and the downside is the subscription that powers Remote Control itself.

**Recommendation:** an MCP server wrapping the tools you already own, plus a child Claude Code process when a foreign model needs real repo tools. Both leave `ANTHROPIC_BASE_URL` untouched, so Remote Control keeps working everywhere.

## Finding 1 — the silent fallback, measured on both paths

**Headless `--model`:**

```
$ claude -p --output-format json --model "not-a-real-model-xyz" "Say OK"
stderr: [claude-code:unrecognized_model] {"model":"not-a-real-model-xyz","query_source":"sdk"}
resolved: claude-opus-5   provider: firstParty   → answered "OK"
```

**Subagent frontmatter** — the path that actually matters, tested separately because the bundle shows it is distinct code (`resolveTeammateModel` plus an `availableModels` allowlist, which could have rejected). An agent file with `model: openai/gpt-5.6-sol` in a scratch directory:

```
stderr: [claude-code:unrecognized_model] {"model":"openai/gpt-5.6-sol","query_source":"agent:custom:fake-model-probe"}
resolved: claude-opus-5   → the agent loaded, ran, and replied
```

**The allowlist did not reject it.** The agent loaded normally and answered as Claude Opus 5. So on 2.1.252 both paths silently fall back to the default model, and the only signal is a stderr line that a subagent's caller never sees.

This **updates** the repo's 2026-08-25 learning, which said such an agent "hard-fails, **or** answers as Claude wearing another family's label". On this version the hard-fail branch no longer happens — it is unambiguously the second, and quieter than the learning implies. Those four agent files were right to be deleted, and must not come back.

It also kills the most attractive idea in this space: "a router plus arbitrary model strings in agent frontmatter gives unlimited non-Claude subagents." It cannot, because Claude Code **replaces the string before the request leaves the process**. A router never sees it.

## Finding 2 — the constraints, verified from the binary

| # | Fact | Evidence |
|---|---|---|
| C1 | RC is disabled if `ANTHROPIC_BASE_URL` is set and its host is not `api.anthropic.com`. `_CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL` is explicitly exempted. RC also rejects API-key auth — it needs the OAuth subscription | `Nw(e){let t=new URL(e).host;return["api.anthropic.com"].includes(t)}` |
| C2 | `ANTHROPIC_CUSTOM_MODEL_OPTION` adds **one** `/model` row, unconditionally, before the provider is resolved. Single-slot: no `_2`, no plural variant | `strings`, fn `ln(e,o)`; upstream issue #58583 |
| C3 | No OpenAI/OpenRouter provider exists. Anthropic, verbatim: *"doesn't support routing Claude Code to non-Claude models through any gateway"* | docs.claude.com/en/llm-gateway |
| C4 | Base URL is process-level; subagents inherit the session's provider. Agent `model:` takes `sonnet\|opus\|haiku\|fable\|<full-id>\|inherit` — and an unrecognised full ID falls back silently (Finding 1) | `strings`; docs; measured |
| C5 | `settings.json` is the only place the base URL is read from; a CLI `--settings` file outranks it | repo measurement (on 2.1.222 — worth re-measuring) |
| **C6** | **Gateway model discovery populates MULTIPLE picker rows from `<base>/v1/models` — but requires the base URL set AND not matching api.anthropic.com, i.e. exactly the condition that kills RC** | `mu(){if(!a.CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY)return!1;if(Oe()!=="firstParty")return!1;if(jo())return!1;if(!a.ANTHROPIC_BASE_URL)return!1;return!0}` |

C6 is the clean statement of the whole problem: **a full non-Claude menu and native RC are mutually exclusive in one process, by construction.** No configuration reconciles them.

## The recommendation, in two parts

**(a) An MCP server wrapping what you already own.** Expose `ask(model, q)`, `council(q)`, `delegate(family, brief)` over `openrouter-cli`, `opencode run` and `codex-companion`. This is the council's strongest contribution, and the reframing behind it is worth keeping: **the 2026-08 gateway failure was a layering error.** Routing at the transport layer collides with C1–C6 by construction; routing at the tool layer escapes all of them. Concretely it beats bare CLI calls because MCP tool calls flow through the permissions model and appear in the transcript — and — **council claim, unverified** (`gemini`, `fable`) — MCP permission prompts surface in Remote Control's phone approval UI, so you could approve a Grok council from your phone inside an RC session. If that holds it is the closest thing to "both at once" that exists; test it before building on it.

**(b) A child Claude Code process when a foreign model needs real repo tools.** From an RC-enabled parent, spawn `claude --settings gateway-settings.json` in a worktree. The parent never touches `ANTHROPIC_BASE_URL`, so its RC is intact. The child gets the real Claude Code loop and CLAUDE.md, and — **bundle inference, not run** — `CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY` should give it **multiple** foreign models in its own picker per C6. Nothing exists yet: no `gateway-settings.json`, and the model-router service it would point at was uninstalled on 2026-08-18. This is the supported cousin of the proxy route: fewer foreign models than body-routed interception could serve, but no gate worked around and no TLS termination of your own OAuth traffic.

Skip a second install via `CLAUDE_CONFIG_DIR` — C5 measured it ignored for the base URL.

### Council ranking, and the disagreement worth keeping

Eight families, all ranking the orchestrator/worker direction first or tied-first: **D > A > B > C**. Three ranked "decide-at-launch split sessions" **worst** — an irreversible launch-time choice that buys one picker row and costs RC.

**Preserved disagreement:** `gpt-5.6-sol` and `qwen3.8-max` insist MCP is a control plane only — it cannot give a foreign model *shared context* with the leader, and that residual gap is the one thing that would justify turning the gateway on globally. `kimi-k3` argues a subagent restricted to the MCP namespace is effectively a routed subagent. Both are right about different things: you get delegation, you do not get a foreign model reading your live transcript. Do not average that away.

**What would flip the recommendation** (four seats raised it independently): if your real need is *conversing* with a foreign model rather than *tasking* it, workers are the wrong shape. Their proposed test is good — watch a month of your own usage and see whether you keep wanting to "talk to" GPT rather than "task" it.

## The transport route: investigated, open, and rejected

Recorded so it is not rediscovered. **It is not impossible — the council's technical objections were wrong on this binary.**

- **The gate is a pure string comparison** on the *configured* value. No socket, no DNS, no verification of where traffic actually goes. Unset passes; so do a trailing slash, `http://`, and a subpath.
- **No TLS pinning.** Zero hits for `sha256/`, `pin-sha256`, `publicKeyPinning`, `certificatePinning`; `rejectUnauthorized` never co-occurs with "anthropic".
- **The client does go through an HTTPS proxy.** Proven by the strongest possible evidence: this sandbox already routes it through one. `https_proxy` (lowercase) is honoured; uppercase `HTTPS_PROXY` is ignored when lowercase is set.
- **Correction to my own earlier note:** my first proxy test was invalid. All eight proxy variables were already set in this environment, so the "control" run was already proxied — I measured override behaviour, not proxy support. The conclusion survives, the reasoning did not.
- **Still untested, and it is the fatal link:** an HTTPS proxy sees a CONNECT tunnel, so it **cannot read the `model` field** without terminating TLS, which needs the Anthropic client path to trust your CA. `NODE_EXTRA_CA_CERTS` appears in the bundle but that is not evidence this client path honours it. And RC's own relay channel is separate code that may honour neither.

**Why reject it anyway:** Finding 1 destroyed the payoff. A router cannot receive arbitrary model strings, so the route buys **at most one** non-Claude model, and possibly **zero**: with `ANTHROPIC_CUSTOM_MODEL_OPTION=zzz-fake-custom-model` and `--model zzz-fake-custom-model`, the headless path still substituted `claude-opus-5`. C2's single-slot grep is solid (no `_2`, no plural variant); whether the interactive picker forwards that one slot under a first-party provider is untested — while the child-process route (C6) gives you a whole menu with nothing bypassed. You would be terminating TLS on your own OAuth traffic and working around a gate Anthropic tightened deliberately at ~2.1.196 — which, with body-based routing (a sentinel in an agent's system prompt rather than the substituted model field), could in principle serve unlimited foreign subagents. That makes it more capable than the child-process route, not less; it is rejected on support and fragility, not on contract.

## Ban risk

Primary sources fetched directly. **The pattern that actually got enforced is not the pattern you would be in — but one clause still reaches you.**

- **Prohibited, explicitly.** `code.claude.com/docs/en/legal-and-compliance`: *"Anthropic does not permit third-party developers to offer Claude.ai login into their own applications, or to route requests through Free, Pro, or Max plan credentials on behalf of their users... may do so without prior notice."* This targets **a third party intermediating credentials for other users** — not a single user's local setup.
- **The clause with the broadest reach.** Consumer Terms §3: *"You also must not abuse, harm, interfere with, or disrupt our Services, including... bypassing any of our systems or protective measures."* On a plain reading "protective measures" means rate limits, abuse controls, safety filters and auth; the RC gate is a product-compatibility check, and routing around it makes nothing less secure. So this is **probably not a breach** — the exposure is that the clause is broad and undefined, and §13 makes any material breach a no-notice termination ground, so Anthropic *could* read a deliberate workaround of a gate they tightened on purpose as "bypassing our systems". Nothing says they would.
- **Merely unsupported.** Pointing Claude Code at a gateway is called unsupported, not prohibited (C3). The Usage Policy has no proxy clause at all — a gap, not a permission.
- **Enforcement that happened.** 2026-01-09: subscription OAuth tokens blocked from OpenCode, Cline, Roo Code. 2026-04-04: subscriptions stopped covering OpenClaw/OpenCode-style harnesses. Both concern *a different client* using subscription credentials. **No incident found naming a router or proxy of the shape discussed here.** (Press reporting — TechCrunch, The Register — quoting named staff; secondary but solid.)

**The asymmetry that decides it:** you would put the Max subscription — which is also what powers Remote Control, the thing you are trying to keep — behind a workaround that is unsupported and breaks silently on a version bump. Detection is plausible too: a TLS-terminating proxy changes TLS fingerprints and header ordering even when it forwards bytes faithfully.

## Why Anthropic does not let you use other models

**No formal statement exists** — no blog post, changelog or docs page gives a reason. What exists is press-reported staff comment: Boris Cherny citing *"engineering constraints"* and wanting to *"make it clear and explicit"* what is supported; Thariq Shihipar citing unusual traffic patterns breaking their debugging. Both secondary.

Two honest non-mysterious reasons beyond that: Claude Code is a distribution channel for Claude, and the loop is genuinely Claude-shaped — prompt formats, tool schemas, retries, prompt caching and compaction. Several seats made the same point independently: **a foreign model driving Claude Code's loop through a translation shim performs worse than that family's own harness**, which you already have in OpenCode and codex-companion. The picker row is partly a fake prize on its own terms.

## Two stale items in the repo

1. **`claude/rc-direct-settings.json` is a no-op**, and the `claude()` wrapper still prepends it to every interactive session and to `remote-control`/`rc`/`agents`. Three council seats flagged it. It is harmless to recommendation (b): the wrapper skips it whenever the caller supplies its own `--settings` (`config/aliases/claude.sh:209`), and a worker spawned from bash never goes through the zsh wrapper at all. Delete it for tidiness or leave it — low stakes either way.
2. **`.claude/rules/dotfiles-settings.md` says `claude/settings.json` carries the gateway URL as a permanent working-tree diff "on purpose".** It does not — neither the committed file nor the deployed `~/.claude/settings.json` has any `ANTHROPIC_*` key. Matches the 2026-08-18 learning; the rule text should be re-scoped to "if the gateway is ever re-enabled". This one matters because it will mislead whoever tries this next.

## What breaks quietly in the recommended design

| Failure | Detector |
|---|---|
| **Finding 1 reborn** — a worker fails and Claude paraphrases an answer as "Kimi said" | Workers return raw provenance (provider, exact slug, generation ID, token counts) that the skill prints verbatim; hard-error on non-2xx; `gemini` suggested a nonce-stamped envelope the model cannot fabricate |
| **Keyless workers** — direnv keys absent in the spawned env | MCP server does a fail-fast key preflight and **refuses to register the tools**. A missing tool is loud; a failing tool is quiet |
| **Slug rot** — OpenRouter renames an alias that resolves back to a Claude model, making the "council" one family | `openrouter-cli drift` already covers part of this; add a canary asserting the echoed `model` field |
| **Version-bump regression** — C1 already proved the pattern | Post-upgrade smoke test: RC handshake works ∧ no `ANTHROPIC_BASE_URL` ∧ each worker answers from the requested family. Note `/remote-control` reportedly degrades to "unknown command" without saying why (issue #89216, unverified) |
| **Worker hangs** on an interactive prompt in headless mode | `timeout --signal=KILL`, stderr captured into the failure payload, timeout treated as "no answer" |
| **Cost creep** — Claude can now spend on councils autonomously, outside the token ledger | Per-tool spend log plus a session budget cap. **This council run cost $2.30 against a $0.43 floor estimate — 5.3x, all reasoning tokens.** |

## Blind spots the panel had, including in my own brief

- **Data governance went unweighed by all eight seats**: a `council` or `opencode` worker ships repo code to eight-plus providers under their own retention and training policies. For this setup that is material and belongs in the MCP server's design.
- **The romp fallback's own weak link is unhardened** — the `socat` forwarder does not survive a reboot, and every "use romp instead of RC" answer leaned on it silently. The real fix is one Tailscale DNS toggle on the phone.
- **Nobody priced the MCP server's build cost** against simply improving CLI ergonomics — arguably the actual decision.
- **Dual-auth economics**: RC needs the OAuth subscription, workers burn API spend. The hybrid pays both, unquantified.
