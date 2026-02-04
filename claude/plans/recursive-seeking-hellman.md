# Skill Organization & Agent Conversion Analysis

**Date:** 2026-02-03
**Context:** Analyzing Claude Code skills for duplicates and identifying skills that should become agents

## Findings

### 1. Skill Duplication Pattern

**Root Cause:** Skills are displayed with TWO naming conventions:
- Plugin namespace delimiter: `__` (e.g., `writing-toolkit__research-presentation`)
- Command delimiter: `:` (e.g., `writing-toolkit:research-presentation`)

**Evidence:**
Looking at the system reminder skill list, EVERY skill appears twice:
- `code-toolkit__codex-cli` AND `code-toolkit:codex-cli`
- `writing-toolkit__research-presentation` AND `writing-toolkit:research-presentation`
- `superpowers__brainstorming` AND `superpowers:brainstorming`

**Actual state on disk:**
```bash
# Only ONE copy exists per skill
/Users/yulong/.claude/plugins/cache/local-marketplace/writing-toolkit/1.0.0/skills/research-presentation/SKILL.md
/Users/yulong/.claude/plugins/cache/local-marketplace/code-toolkit/1.0.0/skills/codex-cli/SKILL.md
```

**Conclusion:** This is NOT duplication - it's a **display artifact**. The skills list shows both invocation patterns for the same underlying skill file. This is likely intentional for UX (users can call skills either way).

**Recommendation:** ✅ **No action needed** - this is working as designed. Both `writing-toolkit:research-presentation` and `/research-presentation` invoke the same skill.

---

### 2. Delegation Skills → Agent Conversion

#### codex-cli: Should Become an Agent ✅

**Current state:** Skill at `code-toolkit/skills/codex-cli/SKILL.md`

**Why it should be an agent:**
1. **Pure delegation pattern** - It literally just calls `codex exec` CLI tool
2. **Zero workflow** - No checklist, no steps for Claude to execute, just "run this bash command"
3. **No Claude-specific logic** - Everything in the skill is about how to invoke an external tool
4. **Already has agent characteristics:**
   - Takes a task description as input
   - Returns results asynchronously
   - Has clear execution modes (sync/async)
   - Has well-defined delegation boundaries

**Comparison with existing agents:**
- `gemini-cli` agent: Delegates large-context tasks to Gemini CLI ✓ Similar pattern
- `codex-cli` skill: Delegates implementation tasks to Codex CLI ✓ Same pattern!

**Migration path:**
```
Current: /code-toolkit skill (invoked with Skill tool)
Target:  code-toolkit:codex agent (invoked with Task tool, subagent_type="code-toolkit:codex")
```

**Benefits:**
- More intuitive ("Task tool for delegating tasks")
- Consistent with gemini-cli agent pattern
- Cleaner skill list (skills = workflows YOU execute, agents = delegation)
- Better async handling (agents already support background execution)

---

#### claude-code: Should Become an Agent ✅

**Current state:** Skill at `code-toolkit/skills/claude-code/SKILL.md`

**Why it should be an agent:**
1. **Pure delegation** - Just wraps `claude -p` CLI calls
2. **Zero workflow** - No checklist for Claude to follow
3. **Complementary to codex-cli** - Both are CLI delegation patterns
4. **Already agent-like:**
   - Async execution support
   - Structured prompting
   - Model selection flags

**Migration path:**
```
Current: /claude-code skill
Target:  code-toolkit:claude agent
```

---

### 3. Other Skills to Review

#### Potential Agent Candidates

**gemini-cli:** Already an agent ✅ (correctly categorized)

**llm-billing:** Currently an agent ✅ (correctly categorized - delegates to provider APIs)

**Skills that are CORRECTLY skills** (workflow-based, not delegation):
- `/brainstorming` - Has checklist, phases, requires Claude's judgment ✓
- `/systematic-debugging` - Has methodology, steps ✓
- `/test-driven-development` - Has workflow (red-green-refactor) ✓
- `/research-presentation` - Has critique framework, steps ✓
- All `plugin-dev:*` skills - Scaffolding workflows ✓

---

## Recommendations

### Priority 1: Convert Delegation Skills to Agents

| Current Skill | New Agent Type | Rationale |
|---------------|----------------|-----------|
| `code-toolkit:codex-cli` | `code-toolkit:codex` | Pure CLI delegation, no workflow |
| `code-toolkit:claude-code` | `code-toolkit:claude` | Pure CLI delegation, matches gemini-cli pattern |

**Implementation:**
1. Create agent definitions in `code-toolkit/agents/`
2. Update CLAUDE.md to reference agents instead of skills
3. Deprecate skills with migration guide
4. Update Task tool subagent_type enum

### Priority 2: Skill Cleanup (Optional)

**No duplicates found** - The `__` vs `:` pattern is intentional dual invocation support.

**Potential consolidation** (lower priority):
- `frontend-design` exists as both a plugin AND a skill - verify which should be canonical
- Multiple document-skills plugins cached (example-skills vs document-skills) - verify which is active

### Priority 3: Documentation Updates

**Update CLAUDE.md** with clearer delegation hierarchy:
```
Task Delegation:
├─ Agents (use Task tool)
│  ├─ gemini-cli: Large context analysis
│  ├─ codex: Well-scoped implementation
│  └─ claude: Judgment-heavy tasks
└─ Skills (use Skill tool)
   ├─ Workflows (brainstorming, debugging, TDD)
   └─ Templates (plugin-dev, research tools)
```

---

## Migration Plan

**Output Location:** `~/code/dotfiles/handover/` - Create handover documentation for implementation

### Phase 1: Document Analysis & Recommendations
- [x] Analyze skill duplication (RESOLVED: display artifact, not real duplication)
- [x] Identify delegation skills → agent candidates (codex-cli, claude-code)
- [ ] Create handover documentation in `~/code/dotfiles/handover/`
  - [ ] Migration guide with full rationale
  - [ ] Agent definition specs
  - [ ] Example invocations

### Phase 2: Create Agent Definitions (Future Implementation)
- [ ] Create `code-toolkit/agents/codex/AGENT.md`
- [ ] Create `code-toolkit/agents/claude/AGENT.md`
- [ ] Test invocation via Task tool

### Phase 3: Update Documentation
- [ ] Update global CLAUDE.md with agent references
- [ ] Remove skill invocations from workflows
- [ ] Add migration notes

### Phase 4: Deprecate Skills
- [ ] Mark skills as deprecated in frontmatter
- [ ] Add warning message pointing to agents
- [ ] Optional: Remove after deprecation period

---

## Questions for User

None - recommendations are clear-cut based on delegation pattern analysis.

---

## Files to Modify

**Working Directory:** `~/code/dotfiles/handover/`

### To Create (handover documentation):
- `~/code/dotfiles/handover/skill-to-agent-conversion.md` - Full migration guide
- `~/code/dotfiles/handover/agent-definitions/codex.md` - Agent spec for codex
- `~/code/dotfiles/handover/agent-definitions/claude.md` - Agent spec for claude-code

### Actual Implementation (later):
- `~/.claude/plugins/cache/local-marketplace/code-toolkit/1.0.0/agents/codex/AGENT.md`
- `~/.claude/plugins/cache/local-marketplace/code-toolkit/1.0.0/agents/claude/AGENT.md`

### To Update:
- `~/.claude/CLAUDE.md` (delegation hierarchy)
- `code-toolkit/skills/codex-cli/SKILL.md` (deprecation notice)
- `code-toolkit/skills/claude-code/SKILL.md` (deprecation notice)

### To Verify:
- Task tool's subagent_type enum includes new agent types
- All existing workflows using these skills

---

## Expected Outcome

**After migration:**
```
# OLD (skill pattern)
/codex-cli "implement function X"

# NEW (agent pattern - more intuitive)
Task tool → subagent_type: "code-toolkit:codex", prompt: "implement function X"
```

Users understand: "Skills for workflows I follow, Agents for tasks I delegate."
