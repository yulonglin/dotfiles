# Fail-Fast Pilots

Before any experiment scales (many episodes, many API calls, GPU fan-out), run a **pilot of 1-2 samples end-to-end through every stage** — parse → audit → render → compute → measure → report — and eyeball the outputs before spending at scale. The pilot is a hard gate, not a formality: scale-up is blocked until it passes.

What this buys, concretely (P0 targeted-replays, 2026-08-13, one session): the 2-rollout pilot caught a collapsed data export (only 1 usable negative in the delivery), silently-widespread thinking-cap truncation (44 capped attempts where the source claimed 6 samples), and a monitor-prompt frame that contradicted a channel's evidence (v5 said "code is redacted" above a block of code) — each of which would have shipped as a plausible-looking wrong number at scale.

## The pattern

- **Formatting audit first.** Parse the real input and audit for chrome, redaction markers, truncation, placeholder tokens, byte-fidelity — with counts, before any downstream stage consumes it. A second independent rendering of the same data (HTML vs markdown, raw vs export) turns "assumed faithful" into a checked diff.
- **Freeze measurement rules before measuring.** Rendering rules, prompt texts (sha256s), position sampling, gate thresholds — recorded in a manifest before the first scored call, enforced by the runner (refuse to spend when the frozen file is absent), not by discipline.
- **Gates ship with a negative control.** A threshold justified by "aligned data passes it" is an assertion; deliberately corrupt one sample (off-by-one shift, wrong template) and show the separation margin. Thresholds stay PROVISIONAL until the pilot numbers exist.
- **Cheap dry-run mode everywhere.** Every spending stage gets a --dry-run that renders exactly what would be sent (with token counts) for zero cost; read it before the live run.
- **Cross-family review before committing pilot code.** The P0 review caught six fail-open gates — including a k=50 surface that silently rendered 49 snapshots — that self-review missed.
- **Append-only + resumable by content identity.** Resume keys include prompt/config hashes so a revised prompt invalidates stale rows instead of silently reusing them.

## Scale-up cost levers (measured, same session)

Per-turn cumulative-prefix monitoring is quadratic (~T²/2); the episode-level endpoint is definitionally the final-turn verdict, so **final-turn-only** cut a 40-episode monitor run from ~$150-250 to $19 with zero loss on the headline. Prefer it, with per-turn latency curves on a subsample later.
