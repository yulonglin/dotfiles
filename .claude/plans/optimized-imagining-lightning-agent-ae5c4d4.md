# MATS Permissions Plugin Analysis

Research into `crazytieguy/alignment-hive` plugin system for evaluating what permission patterns to adopt.

## 1. `/mats:permissions` Skill Overview

**Location:** `plugins/mats/skills/permissions/SKILL.md` (28KB, single file)

**Trigger phrases:** "set up permissions", "configure permissions", "fix permission prompts", "allow commands", "update permissions", "reduce prompts", "stop asking for permission"

**Core purpose:** Generate Claude Code permission configurations that enable autonomous operation while maintaining security. Specifically designed for:
- Running Claude asynchronously (without `--dangerously-skip-permissions`)
- Reducing friction in interactive sessions
- Steering toward correct patterns (via deny rules)
- Preventing bypass vectors (via ask rules)

### 6-Step Interactive Workflow

| Step | Action | Automatic? |
|------|--------|------------|
| 1 | Project detection + audit existing permissions | Yes (auto) |
| 2 | 5 context questions + edit universally safe commands | Interactive |
| 3 | Script execution tier question + edit | Interactive |
| 4 | Web access preference question + edit | Interactive |
| 5 | MCP server permissions (if detected) | Interactive |
| 6 | Secrets + git + mode + cleanup batch | Interactive |

---

## 2. What `.claude/settings.json` Permissions It Configures

The skill produces a layered permission structure with these sections:

### 2a. Universally Safe Commands (~120 allow rules)

Read-only inspection commands that are safe in any project:

```
File inspection:  ls, find, cat, head, tail, wc, file, stat, du, df, diff, tree, realpath, basename, dirname
File creation:    mkdir
Search:           grep, rg, awk, sed -n (read-only sed), jq, yq
Text processing:  sort, uniq, cut, tr, printf, tee
Hashing/encoding: md5sum, sha256sum, base64
System info:      echo, pwd, which, type, command -v, uname, whoami, date, ps, pgrep, nvidia-smi, printenv, id, hostname, uptime, sleep, export, test, man, less, readlink
Localhost curl:   curl *://localhost*, curl *://127.0.0.1*, curl *://0.0.0.0*
Git read-only:    git status, git diff, git log, git show, git branch, git remote, git remote -v, git stash list, git rev-parse, git ls-files
```

**xargs variants:** For every safe read command, there's a corresponding `xargs` and `xargs -I{}` variant (e.g., `xargs cat`, `xargs cat *`, `xargs -I{} cat *`). This covers ~40 additional rules.

### 2b. Deny Rules (Always Applied)

```json
"deny": [
  "Bash(for *)",        // Loop bypass
  "Bash(while *)",      // Loop bypass
  "Bash(until *)",      // Loop bypass
  "Bash(timeout *)",    // Runs arbitrary command
  "Bash(env *)",        // env VAR=val COMMAND runs any command
  "Bash(bash -c *)",    // Executes string as bash
  "Bash(sh -c *)",      // Executes string as shell
  "Bash(zsh -c *)",     // Executes string as zsh
  "Bash(find * -exec *)",     // Arbitrary command execution
  "Bash(find * -execdir *)",  // Arbitrary command execution
  "Bash(awk *system\\(*)",    // awk system() call
  "Bash(xargs awk *system\\(*)",
  "Bash(xargs -I{} awk *system\\(*)",
  "Bash(xargs sh *)",         // xargs to shell
  "Bash(xargs -I{} sh *)",
  "Bash(xargs bash *)",
  "Bash(xargs -I{} bash *)",
  "Bash(cat)",                // Bare cat (stdin read, hangs)
  "Bash(git -C *)"           // Breaks permission matching
]
```

### 2c. Project-Specific Commands (Adapted Per Project)

For each detected script in `package.json`/`pyproject.toml`, two rules: exact + with-args.
Example: `Bash(bun run dev)` + `Bash(bun run dev *)`.

Also denies raw tool invocation to steer through the package manager:
- bun project: denies `eslint *`, `prettier *`, `tsc *`, `jest *`, `vitest *`, `node *`, `npx *`, `npm *`, `pnpm *`, `yarn *`
- uv project: denies `pytest *`, `mypy *`, `ruff *`, `python *`, `python3 *`, `pip *`, `poetry *`, `pipenv *`

### 2d. Web Access (3 Tiers)

| Tier | Allow | Ask |
|------|-------|-----|
| Specific domains | `WebFetch(domain:X)` for ~10 doc sites + `WebSearch` | - |
| WebFetch+WebSearch | `WebFetch`, `WebSearch` | - |
| Full curl GET | `WebFetch`, `WebSearch`, `curl`, `curl *` | 32 `curl` mutation patterns (`-X POST`, `-X PUT`, `-d`, `--data`, `-F`, `--form`, `-T`, `-H`, `-b`, `-u`, etc.) |

The curl ask rules are notably thorough: they cover every flag position permutation (flag before URL, after URL, between other flags) and both short/long forms.

### 2e. Git Permissions

```json
"allow": ["Bash(git add *)", "Bash(git commit:*)"]
```

Note: `git commit` uses `:*` (colon-star) instead of ` *` (space-star) because commit messages use heredoc syntax which ` *` fails to match.

### 2f. Secret Protection

Deny `Read()` on detected secret files:
```json
"deny": [
  "Read(**/.env)",
  "Read(**/.env.local)",
  "Read(**/.envrc)",
  "Read(**/.aws/credentials)",
  "Read(**/.ssh/*)",
  "Read(**/*.pem)",
  "Read(**/*_rsa)",
  "Read(**/*_ed25519)"
]
```

### 2g. Default Mode

```json
"defaultMode": "plan"
```

---

## 3. The "15 Allow / 3 Deny" Detection Pattern

From `best-practices.md`, the plugin checks whether permissions are "properly configured" using these conditions (ALL must pass):

1. At least **15 allow rules** total
2. At least **3 deny rules**
3. Has safe commands like `Bash(ls*)`, `Bash(cat *)`, `Bash(grep *)`
4. Has xargs variants like `Bash(xargs cat*)`, `Bash(xargs -I{} head *)`
5. Has deny patterns like `Bash(for *)`, `Bash(timeout *)`
6. Has project-specific commands if applicable

If ANY condition fails, the best-practices command offers to run `/mats:permissions`.

---

## 4. Bypass Vectors Always Blocked

The SKILL.md identifies a general principle: **any command that takes another command or code string as an argument is a bypass vector.**

Full list:
```
Bash(env *)           # env VAR=val COMMAND runs any command
Bash(xargs *)         # pipes input to any command (generic)
Bash(bash -c *)       # executes string as bash
Bash(sh -c *)         # executes string as shell
Bash(eval *)          # evaluates arbitrary code
Bash(time *)          # time COMMAND runs any command
Bash(timeout *)       # timeout N COMMAND runs any command
Bash(exec *)          # replaces shell with command
Bash(nohup *)         # nohup COMMAND runs any command
Bash(nice *)          # nice COMMAND runs any command
Bash(python -c *)     # executes Python string
Bash(python3 -c *)    # executes Python string
Bash(node -e *)       # executes JavaScript string
Bash(perl -e *)       # executes Perl string
Bash(ruby -e *)       # executes Ruby string
Bash(bun run *)       # runs arbitrary scripts (allow specific instead)
Bash(npm run *)       # runs arbitrary scripts (allow specific instead)
```

**Audit check:** The skill scans existing permissions for these patterns and flags them.

Note the nuanced approach: `xargs` is denied generically (`Bash(xargs *)`) in the audit checklist, but the actual configuration allows safe-target xargs (`Bash(xargs cat *)`, `Bash(xargs file *)`) while denying dangerous ones (`Bash(xargs sh *)`, `Bash(xargs bash *)`).

---

## 5. Security Posture Questions

Five questions asked in a single batch via `AskUserQuestion`:

| # | Question | Options | Drives |
|---|----------|---------|--------|
| Q1 | "Is there sensitive information on this machine or that Claude might work with?" | No / Yes | Web access tier |
| Q2 | "Could Claude cause damage that's hard to undo? (local files, databases, cloud resources)" | No / Yes | Script execution tier |
| Q3 | "How important is it that Claude can work autonomously?" | Not very / Important | Script execution tier |
| Q4 | "Where should permissions be stored?" | Split (recommended) / Shared only / Personal only | Target file (settings.json vs settings.local.json) |
| Q5 | "Add universally safe commands?" | Yes (recommended) / No | Whether to add ~120 safe commands |

---

## 6. Script Execution Tiers

Four tiers, recommended based on Q2 (damage) x Q3 (autonomy):

| Hard to undo? | Autonomy important? | Recommended Tier |
|---------------|---------------------|-----------------|
| Yes | Yes | Temp folder scripts |
| Yes | No | Project scripts only |
| No | Yes | Full execution |
| No | No | Temp folder scripts |

### Tier Details

**No scripts:** Only lint/format/typecheck. Testing requires prompts. Note: "Test files could be edited to run unintended code."

**Project scripts only:** Scripts defined in package.json/pyproject.toml + detected in scripts/. Permission prompts for one-off scripts.

**Temp folder scripts:** Scripts in `/tmp/claude-execution-allowed/<project>/` allowed. One permission prompt per session when first writing there. Enables arbitrary code execution.

**Full execution:** `uv run *`, `bun run *`, `bash scripts/*` fully allowed. Enables arbitrary code execution via the package manager.

Each tier gets corresponding CLAUDE.md guidance explaining what patterns to use (e.g., "write a script in /tmp/..." for temp tier, "break into simpler sequential commands" for no-scripts tier).

---

## 7. Additional Patterns

### Deprecated Syntax Detection
- Old: `cmd:*` (colon-star)
- New: `cmd` + `cmd *` (space-star, two rules)
- Exception: `git commit:*` must use colon-star because commit messages use heredoc syntax

### Wildcard Pattern Rules
- Always use `cmd` + `cmd *` (never `cmd*` which would match `cmdFOO`)
- Exception: heredoc-using commands use `cmd:*`

### CLAUDE.md Guidance
Each configuration step also adds corresponding guidance to CLAUDE.md:
- Bash operations section (simple ops OK, xargs for bulk, avoid string interpolation/heredocs/loops)
- Running commands section (adapted per script tier)
- curl guidance (when full GET is enabled)

### Settings Strategy (Split vs Shared vs Personal)
- **Split:** Universally safe → settings.json, personal prefs → settings.local.json
- **Shared:** Everything → settings.json
- **Personal:** Everything → settings.local.json

---

## 8. Gap Analysis: Our Current Config vs MATS Patterns

### What We Already Do Well
- Default plan mode
- WebSearch + WebFetch allowed
- Git commit allowed (with `:*` syntax)
- Destructive git commands denied (reset --hard, push --force, clean, branch -D, checkout --)
- Destructive file commands denied (rm -rf, rm -r, shred, truncate, dd, mkfs, etc.)
- Process kill commands in "ask" tier

### What We're Missing (Worth Adopting)

1. **Bypass vector blocks:** We allow `nohup *`, `for *`, `while *`, `env *` (via `Bash(for:*)` etc). MATS denies all loop constructs and command-wrapping commands. Our `Bash(nohup:*)` is explicitly listed as a bypass vector.

2. **Colon-star deprecation:** We use `:*` syntax throughout (`Bash(grep:*)`). MATS says this is deprecated and should be `Bash(grep)` + `Bash(grep *)` (except for heredoc commands like `git commit:*`).

3. **xargs safety:** We don't have xargs rules at all. MATS allows safe-target xargs (`xargs cat`, `xargs file`) while denying dangerous ones (`xargs sh`, `xargs bash`).

4. **Bare command blocks:** MATS denies `Bash(cat)` (bare cat hangs on stdin) and `Bash(git -C *)` (breaks permission matching). We don't block these.

5. **Secret file protection:** We don't deny `Read()` on .env, credentials, SSH keys. MATS blocks these at the permission level.

6. **Package manager steering:** MATS denies raw tool invocation (`python *`, `pytest *`) and steers through `uv run`. We allow both `pytest:*` and `uv run pytest:*`.

7. **curl mutation protection:** We don't have any curl rules. If we enabled curl, we'd want the thorough ask-rules for POST/PUT/DELETE/data/headers.

### What We Do Differently (Intentional)

- We allow `python:*` / `python3:*` directly (MATS would deny, steering through `uv run`)
- We allow `for:*` / `while:*` (MATS denies as bypass vectors)
- We use sandbox mode with `autoAllowBashIfSandboxed: true` (different security model)
- We have broader git permissions (checkout, fetch, push, restore, stash)
- We have Hydra-specific rules (`HYDRA_FULL_ERROR=1 uv run python:*`)

### Recommendations for Adoption

**High priority (security):**
- [ ] Deny bypass vectors: `env *`, `bash -c *`, `sh -c *`, `eval *`, `exec *`, `time *`, `timeout *`, `nice *`
- [ ] Deny code-string execution: `python -c *`, `python3 -c *`, `node -e *`
- [ ] Deny `find * -exec *` and `find * -execdir *`
- [ ] Deny `Bash(cat)` (bare, hangs on stdin)
- [ ] Deny `Bash(git -C *)` (breaks permission matching)
- [ ] Add `Read(**/.env)`, `Read(**/.env.local)`, `Read(**/.envrc)` to deny list

**Medium priority (correctness):**
- [ ] Migrate from `:*` to space-star syntax (except `git commit:*`)
- [ ] Add xargs safety rules (allow safe targets, deny shell targets)
- [ ] Reconsider `nohup:*` — currently allowed, is a bypass vector

**Low priority (nice to have):**
- [ ] Add bare-command + with-args pattern for each tool
- [ ] Consider settings.local.json split for personal preferences
- [ ] Add CLAUDE.md bash operations guidance section

**Intentionally skip:**
- Package manager steering (we want `python *` directly)
- Loop denials (we use `for:*` / `while:*` intentionally)
- curl mutation ask-rules (not needed unless we add curl to allow)
