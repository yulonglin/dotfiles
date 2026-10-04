# Vault Deliverables

**Every deliverable has one reader-facing home**; a second copy drifts and nobody can tell which is current. If it already lives where Yulong reads on his phone — a Bear note, an Artifact, a Google Doc, a PR — that is its only home: no copy in `~/vault`. If it would otherwise exist only on this machine or a server (a report, figure, rendered page or PDF), put it in `~/vault`, which Obsidian Sync carries to his phone and Mac, as part of delivering. Code, data, logs, `.eval` files and build trees never go in. Give the one path or link in the closing summary.

Place it where the layout hook allows: research under `research/<topic>/` in `specs/`, `plans/`, `docs/`, `runs/<YYYY-MM-DD-slug>/` or `assets/`; tool work under `tooling/<repo>/`. A batch of binaries gets a `README.md` naming each file and its source path and commit.

Sync carries only markdown, images and PDF, under ~5 MB per file. Copy, never symlink — a symlink inside a synced vault can read as a deletion and propagate it.
