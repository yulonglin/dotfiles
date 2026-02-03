# Update Documentation Lookup Workflow: Remove GitHub MCP, Use Context7 + GitHub CLI

## Objective

Update all documentation, skills, and agents to reflect the new workflow that uses **Context7 MCP** for library documentation and **GitHub CLI** for specific file access, removing deprecated **GitHub MCP** references.

## Background

Based on community research (Simon Willison, HackerNews, official best practices), the optimal documentation lookup strategy is:
1. Local docs first (fastest, most accurate)
2. Context7 MCP for popular library/framework documentation
3. GitHub CLI (`gh api`) for specific files when path is known
4. Local library exploration (Glob/Grep/Read on site-packages/node_modules)
5. WebFetch for specific URLs
6. WebSearch as last resort

GitHub MCP is being removed because:
- Context7 covers most library documentation needs
- GitHub CLI (`gh api`) is simpler and faster for specific file fetches
- Built-in Glob/Grep/Read tools are better for understanding installed libraries
- Reduces MCP server overhead (50+ tools from GitHub MCP)

## Files to Update

### 1. Global CLAUDE.md (`claude/CLAUDE.md`, lines 415-434)

**Current state:**
- Recommends "MCP servers (context7, GitHub, gitmcp)"
- Has "Verified Repositories (use GitHub MCP, gitmcp)" section

**Changes:**
- Remove GitHub MCP and gitmcp from priority order
- Expand workflow section with Context7 examples and GitHub CLI commands
- Update "Verified Repositories" section to explain access without GitHub MCP
- Add decision guidance (when to use Context7 vs gh CLI vs local exploration)

**New priority order:**
1. Local docs (`docs/`, `~/.claude/docs/`)
2. Context7 MCP (popular libraries)
3. GitHub CLI (`gh api repos/OWNER/REPO/contents/PATH`)
4. Explore installed libraries (Glob/Grep/Read)
5. WebFetch (specific URLs)
6. WebSearch (last resort)

**Add practical examples:**
```bash
# Context7 workflow
resolve-library-id: "inspect_ai" → query-docs: libraryId="/UKGovernmentBEIS/inspect_ai"

# GitHub CLI examples
gh api repos/OWNER/REPO/readme
gh api repos/OWNER/REPO/contents/path/to/file.py
```

### 2. Codex AGENTS.md (`codex/AGENTS.md`, line 8)

**Current state:**
```markdown
prefer MCP servers (`context7`, `GitHub`, `gitmcp`)
```

**Change to:**
```markdown
(1) try Context7 MCP for popular libraries, (2) use GitHub CLI (`gh api`) for specific files, (3) explore locally installed libraries with Glob/Grep/Read, (4) use WebSearch as last resort
```

### 3. Fact-Checker Agent (`claude/local-marketplace/plugins/writing-toolkit/agents/writing-facts.md`)

**Current state:**
- Tools: `Read,WebSearch,WebFetch`
- Uses WebSearch for all verification

**Changes:**
- **Line 5 (frontmatter):** Add Context7 tools
  ```yaml
  tools: Read,WebSearch,WebFetch,mcp__context7__resolve-library-id,mcp__context7__query-docs
  ```

- **Lines 40-50 (Verify claims section):** Add Context7 workflow
  ```markdown
  3. **Verify claims**:
     - Check cited sources via WebFetch
     - For technical documentation/API claims, try Context7 first
     - Search for supporting evidence via WebSearch (for general claims, blog posts, news)
     - Note what's verifiable vs. not
  ```

- **Line 99 (constraints):** Add guidance
  ```markdown
  - **Try Context7 for technical claims** - faster and more reliable than WebSearch for library/framework documentation
  ```

- **Line 110 (error handling):** Add Context7 fallback
  ```markdown
  **Context7 not available**: Fall back to WebSearch or gh CLI for GitHub repositories
  **WebSearch rate limited**: Flag as "verification incomplete due to rate limiting"
  ```

### 4. Red-Team Agent (`claude/local-marketplace/plugins/writing-toolkit/agents/writing-redteam.md`)

**Current state:**
- Tools: `Read,WebSearch`

**Changes:**
- **Line 5 (frontmatter):** Add Context7 tools
  ```yaml
  tools: Read,WebSearch,mcp__context7__resolve-library-id,mcp__context7__query-docs
  ```

- **After line 30 (WHAT TO CHECK section):** Add technical accuracy check
  ```markdown
  7. **Technical accuracy** - For claims about libraries/frameworks, verify against documentation (use Context7 for quick checks)
  ```

### 5. Writing Assistants Spec (`claude/specs/writing-assistants.md`)

**Current state:**
- Documents fact-checker uses WebSearch/WebFetch
- Tool lists show only WebSearch/WebFetch

**Changes:**
- **Line 83:** Update to include Context7
  ```markdown
  - **Sources**: Fact-checker uses Context7 (technical docs), WebSearch/WebFetch (general claims), red-team uses Context7 for technical verification; others use Read only
  ```

- **Lines 114-115 (agent table):** Update tool lists
  ```markdown
  | fact-checker | `writing-facts.md` | Read, WebSearch, WebFetch, Context7 | Claim verification |
  | red-team | `writing-redteam.md` | Read, WebSearch, Context7 | Argument stress-testing |
  ```

- **Line 176 (error handling):** Add Context7 fallback
  ```markdown
  | Context7 unavailable | Fact-checker/red-team fall back to WebSearch or gh CLI |
  | WebSearch rate limited | Fact-checker flags as "unable to verify" |
  ```

## Implementation Sequence

1. **CLAUDE.md** - Sets authoritative pattern
2. **AGENTS.md** - Ensures Codex CLI follows same pattern
3. **writing-assistants.md** (spec) - Documents what agents should do
4. **writing-facts.md** + **writing-redteam.md** - Implement spec
5. **Verification** - Run consistency checks

## Critical Files

- `/Users/yulong/code/dotfiles/claude/CLAUDE.md` - Primary documentation
- `/Users/yulong/code/dotfiles/codex/AGENTS.md` - Codex global instructions
- `/Users/yulong/code/dotfiles/claude/specs/writing-assistants.md` - Specification
- `/Users/yulong/code/dotfiles/claude/local-marketplace/plugins/writing-toolkit/agents/writing-facts.md` - Fact-checker agent
- `/Users/yulong/code/dotfiles/claude/local-marketplace/plugins/writing-toolkit/agents/writing-redteam.md` - Red-team agent

## Verification Steps

After implementation:

1. **Consistency check - ensure no GitHub MCP references remain:**
   ```bash
   rg "GitHub MCP|github.*mcp|gitmcp" claude/ codex/
   # Should return 0 results
   ```

2. **Verify Context7 mentioned in all updated files:**
   ```bash
   rg "context7|Context7" claude/CLAUDE.md codex/AGENTS.md claude/specs/writing-assistants.md
   # Should show references in all 3 files
   ```

3. **Check agent frontmatter syntax is valid:**
   ```bash
   # Verify YAML parses correctly
   head -10 claude/local-marketplace/plugins/writing-toolkit/agents/writing-facts.md
   head -10 claude/local-marketplace/plugins/writing-toolkit/agents/writing-redteam.md
   ```

4. **Manual review checklist:**
   - [ ] Priority order is Context7 → gh CLI → local exploration → WebFetch → WebSearch
   - [ ] Practical examples are clear (Context7 workflow, gh api commands)
   - [ ] Security warnings preserved (typosquatting)
   - [ ] Error handling covers Context7 unavailable scenario
   - [ ] No contradictions between files

5. **Functional test:**
   - Invoke `/clarity-critic` or `/review-draft` on a draft with technical claims
   - Verify agent uses Context7 for library documentation
   - Verify agent falls back to WebSearch for general claims

## Edge Cases Covered

- **Context7 library not available** → Fall back to gh CLI → local exploration → WebSearch
- **GitHub CLI not authenticated** → Low impact, Context7 handles most cases
- **Context7 rate limited** → Fall back to other methods (documented in error handling)
- **Backward compatibility** → No other files reference GitHub MCP (verified via exploration)

## Summary

**Total changes:** ~35 lines across 5 files, primarily additive (no functionality removed)

**Impact:**
- More reliable documentation lookup (Context7 is faster than WebSearch)
- Simpler workflow (fewer MCP tools, clearer decision tree)
- Better error handling (explicit fallback strategies)
- Consistent guidance across all docs, specs, and agents
