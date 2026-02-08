# Plan: Custom "10x Mentor" Output Style

## Context

Currently using the built-in "Learning" output style (via plugin), which provides generic coding-focused coaching with `TODO(human)` patterns and `★ Insight` markers. The user wants a **targeted personal growth system** covering 4 tracks: Communication, Reliability, Research Engineering, and Deep Technical Understanding — embedded directly into every Claude Code session.

## Approach

Replace the plugin-based Learning style with a **native custom output style file** (`~/.claude/output-styles/10x-mentor.md`). This is cleaner than the plugin approach and integrates with the `/output-style` command for easy toggling.

## Changes

### 1. Create output style directory and file
**File:** `/Users/yulong/code/dotfiles/claude/output-styles/10x-mentor.md`

- YAML frontmatter: `name: 10x Mentor`, `keep-coding-instructions: true` (augment, don't replace default coding behavior)
- ~170 lines covering:
  - **Core principles**: Task first, max 1 coaching moment/response, model the behavior, be specific
  - **Track 1 [COMM]**: Communication & writing — triggers on commit messages, PR descriptions, research framing, explanations. Develops: clarity, persuasion, warmth, confidence-inspiring writing
  - **Track 2 [RELY]**: Reliability — triggers on verification, edge cases, documentation, loose ends. Develops: thoroughness, follow-through, accountability
  - **Track 3 [RESEARCH]**: 10x Research Engineer / Agent Architect — triggers on experiment design, agent orchestration, code review, system architecture, result interpretation. Develops: directing agents, choosing metrics, identifying useful experiments, framing narratives
  - **Track 4 [DEEP]**: Deep Technical Understanding — triggers on ML/AI internals, debugging methodology, root cause analysis, math intuition. Develops: understanding transformers, training dynamics, LLM internals deeply
  - **Coaching format**: `> [TRACK] observation + Try: actionable suggestion` (placed after relevant work, 2-3 lines max)
  - **When NOT to coach**: Routine operations, user is in a hurry, same track coached recently, obvious observations
  - **Growth challenges**: Replaces `TODO(human)` — max once per session, only for genuine decision points tied to a track

### 2. Update settings.json
**File:** `/Users/yulong/code/dotfiles/claude/settings.json`

- Change `"outputStyle": "Learning"` → `"outputStyle": "10x Mentor"`
- Disable learning plugin: `"learning-output-style@claude-plugins-official": false`

### 3. Update CLAUDE.md architecture docs
**File:** `/Users/yulong/code/dotfiles/CLAUDE.md`

- Add `output-styles/` to the Configuration Structure section
- Brief note about the 10x Mentor style

## Key Design Decisions

| Aspect | Learning (current) | 10x Mentor (new) |
|--------|--------------------|--------------------|
| Mechanism | Plugin SessionStart hook | Native `.md` output style file |
| Coaching scope | Generic coding decisions | 4 targeted growth tracks |
| Coaching frequency | Every few responses | Max 1/response, usually 0 (light touch) |
| Format | `★ Insight` + `TODO(human)` | `> [TRACK]` one-liner + `Try:` |
| Code contributions | 5-10 lines often | Growth challenges, max 1/session |
| Claude's own behavior | Not specified | Must model the coached skills |

## Verification

1. Start a new Claude Code session
2. Run `/output-style` — confirm "10x Mentor" appears and is selected
3. Do a small coding task — verify coaching moments appear naturally (not every response)
4. Write a commit message — verify [COMM] coaching triggers
5. Design a small experiment — verify [RESEARCH] coaching triggers
6. Confirm no conflicts with existing CLAUDE.md rules
