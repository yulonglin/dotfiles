# Plan: Integrate Agent Teams into Dotfiles

## Summary

Enable Claude Code's experimental agent teams feature and add guidance for smart escalation from subagents to teams when tasks are parallelizable with inter-agent communication needs.

**Three deliverables:**
1. Enable agent teams in `settings.json`
2. Add agent team strategy to global `CLAUDE.md`
3. Create new `/agent-teams` skill (standalone, user-owned — not modifying Superpowers plugin)

---

## 1. Enable Agent Teams in `settings.json`

**File:** `claude/settings.json`

**After line 191** (after `sandbox` block closing brace), insert:

```json
"env": {
  "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
},
"teammateMode": "auto",
```

`"auto"` = split panes inside tmux, in-process otherwise.

---

## 2. Update Global CLAUDE.md

**File:** `claude/CLAUDE.md`

### 2a. Update Default Behaviors (line 97)

Change:
```
- **Delegate to subagents** for non-trivial work (you coordinate, they execute)
```
To:
```
- **Delegate to agents** for non-trivial work — use agent teams for parallelizable multi-faceted tasks, subagents for focused single-output tasks
```

### 2b. Add cross-reference in Subagent Strategy (after line 401)

After the "Principles" line, add:
```
> For parallelizable multi-perspective work, consider **Agent Teams** (see below). Teams add inter-agent communication; subagents are better for focused tasks where only the result matters.
```

### 2c. Add "Agent Team Strategy" section (after line 445, before "Documentation Lookup")

New section covering:
- **When to escalate** — decision tree: single session → subagents → agent teams
- **Key differences table** — subagents vs teams (context, communication, coordination, cost)
- **Team composition patterns** — research, implementation, debugging, review teams
- **Communication & coordination** — message vs broadcast, delegate mode, plan approval
- **Best practices** — context in spawn prompts, task sizing, file ownership, monitoring
- **Anti-patterns** — too many teammates for simple work, same-file edits, unattended teams
- **Experimental note** — flag known limitations (no session resumption, one team per session, no nested teams)

Tone: Smart escalation, not "always use teams." Bias towards teams when work is genuinely parallelizable with light communication needs.

---

## 3. Create `/agent-teams` Skill

**Directory:** `claude/skills/agent-teams/`

### Files to create:

#### `SKILL.md` — Main skill definition
Structure:
- **When to Use** — decision tree matching CLAUDE.md but more detailed
- **The Process** — 5 steps: Assess → Design Team → Spawn with Context → Coordinate → Integrate & Clean Up
- **Team Patterns** — 4 patterns with references to prompt templates:
  - Research Team (3-5 teammates, devil's advocate role)
  - Implementation Team (2-4 teammates, file ownership)
  - Debugging Team (3-5 teammates, adversarial hypothesis testing)
  - Review Team (2-3 teammates, multi-lens review)
- **Key Constraints** — one team per session, no nested teams, file ownership, cleanup via lead
- **Integration** — works with brainstorming, writing-plans, finishing-a-development-branch

#### `research-team-prompt.md` — Template for research-oriented teams
#### `implementation-team-prompt.md` — Template for parallel implementation
#### `debugging-team-prompt.md` — Template for competing hypotheses
#### `review-team-prompt.md` — Template for multi-lens code review

Each template provides a copy-paste spawn prompt with:
- Role definitions and focus areas
- Deliverable format per teammate
- Communication expectations
- Lead coordination strategy

---

## Files Modified

| File | Action | Lines affected |
|------|--------|---------------|
| `claude/settings.json` | Edit | After line 191 (add `env` + `teammateMode`) |
| `claude/CLAUDE.md` | Edit | Line 97, after line 401, after line 445 |
| `claude/skills/agent-teams/SKILL.md` | Create | New file |
| `claude/skills/agent-teams/research-team-prompt.md` | Create | New file |
| `claude/skills/agent-teams/implementation-team-prompt.md` | Create | New file |
| `claude/skills/agent-teams/debugging-team-prompt.md` | Create | New file |
| `claude/skills/agent-teams/review-team-prompt.md` | Create | New file |

## Verification

1. **settings.json validity**: `python3 -c "import json; json.load(open('claude/settings.json'))"` — confirm valid JSON
2. **Skill discovery**: Start new Claude session, check that `/agent-teams` appears in available skills
3. **Agent teams enabled**: In a Claude session, ask to create an agent team — should work without "agent teams not enabled" error
4. **teammateMode**: Inside tmux, verify split panes appear; outside tmux, verify in-process mode
5. **CLAUDE.md coherence**: Read the updated sections to confirm the decision tree flows logically from subagents → teams
