# Vault Deliverables

Anything Yulong will read away from this machine gets a copy in `~/vault`, which Obsidian Sync carries to his phone and Mac: reports, specs, plans, handoffs and status docs (`.md`); figures, rendered pages and screenshots (`.png`, `.jpg`); papers, decks, submissions and built reports (`.pdf`). Copy it there as part of delivering, not as a follow-up, and give the vault path in the closing summary. Code, data, logs, `.eval` files and build trees never go in.

Place it where the layout hook allows: research work under `research/<topic>/` in `specs/`, `plans/`, `docs/`, `runs/<YYYY-MM-DD-slug>/` or `assets/` (images); tool work under `tooling/<repo>/`. A batch of binaries gets a `README.md` beside it naming each file, what it is for, and the source path and commit it was copied from.

Sync carries only markdown, images and PDF, and per-file size is capped (keep under ~5 MB; split or downsample anything larger). Copy, never symlink — a symlink inside a synced vault can read as a deletion and propagate it. The vault copy is a snapshot: the source of truth stays in the repo, and a rebuild means a re-copy.
