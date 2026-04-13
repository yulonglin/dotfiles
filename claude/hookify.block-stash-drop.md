---
name: block-stash-drop
enabled: true
event: bash
pattern: git\s+stash\s+drop
action: block
---

**BLOCKED: git stash drop is destructive and irreversible.**

Before dropping any stash:

1. **Verify contents first:** `git stash show -p stash@{N}` to see the full diff
2. **Try applying instead:** Use `git stash apply` (keeps stash as backup) rather than `git stash pop` (deletes on success)
3. **If stash/pop partially failed** (sandbox issues): retry with `dangerouslyDisableSandbox: true` — the stash data is fine, only the restore was blocked

**To proceed:** Ask the user to confirm they want the stash dropped, stating what's in it.
