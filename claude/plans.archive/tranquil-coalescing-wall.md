# Plan: Organize Agents & Skills into Thematic Plugins

## Goal
Restructure the flat `claude/agents/` and `claude/skills/` into thematic local plugins with namespacing and per-project enablement.

## Plugin Groupings

### 1. `research-toolkit` (AI safety research workflows)
**Agents:** experiment-designer, research-engineer, research-skeptic, research-advisor, data-analyst, literature-scout
**Skills:** spec-interview-research, generate-research-spec, experiment-setup, run-experiment, reproducibility-report, api-experiments, mats-slurm

### 2. `writing-toolkit` (papers, drafts, presentations)
**Agents:** paper-writer, application-writer, writing-clarity (clarity-critic), writing-narrative (narrative-critic), writing-facts (fact-checker), writing-redteam (red-team)
**Skills:** review-draft, review-paper, read-paper, research-presentation, slidev, fix-slide, clear-writing

### 3. `code-quality` (code review, debugging, performance)
**Agents:** code-reviewer, debugger, performance-optimizer, tooling-engineer
**Skills:** deslop, bulk-edit, fix-merge-conflict

### 4. Keep in global `~/.claude/` (cross-cutting, always needed)
**Agents:** efficient-explorer, context-summariser, gemini
**Skills:** commit, custom-compact, externalise-handover, fast-cli, spec-interview, strategic-communication, task-management

## Plugin Structure (each plugin)

```
claude/plugins/<name>/
├── .claude-plugin/
│   └── plugin.json
├── agents/
│   └── *.md
└── skills/
    └── <skill-name>/
        └── SKILL.md (+ references/, templates/ as needed)
```

## Symlink Strategy for Shared Items

Some agents/skills fit multiple themes. Use **symlinks** within the dotfiles repo:
- `literature-scout` → both research-toolkit and writing-toolkit
- `read-paper` → both research-toolkit and writing-toolkit

Symlink from the secondary plugin back to the primary location.

## Implementation Steps

1. **Disable unnecessary plugins** in `settings.json`:
   - `swift-lsp` → false
   - `frontend-design` → false
   - `explanatory-output-style` → false (keep `learning-output-style` only)
   - `huggingface-skills` → false

2. **Create plugin directories** with `plugin.json` manifests for: `research-toolkit`, `writing-toolkit`, `code-quality`

3. **Move agents** from `claude/agents/` into respective plugin `agents/` dirs

4. **Move skills** from `claude/skills/` into respective plugin `skills/` dirs (preserving subdirectory structure)

5. **Create symlinks** for shared agents/skills

6. **Keep global items** in `claude/agents/` and `claude/skills/` (the always-needed ones)

7. **Update `settings.json`** to enable local plugins:
   ```json
   "enabledPlugins": {
     "research-toolkit@local": true,
     "writing-toolkit@local": true,
     "code-quality@local": true
   }
   ```

8. **Update `deploy.sh`** if needed (the claude/ symlink should handle it, but verify plugin discovery)

9. **Update CLAUDE.md** project docs to reflect new structure

## Verification

- Run `claude` and check `/` menu shows namespaced skills (e.g., `/research-toolkit:experiment-setup`)
- Run `/agents` and verify agents appear with plugin prefix
- Test in a research repo: enable only `research-toolkit` + `code-quality`
- Test in a paper repo: enable only `writing-toolkit` + `code-quality`

## Files Modified
- `claude/settings.json` — disable plugins, add local plugins
- `claude/plugins/research-toolkit/` — new plugin dir
- `claude/plugins/writing-toolkit/` — new plugin dir
- `claude/plugins/code-quality/` — new plugin dir
- `claude/agents/` — remove moved agents (keep global ones)
- `claude/skills/` — remove moved skills (keep global ones)
- `CLAUDE.md` — update Architecture section
