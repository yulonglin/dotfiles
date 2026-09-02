# Safety

## Irreversible actions

Prefer `archive/` over `trash` over `rm`, and don't `rm -rf` unless asked. The git stash stack is shared across worktrees, so `stash push -u -m '<tag>'` then `apply <sha>` — never bare `stash` or `pop`, and `stash show -p` before dropping. Never commit API keys, tokens or credentials. When `Edit` fails with "file modified since read", re-read and retry rather than `Write` over the file. Never `git add -A` in-sandbox: on Linux, denied paths are masked as phantom character devices that it would stage — use explicit pathspecs.

A restore or git operation that failed under the sandbox is intact — retry with `dangerouslyDisableSandbox: true`. Sandbox failure modes and their fixes are in the `jobs` skill.

Hooks enforce some of this independently: `block_destructive_git.sh` refuses `reset --hard`, `checkout -- <path>`, `clean -f`, bare `stash` and `stash pop`.

## Supply chain

A quarantine or malware-check block is the defense working, not a bug: name the package, version and guard, then stop. Never bypass it, and never do any of these without explicit approval — adding a third-party Homebrew tap, installing from an arbitrary URL or git repo, re-enabling lifecycle scripts, bypassing `min-release-age`, unsetting `UV_MALWARE_CHECK`, or passing `--no-quarantine`.

API keys are scoped per-project via `setup-envrc` and direnv, never globally exported. A project without `.envrc` genuinely cannot see them.

## Google Workspace

Never delete, only trash — deletions across Workspace are irreversible, so if something must be permanently gone the user does it in the UI. Never send email, only draft, even when told to send it. Hooks match the Bash `gws` path only, so MCP tool calls are governed by this file alone.

## Desktop

Ask before anything that launches a GUI app, moves focus or the cursor, types keystrokes, or rearranges windows — keystrokes land wherever focus is, and authorization is per-task. Read-only screenshots and listing calls need no permission. `dangerouslyDisableSandbox` grants filesystem access, never permission to seize the cursor; the sandbox cannot tell whether the user is at the machine. Prefer the CLI or MCP path when one exists, which removes the question entirely.
