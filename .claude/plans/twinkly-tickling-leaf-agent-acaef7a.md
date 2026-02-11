# Critique: Auto-Background Long-Running Bash Commands Plan

Review of `twinkly-tickling-leaf.md` -- the PreToolUse hook for auto-backgrounding.

---

## 1. Correctness: `updatedInput` and `permissionDecision`

### 1a. `updatedInput` is partial-merge, not replace

The official docs state: "The updatedInput field contains a partial object that replaces fields in the original tool input. Only fields present in updatedInput are replaced; other fields remain unchanged." ([Hooks reference](https://code.claude.com/docs/en/hooks))

**Issue with the plan**: Line 71 says "updatedInput includes the full original tool_input merged with run_in_background: true (safe regardless of whether the API does merge vs replace)." This is technically safe but wasteful. The hook only needs to return:

```json
"updatedInput": { "run_in_background": true }
```

Not the full `{"command": "...", "run_in_background": true}`. Passing the full command is harmless (it's a no-op merge) but adds unnecessary complexity to the hook script -- you need to reconstruct the full tool_input object via jq instead of just emitting a one-field object.

**Recommendation**: Simplify to only pass `{"run_in_background": true}` in `updatedInput`. This is cleaner and avoids any risk of corrupting the command string through jq re-serialization (e.g., escaping issues in commands containing quotes, backslashes, or unicode).

### 1b. `permissionDecision: "allow"` bypasses the permission prompt

The docs say: `"allow"` bypasses the permission system. This is a **security concern** the plan underestimates.

When this hook returns `permissionDecision: "allow"`, it is not just setting `run_in_background`. It is also **auto-approving the command** -- the user will never see a permission prompt for it, even if the command would normally require one.

Consider: `pip install some-malicious-package`. This would normally prompt the user for permission (not in the allow-list in settings.json). But the auto-background hook matches `pip install` and returns `permissionDecision: "allow"`, silently approving AND backgrounding it. The user never sees the command at all.

**This is a real problem.** The plan's Tier 1 patterns include commands that ARE NOT in the permissions allow-list:
- `brew install`, `brew upgrade` -- not in allow-list
- `apt install`, `apt update` -- not in allow-list
- `docker build`, `docker compose up` -- not in allow-list
- `cargo build`, `cargo test` -- not in allow-list
- `npm install`, `npm ci` -- not in allow-list
- `git clone` -- not in allow-list

**Fix options**:
1. **Use `permissionDecision: "ask"` with `updatedInput`** -- this shows the modified input (with `run_in_background: true`) to the user for approval. The user sees "Run `npm install` in background?" and can approve/deny. This preserves the security model while still injecting the background flag.
2. **Only use `permissionDecision: "allow"` for commands that are already in the permissions allow-list** -- but this defeats the purpose since those commands already run without prompts.
3. **Drop `permissionDecision` entirely and only use `additionalContext`** -- suggest backgrounding but let Claude and the permission system handle it normally. This is the safest approach but loses the deterministic guarantee.

My recommendation: **Use `"ask"` not `"allow"` for Tier 1.** The user gets a single confirmation that also shows the background flag. After a few approvals they can add the pattern to their allow-list if they want full auto-approval.

### 1c. "Deny wins" across matcher groups -- confirmed correct

The [official docs](https://code.claude.com/docs/en/hooks) confirm: when multiple hooks fire on the same event, deny takes precedence. The plan's assertion that `check_secrets.sh` (exit 2 = deny) still blocks even when the auto-background hook returns "allow" is correct.

However, the interaction is more subtle than the plan acknowledges. The hooks run **in parallel** (per docs: "All matching hooks run in parallel"). So the sequence is:

1. All Bash PreToolUse hooks fire simultaneously
2. `check_secrets.sh` returns exit 2 (deny) for `git commit` with secrets
3. `auto_background.sh` returns allow + updatedInput for... well, `git commit` does not match any Tier 1 pattern, so this is fine

But consider `git clone <url-with-embedded-token>`. The auto-background hook matches `git clone` (Tier 1) and returns allow. If `check_secrets.sh` also catches the token pattern, deny wins. Good. But if `check_secrets.sh` only checks `git commit|add` (which it does -- line 21), the token-bearing clone sails through auto-approved.

**This is an interaction gap the plan should document.** The auto-background hook's `permissionDecision: "allow"` becomes the effective security gate for any command it matches that is NOT already covered by other hooks.

---

## 2. Pattern Quality

### 2a. False positives (annoying)

| Pattern | Problem | Severity |
|---------|---------|----------|
| `make` (without `-n`) | `make clean` takes <1s, `make lint` takes <2s. Only `make` with no target or `make all`/`make build` is slow | **High** -- `make` is extremely common |
| `npm test` | Many projects have `npm test` that runs a single file in <3s | Medium |
| `cargo test` | `cargo test -- --test-name` runs a single test instantly | Medium |
| `go test ./...` | Correct to background, but `go test ./pkg/foo` is fast | Low (regex is specific) |
| `python.*train\|finetune\|eval` | `python evaluate.py --quick` or `python training_utils.py --help` would match | Medium |
| `pip install` | `pip install --upgrade pip` takes ~3s. `pip install -e .` in a small project is fast | Low |

**Recommendations**:
- `make` should be Tier 2 (suggest), not Tier 1 (force). Or restrict Tier 1 to `make\s*$` (bare make), `make\s+(all|build|install|release)`, and `make\s+test`
- `npm test` / `cargo test` should be Tier 2 when they have specific test file arguments
- The `python.*train` regex needs word boundaries: `python.*\b(train|finetune|eval)\b` to avoid matching `training_utils` or `evaluate_config`

### 2b. False negatives (missed patterns)

| Pattern | Why it's long-running | Suggested Tier |
|---------|----------------------|----------------|
| `sleep N` (N > 5) | Explicitly waits | Tier 1 for sleep >30, Tier 2 for sleep 5-30 |
| `npm run dev`, `npm start`, `yarn dev` | Dev servers run indefinitely | Tier 1 |
| `python -m flask run`, `python -m uvicorn`, `uvicorn`, `gunicorn` | Web servers | Tier 1 |
| `npx next dev`, `npx vite`, `npx webpack serve` | Dev servers | Tier 1 |
| `docker compose up` (already listed) | Good | -- |
| `terraform apply`, `terraform plan` | Can take 5+ minutes | Tier 2 |
| `ansible-playbook` | Often takes minutes | Tier 2 |
| `bun install`, `pnpm install` | Package managers (plan only has npm/pip/uv/brew/apt) | Tier 1 |
| `yarn install`, `yarn add` | Package manager | Tier 1 |
| `cargo build --release` | Much slower than debug build | Tier 1 (already covered by `cargo build`) |
| `tsc` (TypeScript compiler) | Can be slow on large projects | Tier 2 |
| `eslint .`, `prettier --write .` on entire repo | Can take minutes | Tier 2 |

**Critical miss**: Dev servers (`npm run dev`, `flask run`, etc.) are the most common case where Claude forgets to background. These run *forever* and will hang the session completely. They should be Tier 1.

### 2c. Exclusion gaps

The plan's exclusions list `--version`, `--help`, `--dry-run`, plus read-only commands. Missing:

| Pattern | Why exclude |
|---------|-------------|
| `pip install` inside a venv creation compound (`python -m venv ... && pip install`) | The whole compound is fast if it's just a venv + 1 package |
| `npm install <single-package>` vs `npm install` (no args) | Single package install is often <5s |
| `make -j1 check` or `make -n` | `-n` is listed but `-j1` might be a dry-run variant in some projects |
| `docker build --dry-run` | docker dry-run |
| Commands starting with `time ` | `time make build` -- the timing wrapper doesn't change the backgrounding need but the regex won't match |
| Commands with `sudo` prefix | `sudo apt install` should still match |
| Commands with env var prefix | `NODE_ENV=production npm run build` should still match |

**The `sudo` and env-var-prefix cases are important.** The regex patterns match `npm install` but not `sudo npm install` or `CI=true npm install`. The hook needs to strip common prefixes before matching.

### 2d. Compound command handling (`&&`, `||`, `;`, `|`)

The plan does not address compound commands at all. Consider:

- `npm install && npm run build` -- should background (both parts are long)
- `echo "starting" && npm install` -- should background (dominant part is long)
- `npm install && npm test && npm run deploy` -- should background
- `git add . && git commit -m "msg"` -- should NOT background (fast)
- `npm install | tee install.log` -- should background (pipe doesn't change duration)

**Recommendation**: For compound commands, check if ANY segment matches a Tier 1 pattern. For piped commands, check the first command (left side of `|`).

---

## 3. Architecture

### 3a. Separate matcher group -- correct but with caveats

The separate matcher group approach is the right call, confirmed by [bug #15897](https://github.com/anthropics/claude-code/issues/15897). Hooks within the same matcher group run in parallel and `updatedInput` from one hook gets overwritten by another hook that returns no `updatedInput`.

However, the plan should note: the docs say "All matching hooks run in parallel" across ALL matcher groups, not just within one. The separate matcher group fixes the `updatedInput` overwrite bug, but both groups' hooks still run in parallel. This means:

- `check_secrets.sh` and `auto_background.sh` run at the same time
- Both read the same original `tool_input` from stdin
- Results are aggregated: deny wins over allow

This is fine for the plan's goals.

### 3b. Alternative: PermissionRequest hook instead of PreToolUse

The plan chose PreToolUse. An alternative is PermissionRequest, which fires only when a permission dialog would appear. Pros and cons:

| Aspect | PreToolUse | PermissionRequest |
|--------|-----------|-------------------|
| Fires when | Every tool call | Only when permission needed |
| Can modify input | Yes (updatedInput) | Yes (updatedInput) |
| Auto-approve | Yes (permissionDecision: allow) | Yes (behavior: allow) |
| Fires in headless mode | Yes | **No** (docs: "PermissionRequest hooks do not fire in non-interactive mode") |
| Commands already allowed | Fires (hook runs needlessly) | Does not fire (no dialog) |
| Security concern | Hook auto-approves things user might want to review | Hook only runs when user would be prompted anyway |

**PermissionRequest is actually better for commands that need permission** because it doesn't add an auto-approval bypass. The hook would only run when the user would see a prompt anyway, and it can modify the input to add backgrounding before showing the prompt.

**But**: Commands in the allow-list (like `python`, `pytest`, `uv run`) would never trigger PermissionRequest, so the hook would never fire for them. These commands already auto-execute, so the only thing the hook would add is the background flag. For these, you NEED PreToolUse.

**Recommendation**: Consider a hybrid approach, or just use PreToolUse with `permissionDecision: "ask"` instead of `"allow"` (see section 1b).

### 3c. Why not just use `additionalContext`?

A simpler approach: return only `additionalContext` with a strong suggestion to background, no `updatedInput` or `permissionDecision`. This is what Tier 2 already does.

Downside: Claude might ignore the suggestion. The whole point of the hook is deterministic backgrounding. But this avoids ALL the security concerns of `permissionDecision: "allow"`.

Worth considering making the **default mode** `suggest` (Tier 2 for everything) and letting users opt into `force` mode via `CLAUDE_AUTOBACKGROUND_MODE=force`. This inverts the risk profile.

---

## 4. `updatedInput` Merge vs Replace

### Confirmed: Partial merge

The official docs say: "Only fields present in updatedInput are replaced; other fields remain unchanged." This means:

```json
"updatedInput": { "run_in_background": true }
```

Will merge into the original tool_input, preserving `command`, `description`, `timeout`, etc. The plan's approach of including the full `command` in `updatedInput` is unnecessarily complex.

### Risk of re-serializing the command

If the hook does `jq` round-trip of the command string, it could corrupt edge cases:
- Commands with literal `\n` or `\t`
- Commands with embedded quotes
- Commands with null bytes (unlikely but possible)

By only passing `{"run_in_background": true}`, you avoid this entirely.

---

## 5. Interaction with Existing Hooks

### 5a. auto_log.sh sees the ORIGINAL input

The auto_log.sh hook is in the SAME PreToolUse matcher group (group 1) and runs as `async: true`. It reads `tool_input.command` from stdin. Since all hooks receive the same stdin (the original tool_input), auto_log.sh will log the original command -- it will NOT see the `run_in_background: true` modification.

**This is actually fine** -- you want to log what was requested, and the background flag is an implementation detail. But the plan should document this explicitly.

### 5b. PostToolUse hooks

The `truncate_output.sh` PostToolUse hook processes command output. For backgrounded commands, the output won't be available at PostToolUse time (it runs asynchronously). This means truncate_output.sh won't fire or will see empty output.

**This is fine but worth noting** -- backgrounded commands are checked via TaskOutput, not inline output.

### 5c. check_pipe_buffering.sh

This hook warns about piping through `less`/`more`/`head`. If a piped command matches an auto-background pattern (e.g., `npm install | tee install.log`), it will be backgrounded while also receiving the pipe warning. The warning goes to stderr (not to Claude), so it's harmless but useless for a backgrounded command.

### 5d. check_destructive_commands.sh

This hook blocks `sudo rm -r`, `xargs kill`, etc. with exit 2. Since deny wins, even if auto_background.sh matches and returns allow, the deny from check_destructive_commands.sh will prevail. **Correct behavior, no issue.**

---

## 6. Missing Concerns

### 6a. `sleep N` commands

`Bash(sleep:*)` is in the permissions allow-list (line 28 of settings.json). So `sleep 300` auto-executes without prompts. The auto-background hook should detect `sleep` with a high number and background it, otherwise it blocks the session for 5 minutes.

Regex suggestion: `sleep\s+([3-9][0-9]|[1-9][0-9]{2,})` (sleep >= 30 seconds).

### 6b. Dev servers (critical miss)

See section 2b. `npm run dev`, `flask run`, `uvicorn`, `next dev` -- these are THE most common case where backgrounding matters because they run indefinitely. Not in the plan at all.

### 6c. Commands with `tee`

`npm install 2>&1 | tee install.log` -- the pipe makes the regex harder. The hook should match the first command in a pipeline, not the whole string.

### 6d. `timeout` wrapper

`timeout 300 make build` -- the `timeout` command wraps a potentially long command. The hook should strip `timeout N` prefix before pattern matching.

### 6e. What happens when a backgrounded command fails?

The plan doesn't address UX for when auto-backgrounded commands fail silently. If `npm install` is backgrounded and fails, Claude might proceed with code that depends on those packages. The `additionalContext` message should prompt Claude to check TaskOutput before proceeding.

### 6f. `run_in_background` already true

The plan correctly handles this (skip if already true). But note: the check is `jq -r '.tool_input.run_in_background'` -- this returns `"true"` (string) for JSON `true` (boolean) and `"null"` for absent. The comparison needs to handle both cases.

---

## 7. Robustness

### 7a. jq dependency

The plan assumes jq is available. All existing hooks (`check_pipe_buffering.sh`, `check_destructive_commands.sh`, etc.) also assume jq. But `check_read_size.sh` has an explicit jq check:

```bash
if ! command -v jq >/dev/null 2>&1; then
    echo '{"decision": "allow", "systemMessage": "check_read_size.sh: jq not installed, hook disabled"}'
    exit 0
fi
```

The auto_background hook should do the same. Fail open (exit 0, no output) if jq is missing.

### 7b. JSON input format changes

If Claude Code changes the tool_input schema (e.g., renames `command` to `cmd`), the hook silently fails open (empty COMMAND, no match, exit 0). This is the correct failure mode.

### 7c. Edge case: very long commands

`jq -r '.tool_input.command'` on a very long command (e.g., a heredoc embedded in the command string) could be slow or hit shell argument limits. The hook should have a size check or timeout.

### 7d. `set -euo pipefail`

Existing hooks use `set -euo pipefail`. If any jq command fails (malformed JSON), the script exits with code 1 (non-blocking error, stderr in verbose mode). This is acceptable but the plan should note it's a deliberate choice.

### 7e. Regex engine differences

The plan uses `grep -qE` patterns. GNU grep and BSD grep (macOS) have slightly different regex behaviors. Patterns should be tested on macOS specifically since that's the primary platform. The existing hooks use the same approach, so this is a known-acceptable risk.

### 7f. Environment variable quoting

`CLAUDE_AUTOBACKGROUND_EXTRA` for additional patterns -- if patterns contain special characters (e.g., `|`), they need careful quoting. The plan should document the exact syntax expected.

---

## 8. Summary of Recommended Changes

### Critical (must fix before implementing)

1. **Do NOT use `permissionDecision: "allow"`** -- use `"ask"` instead, or make `suggest` the default mode. The `"allow"` approach silently auto-approves commands that the user's permission config would normally prompt for.

2. **Simplify `updatedInput` to `{"run_in_background": true}` only** -- don't include the command. Partial merge is confirmed behavior; including the command risks jq re-serialization bugs.

3. **Add dev server patterns to Tier 1** -- `npm run dev`, `yarn dev`, `flask run`, `uvicorn`, `gunicorn`, `next dev`, `vite`. These are the most impactful missing patterns.

### Important (should fix)

4. **Move `make` to Tier 2** or restrict to `make\s+(all|build|install|release|test)?$` -- bare `make` and specific slow targets only.

5. **Handle command prefixes** -- strip `sudo`, `env VAR=val`, `time`, `timeout N` before pattern matching.

6. **Handle compound commands** -- check if any `&&`/`;` segment matches a Tier 1 pattern.

7. **Add jq availability check** -- fail open with exit 0 if jq is missing.

8. **Add `sleep N` (N >= 30)** to Tier 1.

9. **Add `bun install`, `pnpm install`, `yarn install`** to Tier 1 -- plan only covers npm/pip/uv/brew/apt.

### Nice to have

10. **Add word boundaries** to ML patterns: `\b(train|finetune|eval)\b` not `train|finetune|eval`.

11. **Document the auto_log.sh interaction** -- it logs original input, not modified.

12. **Consider default mode = suggest** with opt-in to force via env var, to minimize surprise.

13. **Handle piped commands** by matching left side of `|`.

14. **Add `additionalContext` reminder** to check TaskOutput, since backgrounded failures are silent.

---

## Sources

- [Hooks reference - Claude Code Docs](https://code.claude.com/docs/en/hooks)
- [Automate workflows with hooks - Claude Code Docs](https://code.claude.com/docs/en/hooks-guide)
- [BUG: updatedInput not working with multiple PreToolUse hooks - #15897](https://github.com/anthropics/claude-code/issues/15897)
- [Feature Request: Enhance PreToolUse Hooks to Modify Tool Inputs - #4368](https://github.com/anthropics/claude-code/issues/4368)
- [Hook development skill - plugin-dev](https://github.com/anthropics/claude-code/blob/main/plugins/plugin-dev/skills/hook-development/SKILL.md)
- [Claude Code power user hooks blog post](https://claude.com/blog/how-to-configure-hooks)
