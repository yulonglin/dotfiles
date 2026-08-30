# Artifact sources live here, in git

A published Artifact lives on someone else's server, under an org you may leave. The page can become unreachable without anything local changing: an account switch, an org's External-sharing toggle, a plan change. So **the source that rebuilds the page is the durable copy, and it belongs in version control** — not in `tmp/`, not in `$TMPDIR`, not in a worktree that gets deleted.

This directory is the standard home for that source. `ARTIFACTS.md` in the repo root maps each published URL to what the page established; its **Source** column points here.

## Why this exists

`ARTIFACTS.md` records that eight of its rows are retro-attributed, matched to this repo by subject matter, "because no built HTML was kept for any of them". Those pages cannot be rebuilt, corrected or re-published — only read, and only while the link resolves. The convention below is what stops that recurring.

The failure is easy to walk into. A page built in `tmp/` publishes perfectly and looks finished; the loss is invisible until the worktree is removed or the org changes, which is long after anyone would connect the two.

## Layout

```
artifacts/
  <slug>/                 slug matches the artifact's title, kebab-case
    meta.yml              url, title, org, first published, last updated
    <source>              what rebuilds the page: .md, .html, or a build script
    build/                gitignored — built output, regenerable, never committed
```

**Commit the inputs, not the output.** A built page is regenerable and often megabytes; `build/` is ignored for that reason. The exception is an input that is itself ephemeral — a scan of the live environment, a query result, an API response — which cannot be regenerated later because the thing it measured has moved on. Snapshot that alongside the source and say in `meta.yml` when it was taken.

`meta.yml` carries what the gallery cannot: the **publishing org**, which is unrecoverable afterwards and is exactly what breaks when accounts change.

## The rule

Never pass a path under `tmp/`, `$TMPDIR`, `/tmp`, or any gitignored directory to the Artifact tool. Build under `artifacts/<slug>/build/` if you like, but the source that produced it must be committed first — publishing is the last step, not the record.

For a repo whose artifacts are personal rather than about the code, the same layout goes in the private `dotfiles-personal` repo instead. This repo is public; personal working artifacts never land on a branch here.

## Worked example

`context-ledger/` is the one built while the convention was written. Its page is a 1.5 MB HTML file — far too large to commit, and fully regenerable — so what is stored is the pipeline that builds it plus the environment scan it consumed, which is not regenerable because it measured a setup that has since changed.
