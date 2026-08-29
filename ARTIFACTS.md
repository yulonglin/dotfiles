# Artifacts and Resources for dotfiles

The pages this repo's work has produced, and where the things it depends on live. Every row states what the page established, so this file can be read instead of opened.

Maintained per `~/.claude/skills/artifacts-sync/SKILL.md` — rows are written at publish time, because neither the repo nor the publishing org can be recovered from the gallery afterwards. Run `/artifacts-sync` to reconcile.

## Artifacts

| Artifact | Org | Status | Source | Public | Updated |
|---|---|---|---|---|---|
| [Artifacts and Resources for dotfiles](https://claude.ai/code/artifact/8ad029a9-5ad8-431f-9e1d-88532cb89802) — this index; a living index may name its function rather than assert a finding | see note | live | `ARTIFACTS.md` | no | 2026-08-29 |
| [Task Lists Follow the Shell](https://claude.ai/code/artifact/242e3dbb-600d-44b4-87ae-9a688542e132) — every session already gets its own task list, so the wrapper must never export a shared ID; the daemon is the last place a stale one hides | see note | live | — | no | 2026-08-28 |
| [Most of the setup now loads on demand](https://claude.ai/code/artifact/26852bc6-e36f-4b55-97db-d0d3473a0b49) — the always-loaded rules tier fell from ~76 KB to ~28 KB by moving activity-scoped procedure into skills | see note | live | — | no | 2026-08-28 |
| [Pick The House Chart Style](https://claude.ai/code/artifact/aecdec3a-7fb5-43b3-8841-c4d176de379d) — the chart-style options put side by side for a decision | see note | live | — | no | 2026-08-28 |
| [Two Files Earn Their Keep](https://claude.ai/code/artifact/c2c019d6-dc78-4f8e-88b8-8d716bfad39d) — which of the plotting-library files justified staying | see note | live | — | no | 2026-08-28 |
| [Timestamps Already Land Each Turn; The Gap Is Inside Long Turns](https://claude.ai/code/artifact/842dfe8e-e902-416d-86eb-aa7d5042b659) — per-turn timestamp injection is already solved; only long single turns lack a time signal | see note | live | — | no | 2026-08-27 |
| [The Remote Control Inversion](https://claude.ai/code/artifact/fadb27e4-dd05-40b2-940e-3fb674ca6251) — a global `ANTHROPIC_BASE_URL` hard-disables Remote Control, which is why the model-router gateway was unwired | see note | live | — | no | 2026-08-19 |
| [Alias Audit](https://claude.ai/code/artifact/739598b0-362d-4aaa-a8c2-c77775be5eb4) — alias files fight over names by source order; the set was cut 161 → ~110 against two months of shell history | see note | live | — | no | 2026-08-18 |
| [Tool-Backed Agents](https://claude.ai/code/artifact/4c124679-7346-4dc5-9cb4-75889320aaf4) — which agents actually invoke their CLI rather than answering from their own reasoning | see note | live | — | no | 2026-08-18 |

**Org, and why it is not filled in yet.** Every row above appeared in the `Artifact action: list` result of 2026-08-29, so all of them are in the org this machine is currently signed into — that part is evidence, not inference. The org's *name* is missing because `claude auth status` returns `orgName: null` on this session, which is authenticated by `ANTHROPIC_API_KEY` rather than a claude.ai login. Run `/artifacts-sync` from a `/login` session to stamp the real name.

**These eight rows are retro-attributed.** They were matched to this repo by subject matter against the Learnings section of `CLAUDE.md`, not by a source file on disk, because no built HTML was kept for any of them. Every row published from now on gets its source path recorded at publish time. Treat the two least certain — *Two Files Earn Their Keep* and *Tool-Backed Agents* — as provisional until confirmed.

## Other resources

| Resource | What it is | Where |
|---|---|---|
| Artifact gallery | Every artifact on the account, across repos, newest first and truncated by a listing window | [claude.ai/code/artifacts](https://claude.ai/code/artifacts) |
| `dotfiles-personal` | The private repo holding `plans/`, `.remember/`, personal `docs/`, `config/machines.conf` — this repo is public, so personal working artifacts never live on a branch here | private GitHub repo |
| Bitwarden Secrets Manager | API keys, reached per-project via `setup-envrc` and direnv, never globally exported | token at `~/.config/bws/token` |
| Global rules | Always-loaded judgment; activity-scoped procedure lives in skills, indexed by `pointers.md` | `claude/rules/` |

## Publishing a page publicly is an org decision, not a local one

Under a Team or Enterprise org, public sharing is off until an **Owner** enables External sharing, and re-disabling it kills every existing public link at once. So the Public column above is `no` throughout, and the two available fallbacks are a self-hosted mirror of the built HTML, or publishing outward-facing pages from a personal Pro/Max account where public is the only sharing mode. The full policy, including why no stored token can publish into another org, is in the `artifacts-sync` skill.
