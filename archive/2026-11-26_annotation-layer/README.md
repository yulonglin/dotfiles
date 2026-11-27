# Annotation layer (retired 2026-11-26)

The custom select-to-comment layer that `md2artifact` and `annotate-html` injected into Artifact pages: comments and suggested edits in `localStorage`, a Copy-all Markdown export, an unload guard, checklist state (`--states`) and Download/Copy HTML buttons.

Retired because the Artifact platform now has built-in comments, read and answered with the `ArtifactComments` tool (Yulong, 26 Nov 2026). The PreToolUse hook that blocked publishing a page without the layer (`claude/hooks/block_unannotated_artifact.sh`) was deleted with it; git history keeps it.

Files:

- `_annotation_layer.py` — the shared CSS + HTML + JS block, formerly `custom_bins/_annotation_layer.py`
- `annotate-html` — CLI that injected the layer into a hand-built page, formerly `custom_bins/annotate-html`
- `test_annotate_html.py` — its tests, formerly `tests/test_annotate_html.py`

Pages published before 2026-11-26 still carry a frozen copy of the layer. Rebuilding with the current `md2artifact` drops it.
