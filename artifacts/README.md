# Artifact sources live here, in git — and so does the built page

A published Artifact lives on someone else's server, under an org you may leave. The page can become unreachable without anything local changing: an account switch, an org's External-sharing toggle, a plan change. So **the source that rebuilds the page AND the built HTML are the durable copy, and both belong in version control** — not in `tmp/`, not in `$TMPDIR`, not in a worktree that gets deleted.

This directory is the standard home for both. `ARTIFACTS.md` in the repo root maps each published URL to what the page established; its **Source** column points here.

## Why this exists

`ARTIFACTS.md` records that eight of its rows are retro-attributed, matched to this repo by subject matter, "because no built HTML was kept for any of them". Those pages cannot be rebuilt, corrected or re-published — only read, and only while the link resolves. The convention below is what stops that recurring.

The failure is easy to walk into. A page built in `tmp/` publishes perfectly and looks finished; the loss is invisible until the worktree is removed or the org changes, which is long after anyone would connect the two.

## Layout

```
artifacts/
  <slug>/                 slug matches the artifact's title, kebab-case
    meta.yml              url, title, org, first published, last updated
    <source>              what rebuilds the page: .md, .html, or a build script
    <slug>.html           the built page, committed beside the source
    build/                gitignored — intermediates and scratch only
```

**Commit the source and the built HTML, for every artifact** (Yulong, 2026-09-01 — this reversed the earlier inputs-only rule). The committed HTML is what the review round-trip runs on: the published page is where Yulong comments and suggests edits, the session applies them to the source, rebuilds, and republishes — and source, HTML and published page must stay one thing. Rebuild and republish update the committed HTML **in the same commit as the source change**, so the repo copy always matches what is live. `build/` remains gitignored scratch for intermediates that a build script regenerates.

An input that is itself ephemeral — a scan of the live environment, a query result, an API response — cannot be regenerated later because the thing it measured has moved on. Snapshot that alongside the source and say in `meta.yml` when it was taken.

`meta.yml` carries what the gallery cannot: the **publishing org**, which is unrecoverable afterwards and is exactly what breaks when accounts change.

Name the source for what it is (`spec.md`, `plan.md`) — `md2artifact` qualifies a generic stem with the artifact directory, so the comment key is `review-<slug>-spec` rather than the `review-spec` that every spec in the gallery would otherwise share. All artifacts are read from one origin, so a shared key means two pages showing each other's comments; `tests/test_md2artifact_key.py` pins it. A specific stem keeps its historic key, so no already-published page is orphaned.

## The rule

Never pass a path under `tmp/`, `$TMPDIR`, `/tmp`, or any gitignored directory to the Artifact tool. Publish the committed HTML at `artifacts/<slug>/<slug>.html` — publishing is the last step, not the record, and the commit comes first.

For a repo whose artifacts are personal rather than about the code, the same layout goes in the private `dotfiles-personal` repo instead. This repo is public; personal working artifacts never land on a branch here.

## Worked example

`editable-review-layer/` is the first one built under the commit-the-HTML rule: `spec.md` is the source, `spec.html` the committed page, and both move together in every commit. `context-ledger/` predates the rule — its 1.5 MB page was judged too large to commit at the time, so only its pipeline plus the non-regenerable environment scan are stored; treat it as the grandfathered exception, not the pattern. If a future page is ever genuinely too large, that carve-out is Yulong's call, noted in its `meta.yml`.
