# Plan: Update /tmp → ./tmp References

**Goal**: Update all project-level temporary file references from `/tmp/...` to `./tmp/...` in documentation and skills per `specs/tmp.md`.

## Context

The spec requests using `./tmp/...` instead of `/tmp/...` for temporary files to make it explicit that project-local temp directories should be used rather than system-wide temp.

After comprehensive search, found that most `/tmp` references are **system-level** (Claude Code's TMPDIR, installation scripts, SLURM templates) and should remain unchanged. Only **user-facing documentation** in skill files needs updating.

## Files to Update

### Skills (User-Facing Documentation) - 3 files

All updates are in example commands and documentation, not in code:

1. **`claude/local-marketplace/plugins/writing-toolkit/skills/fix-slide/SKILL.md`**
   - Line 24: `tmp/slide-check.pdf` → `./tmp/slide-check.pdf`
   - Line 36: `tmp/slides-images` → `./tmp/slides-images`
   - Line 62: `tmp/slides-fixed/` → `./tmp/slides-fixed/`

2. **`claude/local-marketplace/plugins/code-toolkit/skills/claude-code/SKILL.md`**
   - Line 42: `/tmp/claude-review.txt` → `./tmp/claude-review.txt`
   - Line 54: `/tmp/${TASK_NAME}.log` → `./tmp/${TASK_NAME}.log`

3. **`claude/local-marketplace/plugins/code-toolkit/skills/codex-cli/SKILL.md`**
   - Line 52: `OUTPUT="/tmp/codex-$(date -u +%s).txt"` → `OUTPUT="./tmp/codex-$(date -u +%s).txt"`
   - Line 75 (2 instances): `/tmp/${TASK_NAME}.txt` and `/tmp/${TASK_NAME}.log` → `./tmp/...`
   - Line 145: `/tmp/review.txt` → `./tmp/review.txt`
   - Line 152: `/tmp/review.txt` → `./tmp/review.txt`

## Files NOT to Update (System-Level Operations)

**Keep as `/tmp`** (system-level temp, not project-level):
- `claude/CLAUDE.md` (symlinked from ~/.claude/CLAUDE.md) - references to `/tmp/claude` for Claude Code's system TMPDIR
- `config/zshrc.sh` - `CLAUDE_CODE_TMPDIR` system configuration
- `scripts/cleanup/cleanup_claude_tmpdir.sh` - system-level cleanup
- `scripts/shared/helpers.sh` - download temp for gh CLI installation
- `install.sh` - download temp for gitleaks installation
- SLURM templates in `research-toolkit/skills/mats-slurm/` - cluster scripts need system-wide temp
- `.gitignore` files - correctly ignore both `/tmp` (root-level) and `tmp/` (any level)
- `config/aliases.sh` - `codex` function already uses `${PWD}/tmp/codex` when writable
- `custom_bins/transfer` - example shows downloading FROM remote `/tmp`, not creating local temp

## Implementation Steps

For each skill file:

1. Use Edit tool to replace `/tmp/` → `./tmp/` in the specific lines
2. Ensure context makes it clear these are project-local temp files

All changes are straightforward string replacements in documentation/examples.

## Verification

After updates:

1. **Grep verification**:
   ```bash
   # Should only show system-level references
   grep -r "/tmp/" claude/local-marketplace/plugins/*/skills/*/SKILL.md || echo "No project-level /tmp refs remaining"
   ```

2. **Manual spot-check**: Read updated skill files to ensure examples are correct

3. **Commit check**: Review `git diff` to ensure only intended lines changed

## Rationale

- **Project-local temp** (`./tmp/`) makes it explicit that files go in the project's scratch space
- **System temp** (`/tmp/`) is appropriate for system-level operations (Claude Code's TMPDIR, package downloads, SLURM job submission)
- **Documentation impact**: Users reading skills will see the correct pattern to follow
- **No code changes**: These are all documentation updates, no runtime behavior changes
