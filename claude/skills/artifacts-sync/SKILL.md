---
name: artifacts-sync
description: Maintain and reconcile a repo's ARTIFACTS.md — the index mapping artifact URLs to what they established. Covers the row schema, recording the publishing org, public-sharing limits under a Team/Enterprise org, and the reconcile pass. Use when publishing an artifact and recording it, when a link 404s, after switching Claude accounts or orgs, or on "sync/audit/refresh the artifact index".
---

# Keep ARTIFACTS.md and the Index Page in Step

Each repo keeps one index of its artifacts, each row stating the finding rather than only the title, and one topic keeps one link — update a page in place rather than minting a URL per revision. This skill owns the shape of that index and the pass that repairs it. Building the pages themselves is `artifact-writing`; this is about not losing them afterwards.

The canonical filename is **`ARTIFACTS.md` at the repo root**. One per repo.

## Write the row at publish time, because the org cannot be recovered later

The moment an `Artifact` publish returns a URL, add or update its row in the same turn, before reporting back. Two facts are available then and never again: which repo the page belongs to, and which org published it. `Artifact action: list` carries neither.

| Column | Content |
|---|---|
| Artifact | The linked title. It already asserts the finding, so it doubles as the summary; give a legacy topic-titled page a one-line gloss until it is renamed |
| Org | `orgName` from `claude auth status` **at publish time** |
| Status | one of the five below — nothing else |
| Source | Repo-relative path of the Markdown or HTML it was built from, or `—` when nothing was kept |
| Public | `no`, or the public mirror URL |
| Updated | ISO date of the last publish |

### Status separates "still moving" from "finished" from "retired"

A single `live` flag collapses three different things a reader needs to tell apart: a page still being updated, a page whose work is finished and whose conclusions stand, and a page nobody should cite any more. Five values, and no others:

| Status | Meaning | Still cite it? |
|---|---|---|
| `live` | The current page for this topic, still being updated | yes |
| `done` | The work it reports is finished; the page is final and its conclusions stand | yes |
| `archived` | Deliberately retired — the topic moved on, or the work was abandoned | no, but keep the row |
| `superseded` | Replaced by a specific newer page; the row **must** link to it | no, follow the link |
| `elsewhere` | Published under an org this machine is not signed into | cannot reach it from here |

`done` and `archived` are the pair people conflate. **`done` is an achievement, `archived` is a retirement**: a finished experiment write-up whose numbers still hold is `done` forever and stays quotable, while a page whose premise was abandoned is `archived` even if it was never replaced. Only `superseded` implies a successor exists, which is why it is the one status that carries a mandatory link.

Nothing is ever deleted. Deleting a row destroys the only trace of where a stale link points, and the comment threads on a retired page are still the user's work.

`ARTIFACTS.md` is itself published as the repo's index page and carries its own row. A living index may name its function rather than assert a finding — the documented exception to the title rule.

## Absence from the listing is three different states, so record the org instead of probing

**Assumption, not documented fact:** the reconcile table below rests on `Artifact action: list` returning only the current org's artifacts. The Claude Code docs never say this — they describe `/artifacts` as listing "every artifact you own and every artifact shared with you", with no mention of org scoping. Only the listing window is documented, and only as the tool's `limit` (default 25, max 50). So treat org-scoping as an unverified premise: it matches observed behaviour, and the whole "elsewhere" verdict depends on it. If it turns out the listing spans orgs, `elsewhere` collapses into `deleted` and this table needs rewriting. Someone should confirm it directly by listing from two orgs.

Granting the premise: a URL missing from the listing is ambiguous between *old*, *deleted*, and *published under another org*. Recording Org at publish time is what disambiguates — a missing URL whose recorded org differs from the current `orgName` is `elsewhere`, not lost. That is the value of the column regardless of how the listing scopes, because the org is unrecoverable afterwards either way.

**Never demote a row to `superseded` on a listing miss alone.** That transition is only correct when a replacement page exists, and it always carries a link to the replacement. This is the commonest way a sync pass destroys information.

Equally, a sync pass never invents `done` or `archived`. Both are editorial judgements about whether work finished or was abandoned, and neither is visible in the gallery — they are set by the person or session that knows the work ended, not inferred from dates. An old `live` row is a prompt to ask, not a licence to retire it.

## The reconcile pass

Establish the org first — every verdict below is relative to it, so skipping this produces confident nonsense after an account switch:

```bash
claude auth status
```

`orgName` can come back `null` on a session that publishes perfectly well — measured 2026-08-29, a session reporting `authMethod: "claude.ai"`, `orgName: null` published without trouble. So a null org is not a diagnosis of anything, least of all of API-key auth. Record `unknown` and stamp the real name from a session where the field is populated; never stamp an org you did not read.

Then list the gallery and join **by URL, never by title** — titles get rewritten, and two artifacts have already shared one in this gallery ("Monitoring Beyond CoT" appears twice under different UUIDs).

```
Artifact action: list, scope: "mine", limit: 50
```

| Row's recorded org | In the listing? | Verdict |
|---|---|---|
| = current `orgName` | yes | `live` — refresh Updated |
| = current `orgName` | no | ambiguous: outside the listing window, or deleted. Leave status unchanged, flag it in the report |
| ≠ current `orgName` | no | `elsewhere` — expected, not a fault. Do not try to fetch it |
| any | listed but not in the file | unrecorded — attribute only on evidence |

Attribute an unrecorded artifact to this repo only when something ties it here: a source file on disk, a commit on the same date, a subject that is unambiguously this repo's. Attribution by vibe pollutes every later sync — when it belongs elsewhere, leave it alone, and mark anything attributed after the fact as retro-attributed.

Check each row's Source path still exists. A row whose source is gone cannot be rebuilt after an org switch, which is exactly when rebuilding matters. Report those; do not delete the row.

### A published page is frozen at the tooling that built it

`md2review` inlines the annotation layer into the HTML rather than linking it, so every page carries its own copy of whatever version was current when it was built. Fixing the layer fixes **future builds only**. Confirmed the hard way on 2026-08-29: the select-to-comment box flickered on older pages while newly published ones behaved, long after the 2026-08-28 fix landed — the builder on PATH was correct and its browser suite passed, because the broken copies were frozen inside pages published before it.

Two consequences. A page showing behaviour the current tooling no longer produces needs a **rebuild and republish**, not a bug report. And a row whose Source is `—` can never get that rebuild, which is why the column is a durability requirement rather than bookkeeping — it is the difference between a page that can be repaired and one that is stuck forever. When a tooling fix matters (data loss, a broken export, an unusable comment box), rebuild the rows that have sources and list the ones that cannot be fixed.

Republish the index in the same pass — a sync that updates only the Markdown leaves the page stale, which is the drift this skill exists to remove:

```bash
md2review ARTIFACTS.md -o "$TMPDIR/artifacts-index.html"
```

Publish with the index's own `url` from its row so it updates in place. On `org_mismatch`, follow `artifact-writing` § in-place update refused: new file path, publish without `url`, supersedes note, then record it here as one `superseded` row plus one new row. Warn before republishing over annotations the user may have added.

Close by reporting counts per verdict, ambiguous rows named individually, and missing sources. Say plainly when nothing changed — a clean sync is a result.

## Public sharing is an org policy, not a setting you can reach

Verified against the Claude Code docs, 2026-08-29:

- On **Pro and Max**, a public link is the only sharing mode, and any artifact can have one.
- On **Team and Enterprise**, public sharing is **off by default**; only an organization **Owner** enables it, under Settings > Claude Code > Capabilities > External sharing. Turning it back off blocks access through every existing public link at once, without changing any artifact's audience — and access resumes if it is re-enabled. So the links are suspended, not destroyed; the risk is an outage you cannot fix yourself, not permanent loss.
- A **connector-backed** artifact can never be public on any plan.
- Native comment threads work **only** on org-shared artifacts. A public artifact cannot take comments, and one with existing threads must have them deleted before it can go public. The `md2review` annotation layer is unaffected, being page-local.

So under a Team or Enterprise org such as MATS, "make this public" is not yours to grant. Two fallbacks, both recorded in the Public column:

- **Self-host the mirror** — the built HTML already exists on disk, so pushing it to GitHub Pages yields a URL no org toggle can revoke. Default for anything that must stay reachable.
- **Publish outward-facing pages from a personal Pro/Max account**, where public is the only mode. Costs org comments and splits the gallery, so reserve it for genuinely external audiences. **This fallback does not rescue a connector-backed page**: on Pro/Max such a page stays private to its author, because no plan allows a connector-backed artifact a public link. A page that must be both public and live-data has to become a self-hosted mirror with the data baked in, or stop calling connectors.

## No credential publishes into an org the session is not signed into

There is no token for this and looking for one is a dead end. The docs require a session signed in with `/login` to a claude.ai account, and state that sessions using an API key, gateway token, or cloud-provider credential cannot publish at all. The artifact lands in whichever org that login resolves to; nothing in the tool call selects an org.

The only candidate mechanism for two orgs on one machine is **two config directories** — `CLAUDE_CONFIG_DIR` relocates Claude Code's home-directory state, so a second directory with its own login could host personal-org sessions beside work-org ones. Treat this as plausible but unverified: the docs say it relocates settings, session history and plugins, and do not name credentials among them. Test it before relying on it, and record the outcome here rather than re-deriving it.
