# Plan: Remove Orphaned Plugin Entries

## Context

Two plugins fail to load on every session start:
- `document-skills@anthropic-agent-skills` — orphaned from marketplace, cached but unusable
- `example-plugin@claude-plugins-official` — never installed to cache, purely educational

Both are disabled (`false`) in `enabledPlugins` but their presence causes load errors. Removing the entries stops the errors with no functionality loss.

## Changes

**File:** `claude/settings.json`

Remove these two lines from the `enabledPlugins` object:
- `"document-skills@anthropic-agent-skills": false,`
- `"example-plugin@claude-plugins-official": false,`

## PDF capability gap

`/fix-slide` is **Slidev-specific** (fixes overflow/blank pages in Markdown presentations, exports to PNG). It does NOT provide general PDF manipulation.

The `document-skills` plugin was the only source for general PDF ops (merge, split, extract text/tables, OCR, watermarks). Since it's orphaned from its marketplace, re-enabling won't work. If needed later:
- Install a fresh PDF plugin, or
- Use Python libraries directly (`pypdf`, `pdfplumber`, `pymupdf`)

## Verification

1. Restart Claude Code
2. Run `/plugins` — neither plugin should appear or show errors
