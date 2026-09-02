# Remote Control and foreign models: route at the tool layer, or move the endpoint without breaking TLS

**Status:** measured on Claude Code v2.1.252, 2026-09-01. Eight-family council consulted ($2.30). Durable copy of the evidence: `docs/remote-control-and-foreign-models.md`.

## The question, and the answer in one paragraph

Can one Claude Code session have native Remote Control **and** non-Claude models (GPT, Kimi, GLM, Gemini, Qwen, Grok) as first-class citizens — in the `/model` picker and as subagents? **Not in the form asked.** The gate that disables Remote Control is the same condition that enables a multi-model picker, so the two are mutually exclusive in one process by construction. Every route falls into one of three shapes — move the endpoint, sit in the connection, or stay out of it — and only the third keeps Remote Control with no workaround. One variant of the first keeps the gate passing and TLS intact, and is the only workaround worth testing.

## The finding that matters more than the architecture

**An unrecognised model ID does not fail. Claude Code silently answers from your default model.**

| Path | Requested | Actually answered | Only signal |
|---|---|---|---|
| `claude -p --model openai/gpt-5.6-sol` | GPT | `claude-opus-5` | stderr `[claude-code:unrecognized_model]` |
| agent file, `model: openai/gpt-5.6-sol` | GPT | `claude-opus-5` | same line, `query_source: agent:custom:…` |
| `ANTHROPIC_CUSTOM_MODEL_OPTION=x`, `--model x` | custom | `claude-opus-5` | same |

The agent loads and runs normally. A subagent's caller never sees stderr. So an agent file naming a foreign model fabricates a multi-family result quietly — this sharpens the 2026-08-25 deletion of the foreign-model agent files: the "hard-fail" branch that note allowed for does not happen on this version.

It also means the model field carries no routing signal on the wire: substitution happens before the request leaves the process, so anything sitting in the connection sees `claude-opus-5` on every request.

## How Remote Control works, and why it demands a first-party endpoint

Confidence ~70% on internals, from bundle naming (`tengu_ccr_bridge`, `CLAUDE_CODE_USE_CCR_V2`, `SESSION_INGRESS_URL`) plus the docs. The local session opens an authenticated channel to Anthropic's relay. The phone app never touches the machine: it talks to Anthropic, which relays messages and permission prompts to the session and answers back. Tools still execute locally. That relay is tied to the claude.ai identity, so it requires OAuth rather than an API key, and Anthropic wants to see the relayed session end to end, which is the stated reason for the first-party rule.

The gate itself, verbatim from the bundle:

```js
function Nw(e){try{let t=new URL(e).host;return["api.anthropic.com"].includes(t)}catch{return!1}}
function DB(){let e=process.env.ANTHROPIC_BASE_URL;if(!e)return!0;return Nw(e)}
```

It compares the **configured** host string. No socket, no DNS, no check of where traffic actually goes. Unset passes; so do `http://`, a trailing slash and a subpath. `_CLAUDE_CODE_ASSUME_FIRST_PARTY_BASE_URL` is explicitly exempted. It is re-evaluated live, not once at startup.

And the multi-model picker needs exactly the opposite:

```js
function mu(){if(!a.CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY)return!1;
              if(Oe()!=="firstParty")return!1;if(jo())return!1;
              if(!a.ANTHROPIC_BASE_URL)return!1;return!0}
```

Discovery populates several `/model` rows from `<base>/v1/models`, but only when the base URL is set **and** fails the gate. That is the whole conflict in two functions.

## Every route is one of three shapes

| Shape | Mechanism | Remote Control | TLS on external hops | Foreign models | Support status |
|---|---|---|---|---|---|
| **1a. Move the endpoint** — model-router (2026-08) | `ANTHROPIC_BASE_URL=http://127.0.0.1:<port>`; router speaks TLS outward to Anthropic and OpenRouter, translating formats | **off** — gate fires | intact, no CA | full menu via discovery; subagents by name | unsupported |
| **1b. Move the endpoint, keep the host** — *untested* | `ANTHROPIC_BASE_URL=http://api.anthropic.com` + `/etc/hosts` → `127.0.0.1`; router on port 80 | **gate passes** | intact, no CA | as 1a | unsupported |
| **2. Sit in the connection** — MITM proxy | `https_proxy` + own CA via `NODE_EXTRA_CA_CERTS`; proxy terminates TLS, reads body, re-encrypts | gate passes | **broken** on the client leg | unlimited subagents if routed on a system-prompt sentinel; picker: one row at most | unsupported |
| **3a. Stay out of it** — MCP server | Claude Code spawns the server over stdio; tools `ask`, `council`, `delegate` call OpenRouter / `opencode` / `codex-companion` | **on**, untouched | intact | as tool results; provenance enforceable | supported |
| **3b. Stay out of it** — child Claude Code | Parent (RC on) spawns `claude --settings gateway.json`, a 1a session in a worktree | parent **on** | intact | child gets the real loop on a foreign model | unsupported for the child only |
| **3c. Stay out of it** — worker CLIs | `opencode run`, `codex-companion` | on | intact | each family's own harness | supported |

### Shape 1 keeps TLS because the plaintext leg is loopback

Claude Code speaks plain HTTP to a local router; the router opens its own TLS connections outward. Nothing is decrypted that was ever encrypted. 1b differs from 1a only in what the client *believes* the host is, which is all the gate checks. Open questions for 1b, both testable without any MITM: whether the client refuses `http://` for OAuth traffic, and whether the Remote Control bridge resolves through the same hosts entry — if so the router must pass that channel through untouched. It needs sudo for `/etc/hosts` and port 80, and the router must reach the real Anthropic by IP or a separate resolver.

### Shape 2 only works by breaking TLS

An HTTPS proxy sees `CONNECT api.anthropic.com:443` and nothing else. The routing signal is inside the encrypted body, so the proxy must terminate TLS with its own CA to read it. The client honours lowercase `https_proxy` (measured) and the bundle has no certificate pinning (measured), so it would work — at the cost of your own OAuth traffic passing through a process you wrote, and a translation layer that must never fall back to Claude on an OpenRouter error or the silent-fallback bug returns one layer down.

### Shape 3 leaves Anthropic-bound traffic untouched

MCP: at startup the server advertises tools with JSON schemas; Claude emits a tool call like any built-in; Claude Code runs its permission check, calls the server, and the return value lands in the transcript as a `tool_result`. The foreign model's answer enters Claude's context as **data**; the foreign model never enters Claude Code's loop. Because tool calls go through the normal permission system, the prompt *should* surface in Remote Control's phone approval UI — a council claim, not yet tested. What you do not get: a foreign model reading the live transcript as a true shared-context subagent. Two seats (`gpt-5.6-sol`, `qwen3.8-max`) were emphatic that this residual gap is the one thing that would justify Shape 1.

## Terms of service, corrected

An earlier draft called Shape 2 a likely breach of Consumer Terms §3 ("bypassing any of our systems or protective measures"). That was stretching the clause: on a plain reading "protective measures" means rate limits, abuse controls, safety filters and auth, and routing around a compatibility gate makes nothing less secure. Corrected position:

- **Explicitly prohibited:** third parties routing *other users'* requests through subscription credentials (`legal-and-compliance`, no-notice enforcement). Not this shape.
- **Explicitly unsupported, not prohibited:** routing Claude Code to non-Claude models through any gateway (`llm-gateway`). Shapes 1 and 2.
- **Enforcement that happened** (2026-01-09, 2026-04-04): other harnesses — OpenCode, Cline, Roo Code — using subscription OAuth. Not this shape; no incident found naming a router or proxy.
- **Residual exposure:** the §3 clause is broad and undefined, and any material breach is a no-notice termination ground, so a deliberate workaround of a gate tightened on purpose *could* be read that way. Nothing says it would.

**Why Claude Code is Claude-only:** no formal statement exists. Press-reported staff comment cites engineering constraints and traffic patterns that break debugging. Beyond that, the loop is Claude-shaped — prompt formats, tool schemas, retries, caching, compaction — and several seats noted a foreign model driving it through a shim performs worse than in its own harness.

## Recommendation and the one experiment left

**Build Shape 3a now.** It is supported, keeps Remote Control everywhere, gives provenance for free, and the workers already exist; the marginal cost is one server with a fail-fast key preflight and a hard rule that a missing tool is loud and a failing one never paraphrased.

**Test Shape 1b once**, from a shell rather than a sandboxed session: does the client accept `http://api.anthropic.com`, and does the Remote Control bridge still connect with the hosts entry in place? If both hold, 1b is a full foreign-model menu plus native Remote Control with TLS intact and no certificate — the closest thing to the original ask — at the price of being unsupported and liable to break silently on any version bump.

**Do not build Shape 2.** It buys nothing 1b does not, and it is the only shape that decrypts your own traffic.

## Quiet failures in the recommended design, and the detector for each

| Failure | Detector |
|---|---|
| Worker fails; Claude paraphrases an answer as "Kimi said" — the silent fallback reborn | Server returns provider, exact slug, generation id, token counts; skill prints them verbatim; non-2xx is a hard error |
| Keys absent in the spawned environment | Server preflights keys and refuses to register tools without them |
| OpenRouter renames a slug that resolves back to a Claude model, so a "council" is one family | `openrouter-cli drift`, plus a canary on the echoed `model` field |
| A version bump re-tightens the gate or changes the loop | Post-upgrade smoke test: Remote Control connects, base URL unset, each worker answers from the requested family |
| Headless worker blocks on an interactive prompt | `timeout --signal=KILL`, stderr captured into the failure payload |
| Claude spends on councils autonomously, outside the token ledger | Per-tool spend log and a session cap; this run cost 5.3x its `--dry-run` floor, all reasoning tokens |

## What the panel missed, including in the brief it was given

Data governance went unweighed by all eight seats: a council or `opencode` worker ships repo text to eight providers under their own retention and training policies, which belongs in the server's design. Nobody priced the MCP server's build cost against simply improving CLI ergonomics. Nobody costed the dual auth the hybrid requires — an OAuth subscription for Remote Control and API spend for workers. And the romp-over-Tailscale fallback everyone leaned on has an unhardened `socat` link that does not survive a reboot.
