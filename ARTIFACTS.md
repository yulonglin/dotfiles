# Artifacts and Resources for dotfiles

The pages this repo's work has produced, and where the things it depends on live. Every row states what the page established, so this file can be read instead of opened.

Maintained per `~/.claude/skills/artifacts-sync/SKILL.md` — rows are written at publish time, because neither the repo nor the publishing org can be recovered from the gallery afterwards. Run `/artifacts-sync` to reconcile.

**There is currently no live published index page.** The original ([8ad029a9](https://claude.ai/code/artifact/8ad029a9-5ad8-431f-9e1d-88532cb89802)) sits in another of the account's orgs and refuses in-place updates from this machine; its replacement ([8d035fe5](https://claude.ai/code/artifact/8d035fe5-a206-4d80-ac2f-c32ca0db743c)) was published on 2026-08-31 and deleted the same day, as was the report published alongside it. **This Markdown file is therefore the only current index** — republish it only when someone actually wants a hosted copy, rather than automatically, since the last two were removed shortly after publication.

## Artifacts

| Artifact | Org | Status | Source | Public | Updated |
|---|---|---|---|---|---|
| [Artifacts and Resources for dotfiles](https://claude.ai/code/artifact/8d035fe5-a206-4d80-ac2f-c32ca0db743c) — this index, published 2026-08-31 and deleted the same day | unknown | archived — deleted upstream; the URL 404s | `ARTIFACTS.md` | no | 2026-08-31 |
| [Artifacts and Resources for dotfiles (previous URL)](https://claude.ai/code/artifact/8ad029a9-5ad8-431f-9e1d-88532cb89802) — org-locked former home of this index | see note | superseded — by [the current index](https://claude.ai/code/artifact/8d035fe5-a206-4d80-ac2f-c32ca0db743c) | `ARTIFACTS.md` | no | 2026-08-29 |
| [Six Casks Marked for Removal and Twenty-Seven Apps Join the Registry](https://claude.ai/code/artifact/1e36e85b-83c6-46e9-9fb7-df929387dbb4) — the Brewfile listed 40 entries while the Mac carried 53 casks and 20 App Store apps; `apps.conf` gained `default=exclude` and `app-picker` gained `--installed` and `--audit`, the Brewfile now states 65 entries, and six casks (cursor, codex-app, codexbar, conductor, espanso, aqua-voice) plus two third-party taps are named for removal | unknown | done | [`artifacts/brewfile-audit/report.md`](artifacts/brewfile-audit/report.md) | no | 2026-09-03 |
| [Remote Control and Foreign Models](https://claude.ai/code/artifact/d224e859-2f4d-452c-9781-5ab3941e57cf) — native Remote Control and a non-Claude `/model` menu are mutually exclusive in one process by construction; an unrecognised model ID silently answers from the default Claude model; route at the tool layer, and the one workaround worth a test moves the endpoint without breaking TLS | unknown (claude.ai login; `claude auth status` reports `orgName: null`) | live | `artifacts/remote-control-and-foreign-models/` | no | 2026-09-03 |
| [Installers Stop Stalling; Profiles Get Names](https://claude.ai/code/artifact/8d07cd03-d6f6-4b86-b72c-1ce1c03d2191) — the stall was never the prompts: a silent `cargo build --quiet` and untimed fetches at the top of both scripts, plus five more untimed `curl \| sh` installers found only by checking the class; fixed with deadlines and purpose-named profiles (bare/standard/agent/devbox) on draft PR #77, CI green | unknown (see note) | live | — (built from the job's gitignored `tmp/`, not kept) | no | 2026-08-31 |
| [README Trimmed; Two Proposals Await](https://claude.ai/code/artifact/720f1fce-0147-47ef-a9f5-9afb98768445) — the same report at its original URL | unknown | archived — deleted upstream; the URL 404s | — | no | 2026-08-31 |
| [Context Ledger](https://claude.ai/code/artifact/439482e4-0d10-4715-a7d1-add2805e614a) — 134 components cost 17,246 tok every session, 60% of it always-loaded prose rather than skill descriptions; 67 of 120 skills/agents have never been invoked, and the rules cite four skills with zero uses | see note | live | `artifacts/context-ledger/` | no | 2026-08-29 |
| [The Second Clear](https://claude.ai/code/artifact/46e4abb8-b37f-4597-8f47-6176f4fa4649) — nine models across three families refuse the literal "clear uncopied": every comment predating the feature carries no stamp, so it reads as uncopied and the button would wipe the page. Ship "Delete copied" instead, on the file's existing arm-and-confirm. Round 1 ran against a description 59 commits stale; the corrected re-run flipped the wording to "copied out" unanimously | see note | done | `tmp/anlayer/playground.html` (untracked scratch) | no | 2026-09-01 |
| [Task Lists Follow the Shell](https://claude.ai/code/artifact/242e3dbb-600d-44b4-87ae-9a688542e132) — every session already gets its own task list, so the wrapper must never export a shared ID; the daemon is the last place a stale one hides | see note | done | — | no | 2026-08-28 |
| [Most of the setup now loads on demand](https://claude.ai/code/artifact/26852bc6-e36f-4b55-97db-d0d3473a0b49) — the always-loaded rules tier fell from ~76 KB to ~28 KB by moving activity-scoped procedure into skills | see note | done | — | no | 2026-08-28 |
| [Pick The House Chart Style](https://claude.ai/code/artifact/aecdec3a-7fb5-43b3-8841-c4d176de379d) — the chart-style options put side by side for a decision | see note | done | — | no | 2026-08-28 |
| [Two Files Earn Their Keep](https://claude.ai/code/artifact/c2c019d6-dc78-4f8e-88b8-8d716bfad39d) — which of the plotting-library files justified staying | see note | done | — | no | 2026-08-28 |
| [Timestamps Already Land Each Turn; The Gap Is Inside Long Turns](https://claude.ai/code/artifact/842dfe8e-e902-416d-86eb-aa7d5042b659) — per-turn timestamp injection is already solved; only long single turns lack a time signal | see note | done | — | no | 2026-08-27 |
| [The Remote Control Inversion](https://claude.ai/code/artifact/fadb27e4-dd05-40b2-940e-3fb674ca6251) — a global `ANTHROPIC_BASE_URL` hard-disables Remote Control, which is why the model-router gateway was unwired | see note | done | — | no | 2026-08-19 |
| [Alias Audit](https://claude.ai/code/artifact/739598b0-362d-4aaa-a8c2-c77775be5eb4) — alias files fight over names by source order; the set was cut 161 → ~110 against two months of shell history | see note | done | — | no | 2026-08-18 |
| [Tool-Backed Agents](https://claude.ai/code/artifact/4c124679-7346-4dc5-9cb4-75889320aaf4) — which agents actually invoke their CLI rather than answering from their own reasoning | see note | done | — | no | 2026-08-18 |

**Status vocabulary.** `live` — still being updated, cite it. `done` — the work is finished and its conclusions stand, still quotable. `archived` — deliberately retired, do not cite, row kept for its history and comment threads. `superseded` — replaced by a specific newer page, and the row links to it. `elsewhere` — published under an org this machine is not signed into. `done` is an achievement and `archived` is a retirement; only `superseded` implies a successor exists. Nothing is ever deleted from this table.

Everything above except this index and *README Trimmed; Two Proposals Await* (still collecting decisions) is `done`: each reports finished work whose conclusions still hold. Nothing here is `archived` yet.

**Org, and why it is not filled in yet.** Every row above appeared in the `Artifact action: list` result of 2026-08-29. Whether that *means* they are in the currently signed-in org depends on the listing being org-scoped, which the Claude Code docs nowhere state — so read "see note" as genuinely unknown rather than as a name I merely failed to type. The org's *name* is missing only because `claude auth status` returned `orgName: null` on the session that wrote this file — while reporting `authMethod: "claude.ai"` and publishing the index page without trouble. A null org therefore diagnoses nothing about how the session is authenticated; it is simply a field that is sometimes unpopulated. Run `/artifacts-sync` from a session where it is populated to stamp the real name.

**These eight rows are retro-attributed.** They were matched to this repo by subject matter against the Learnings section of `CLAUDE.md`, not by a source file on disk, because no built HTML was kept for any of them. Every row published from now on gets its source path recorded at publish time. Treat the two least certain — *Two Files Earn Their Keep* and *Tool-Backed Agents* — as provisional until confirmed.

## Other resources

| Resource | What it is | Where |
|---|---|---|
| Artifact gallery | Every artifact on the account, across repos, newest first and truncated by a listing window | [claude.ai/code/artifacts](https://claude.ai/code/artifacts) |
| `dotfiles-personal` | The private repo holding `plans/`, `.remember/`, personal `docs/`, `config/machines.conf` — this repo is public, so personal working artifacts never live on a branch here | private GitHub repo |
| Bitwarden Secrets Manager | API keys, reached through the `secrets` command; never exported into every shell | token at `~/.config/bws/token` |
| Global rules | Always-loaded judgment; activity-scoped procedure lives in skills, indexed by `catalog` | `claude/rules/` |

## Publishing a page publicly is an org decision, not a local one

Under a Team or Enterprise org, public sharing is off until an **Owner** enables External sharing. Re-disabling it blocks access through every existing public link at once, without changing any artifact's audience — access resumes if it is turned back on, so the links are suspended rather than destroyed. The risk is an outage nobody here can fix, not permanent loss.

So the Public column above is `no` throughout. Two fallbacks: a self-hosted mirror of the built HTML, which no org toggle can reach; or publishing outward-facing pages from a personal Pro/Max account, where public is the only sharing mode — though that second one does **not** rescue a connector-backed page, which stays private on every plan. The full policy, including why no stored token can publish into another org, is in the `artifacts-sync` skill.
