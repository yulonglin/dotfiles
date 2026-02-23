# Fix Skill/Agent Duplications & Update Plugin Cache

## Context

Two layers of duplication:
1. **Symlink duplications** — Claude Code creates 77 symlinks in `~/.claude/skills/` → every plugin skill appears twice in the picker
2. **Content duplications** — skills and agents that do the same thing exist across plugins

Additionally, ai-safety-plugins cache dirs are real copies (not symlinked to source), so edits aren't live.

## Content Duplications Found

| Duplicate | Source | Keep | Remove | Reason |
|-----------|--------|------|--------|--------|
| **`claude-code` skill ↔ `claude` agent** | code-toolkit | agent | skill | Agent integrates with Task tool; skill is just a how-to guide for the same CLI commands |
| **`codex-cli` skill ↔ `codex` agent** | code-toolkit skill + core-toolkit agent | agent (core-toolkit) | skill (code-toolkit) | Agent always available via core-toolkit; skill duplicates the same delegation pattern |

Official plugin overlaps (we don't control, just configure):
- `coderabbit:code-review` skill vs `code-review:code-review` command — both provide `/code-review`, different backends
- `superpowers:code-reviewer` agent vs `code-toolkit:code-reviewer` agent vs `coderabbit:code-reviewer` agent — 3 code-reviewer agents, different focus areas

## Steps

### 1. Remove duplicate skills from ai-safety-plugins source
**Files to delete** (in `~/code/ai-safety-plugins/plugins/`):
- `code-toolkit/skills/claude-code/` — redundant with `code-toolkit/agents/claude.md`
- `code-toolkit/skills/codex-cli/` — redundant with `core-toolkit/agents/codex.md`

### 2. Remove skill symlinks from ~/.claude/skills/
Run `clean-skill-dupes` (existing script: `scripts/cleanup/clean_plugin_symlinks.sh`) to remove all 77 plugin-created symlinks. User-authored skill dirs are untouched.

### 3. Sync cache to source via symlinks
Run `claude-cache-link --apply` to replace the 7 real cache version dirs with symlinks to `~/code/ai-safety-plugins/plugins/`. This makes step 1's deletions immediately live AND ensures all future source edits are live.

### 4. Clean stale cache entries
Run `claude-cache-clean --apply` to remove `insights-toolkit` (absorbed into workflow-toolkit) and any other orphaned cache versions.

## Verification
- `ls ~/.claude/skills/` — only real directories (commit, commit-push-sync, anthropic-style, llm-billing, .system, .migrated)
- `ls -la ~/.claude/plugins/cache/ai-safety-plugins/*/` — version dirs are symlinks to source
- `ls ~/code/ai-safety-plugins/plugins/code-toolkit/skills/` — no `claude-code/` or `codex-cli/`
- Restart Claude Code → confirm no duplicate skill entries in picker
