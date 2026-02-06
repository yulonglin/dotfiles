# Documentation Lookup

## Priority Order

1. Check `docs/` for project-specific context
2. Check `~/.claude/docs/` for global specs (CI standards, reproducibility checklist)
3. **Context7 MCP** for popular library/framework documentation (fastest, most reliable)
4. **GitHub CLI** (`gh api`) for specific file access to verified repositories
5. **Explore locally** with Glob/Grep/Read for installed libraries/packages
6. **WebFetch** for specific URLs you know about
7. **WebSearch** as last resort for general information
8. **Search with `/docs-search`** for fast grep-based search across docs, specs, CLAUDE.md

## Using Context7 MCP (Recommended for Libraries)

```bash
# 1. Resolve library ID
resolve-library-id: "inspect_ai" -> libraryId="/UKGovernmentBEIS/inspect_ai"

# 2. Query documentation
query-docs: libraryId="/UKGovernmentBEIS/inspect_ai" query="How to run evaluations?"
```

## Using GitHub CLI for Specific Files

```bash
gh api repos/OWNER/REPO/readme --jq '.content' | base64 -d
gh api repos/OWNER/REPO/contents/path/to/file.py --jq '.content' | base64 -d
gh api repos/OWNER/REPO | jq '.description, .homepage'
```

## Verified Repositories

```
UKGovernmentBEIS/inspect_ai      # LLM evaluation framework
UKGovernmentBEIS/inspect_evals   # Community evaluations
facebookresearch/hydra           # Configuration framework
BerriAI/litellm                  # Multi-provider LLM client
safety-research/safety-tooling   # Safety research tools
ericbuess/claude-code-docs       # Claude Code documentation
```

**Security**: Always verify exact owner/repo path to prevent typosquatting.

## Decision Tree

| Need | Method | Why |
|------|--------|-----|
| Popular library docs | **Context7** | Fastest, curated |
| Specific file from known GitHub repo | **GitHub CLI** | Instant, reliable |
| Installed library exploring | **Glob/Grep/Read** | No network |
| Known specific URL | **WebFetch** | Exact content |
| General information | **WebSearch** | Last resort |
