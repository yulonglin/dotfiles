---
name: docs-search
description: Fast grep-based search across docs, specs, CLAUDE.md using fd + ripgrep
---

# /docs-search

Fast, transparent search across project documentation using `fd` + `rg` (ripgrep).

## Usage

```
/docs-search <query>
/docs-search "batch size"
/docs-search "async optimization" --files="docs/*.md"
/docs-search "hyperparameter" --case-insensitive
```

## What It Searches

**Priority order** (by relevance):
1. `docs/` - Project documentation (renamed from ai_docs/)
2. `specs/` - Feature specifications
3. `.claude/docs/` - Claude-specific knowledge (global)
4. Project root:
   - `CLAUDE.md` - Project conventions and ground truth
   - `README.md` - Setup and overview
   - `.claude/CLAUDE.md` - Global AI instructions

## How It Works

1. **Find relevant files** using `fd` (fast, respects .gitignore):
   - `*.md` files in docs/, specs/, README.md, CLAUDE.md
   - Excludes: node_modules, .git, dist, build

2. **Search content** using `rg` (ripgrep, blazing fast):
   - Case-insensitive by default
   - Shows line numbers and context
   - Highlights matches

3. **Return results** with:
   - File path and line number
   - 2 lines of context before/after match
   - Truncated if >20 results

## Examples

**Search for hyperparameters:**
```
/docs-search "learning rate"
```

**Search in specific directory:**
```
/docs-search "transformers" --files="docs/*.md"
```

**Case-sensitive search:**
```
/docs-search "API_KEY" --case-sensitive
```

## Performance

- **<2 seconds** on typical repos (even with 10k+ files)
- Indexes: None (real-time grep)
- Storage: Minimal (no database)
- Update: Automatic (searches latest git state)

## Advantages over Vector DB

| Aspect | docs-search | Vector DB |
|--------|-------------|-----------|
| Speed | 0.5-1.5s | 2-5s (API call) |
| Transparency | 100% (see every match) | ~30% (top-k) |
| Setup | Zero | Requires embedding API |
| Cost | Free | API calls ($) |
| Staleness | None (always current) | Requires re-indexing |
| False positives | Exact matches only | ~10-20% due to embeddings |

## Environment

Requires `fd` and `rg` (ripgrep) in PATH. Check with:
```bash
which fd rg
```

If missing, install via:
```bash
brew install fd ripgrep  # macOS
apt-get install fd ripgrep  # Linux (check your package manager)
```

## Implementation (for reference)

```bash
#!/bin/bash
query="$1"
options="${@:2}"

# Find markdown docs
fd -e md -E node_modules -E .git . | \
  grep -E "(docs/|specs/|CLAUDE\.md|README\.md)" | \
  xargs rg -i "$query" $options -H -n --context 2 | \
  head -100  # Limit output
```

This ensures:
- Exact matches (no ambiguity)
- All relevant files searched
- Fast results (<2s typical)
- No setup required

## Tips

- **Search ground truth**: `/docs-search CLAUDE` to find docs about CLAUDE.md
- **Find outdated references**: `/docs-search "old_function_name"`
- **Batch operations**: `/docs-search "TODO"` to find action items
- **Cross-project**: Works in any git repo with docs/

## Limitations

- **No fuzzy search** (must know exact term or substring)
- **No semantic search** (can't search by meaning)
- **Line length limit** (shows first ~2000 chars per line)

For advanced searching, try:
- `rg` CLI directly for regex patterns
- `fzf` for interactive browsing
- Vector DB if you need semantic search
