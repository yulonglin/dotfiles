---
name: verify-git-remote
enabled: true
event: bash
pattern: git\s+remote\s+add
action: block
---

**Git remote add blocked — verify the remote first.**

Before adding a git remote, you MUST verify the URL is correct:

1. **If this is a fork**, check the parent via GitHub API:
   ```
   curl -s "https://api.github.com/repos/{owner}/{repo}" | python3 -c "import sys,json; r=json.load(sys.stdin); print(f'Parent: {r[\"parent\"][\"full_name\"]}') if r.get('parent') else print('Not a fork')"
   ```
2. **If not a fork**, ask the user for the correct upstream URL — do not guess from commit messages, PR authors, or repo naming conventions.

Only proceed with `git remote add` after confirming the URL with the user or the GitHub API.
