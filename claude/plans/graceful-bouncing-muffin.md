# Plan: Push slack-mcp-server to yulonglin namespace

## Context

Current remote `origin` points to `korotovsky/slack-mcp-server`. The branch is 1 commit ahead of origin/master (14 files, channel recency sorting + security hardening). There are also untracked files (`.claude/`, `CLAUDE.md`, and a `slack-mcp-server` binary).

The user wants to push to their own `yulonglin` namespace on GitHub, ideally as a fork.

**Note**: `gh` CLI requires sandbox bypass (TLS cert issue in sandbox). Auth is valid.

## Steps

### 1. Fork the repo to yulonglin namespace
```bash
gh repo fork korotovsky/slack-mcp-server --clone=false --remote-name=origin
```
This will:
- Create `yulonglin/slack-mcp-server` as a fork on GitHub
- Rename current `origin` → `upstream`
- Add `yulonglin/slack-mcp-server` as new `origin`

### 3. Commit untracked project files
- Add `.claude/` and `CLAUDE.md` (project config, useful to keep)
- **Skip** `slack-mcp-server` binary (add to `.gitignore`)

```bash
echo "/slack-mcp-server" >> .gitignore
git add .gitignore .claude/ CLAUDE.md
git commit -m "Add project config (CLAUDE.md, .claude/)"
```

### 4. Push to fork
```bash
git push origin master
```

## Fallback (if fork is troublesome)

If forking fails or causes issues, create a fresh repo instead:
```bash
gh repo create yulonglin/slack-mcp-server --public --source=. --remote=origin --push
```

## Verification

- `git remote -v` shows `yulonglin/slack-mcp-server` as origin
- `gh repo view yulonglin/slack-mcp-server` succeeds
- All commits are visible on GitHub
