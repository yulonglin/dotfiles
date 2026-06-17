# Prefer WebFetch Over WebSearch Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make Claude Code prefer WebFetch (domain-gated, auditable) over WebSearch (opaque, less controlled) for web access, with appropriate guardrails.

**Architecture:** Add a PreToolUse hook on WebSearch that provides soft guidance (not blocking) to prefer WebFetch when a specific URL is known. Update existing WebFetch hook's fallback message. Update documentation to reflect the preference.

**Tech Stack:** Bash hooks, Claude Code settings.json, Markdown docs

---

### Task 1: Update WebFetch Hook Block Message

**Files:**
- Modify: `claude/hooks/check_webfetch_domain.sh:77`

**Context:** Currently when WebFetch is blocked, the message says "use WebSearch instead." This is backwards — we want to prefer WebFetch. The fallback should be asking the user, not WebSearch.

**Step 1: Update the block message**

Change line 77 from:
```bash
echo "BLOCKED: WebFetch to '$DOMAIN' is not in the allowed domain list. Ask the user for permission before fetching from this domain, or use WebSearch instead." >&2
```

To:
```bash
echo "BLOCKED: WebFetch to '$DOMAIN' is not in the allowed domain list. Ask the user for permission to add this domain, or ask the user to provide the content directly." >&2
```

**Rationale:** Don't redirect to WebSearch as fallback. Ask the user — they can either approve the domain or paste content.

**Step 2: Verify hook still works**

Run: `CLAUDE_TOOL_INPUT='{"url":"https://example.com/page"}' bash claude/hooks/check_webfetch_domain.sh; echo "exit: $?"`
Expected: stderr shows updated message, exit code 2

Run: `CLAUDE_TOOL_INPUT='{"url":"https://github.com/foo"}' bash claude/hooks/check_webfetch_domain.sh; echo "exit: $?"`
Expected: no output, exit code 0

**Step 3: Commit**

```bash
git add claude/hooks/check_webfetch_domain.sh
git commit -m "fix: update WebFetch block message to not suggest WebSearch as fallback"
```

---

### Task 2: Create WebSearch Guidance Hook

**Files:**
- Create: `claude/hooks/prefer_webfetch.sh`

**Context:** This is a *soft* PreToolUse hook on WebSearch. It doesn't block (exit 0), but prints guidance to stderr encouraging Claude to prefer WebFetch when a specific URL is available. The goal is behavioral nudging, not hard blocking — WebSearch is still useful when you genuinely need to discover information.

**Step 1: Write the hook script**

```bash
#!/usr/bin/env bash
# PreToolUse:WebSearch hook — soft guidance to prefer WebFetch
# Always exits 0 (never blocks). Prints guidance to stderr.

cat >&2 <<'MSG'
PREFERENCE: WebFetch is preferred over WebSearch when you already know the target URL.
- If you have a specific URL → use WebFetch instead
- If you need to discover/find information and don't have a URL → WebSearch is fine
- For library docs → prefer Context7 MCP over both
MSG

exit 0
```

**Step 2: Make executable**

Run: `chmod +x claude/hooks/prefer_webfetch.sh`

**Step 3: Verify hook runs cleanly**

Run: `bash claude/hooks/prefer_webfetch.sh; echo "exit: $?"`
Expected: stderr shows guidance message, exit code 0

**Step 4: Commit**

```bash
git add claude/hooks/prefer_webfetch.sh
git commit -m "feat: add soft WebSearch guidance hook to prefer WebFetch"
```

---

### Task 3: Register WebSearch Hook in Settings

**Files:**
- Modify: `claude/settings.json` (hooks section)

**Context:** Add the new hook to the PreToolUse hooks array, alongside the existing WebFetch hook.

**Step 1: Find the hooks section**

Run: `grep -n 'PreToolUse\|WebFetch\|WebSearch' claude/settings.json`

Locate the `customApiKeyResponses` / `hooks` section where the WebFetch hook is registered.

**Step 2: Add WebSearch hook entry**

Add this entry to the `hooks` array in settings.json, after the existing WebFetch matcher block:

```json
{
  "matcher": "WebSearch",
  "hooks": [
    {
      "type": "command",
      "command": "$HOME/.claude/hooks/prefer_webfetch.sh",
      "timeout": 3
    }
  ]
}
```

**Step 3: Validate JSON**

Run: `jq '.' claude/settings.json > /dev/null && echo "valid JSON"`
Expected: "valid JSON"

**Step 4: Commit**

```bash
git add claude/settings.json
git commit -m "feat: register WebSearch guidance hook in settings"
```

---

### Task 4: Update Documentation

**Files:**
- Modify: `claude/docs/documentation-lookup.md`

**Context:** Update the priority order and decision tree to explicitly state the WebFetch preference and rationale.

**Step 1: Update priority order**

Replace lines 6-11 with:

```markdown
6. **WebFetch** for specific URLs (preferred for web access — domain-gated, auditable)
7. **WebSearch** only when you need to *discover* information and have no URL
8. **Search with `/docs-search`** for fast grep-based search across docs, specs, CLAUDE.md
```

**Step 2: Update decision tree**

Replace the last two rows of the decision tree table with:

```markdown
| Known specific URL | **WebFetch** | Preferred — domain-gated, auditable, predictable |
| Need to discover/find something | **WebSearch** | Only when no URL available |
```

**Step 3: Verify formatting**

Run: `cat claude/docs/documentation-lookup.md` and visually confirm the table renders correctly.

**Step 4: Commit**

```bash
git add claude/docs/documentation-lookup.md
git commit -m "docs: update lookup priority to prefer WebFetch over WebSearch"
```

---

### Task 5: Add Rule for Web Access Preference

**Files:**
- Modify: `claude/rules/refusal-alternatives.md` (Tool Failure Alternatives table)

**Context:** The refusal-alternatives rule already mentions WebFetch. Add a row that codifies the preference.

**Step 1: Add web access preference row**

Add this row to the "Tool Failure Alternatives" table:

```markdown
| WebSearch for a known URL | Use **WebFetch** instead — it's domain-gated, auditable, and preferred. WebSearch only for discovery when you have no URL |
```

**Step 2: Commit**

```bash
git add claude/rules/refusal-alternatives.md
git commit -m "docs: add WebFetch preference to refusal-alternatives rule"
```

---

## Summary of Changes

| File | Change | Purpose |
|------|--------|---------|
| `claude/hooks/check_webfetch_domain.sh` | Fix block message | Don't suggest WebSearch as fallback |
| `claude/hooks/prefer_webfetch.sh` | New soft guidance hook | Nudge Claude toward WebFetch |
| `claude/settings.json` | Register new hook | Activate guidance on WebSearch calls |
| `claude/docs/documentation-lookup.md` | Update priority + decision tree | Explicit preference documentation |
| `claude/rules/refusal-alternatives.md` | Add preference row | Codify in behavioral rules |

**Design decisions:**
- **Soft, not hard:** WebSearch isn't blocked — it's still the right tool for genuine discovery. The hook just reminds Claude to check if WebFetch would work first.
- **No new permissions needed:** Both tools remain pre-approved. The guidance is behavioral, not access control.
- **Consistent messaging:** All three touchpoints (hook, docs, rules) say the same thing: WebFetch preferred, WebSearch for discovery only.
