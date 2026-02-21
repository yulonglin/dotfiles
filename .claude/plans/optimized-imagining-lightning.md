# Alignment-Hive / Coven + Permission Hardening

## Context

Evaluating tools from MATS workshop ([alignment-hive](https://github.com/crazytieguy/alignment-hive), [coven](https://github.com/Crazytieguy/coven)) for integration into dotfiles. During evaluation, a deep permission audit revealed significant security gaps in `claude/settings.json`.

**Research method:** 11 agents across 3 models (Claude, Codex gpt-5.3, Gemini 2.5 Pro) plus tooling engineer and security reviewer.

---

## Tool Verdicts

| Tool | Decision | Rationale |
|------|----------|-----------|
| **remote-kernels** | **Add** (research profile) | Dynamic GPU pod management fills a real gap |
| **coven** | **Install** (brew + install.sh) | Better display than raw `claude -p` — confirmed by source analysis |
| **llms-fetch-mcp** | **Add** (base profile, `bunx`) | Lightweight llms.txt complement to context7 |
| **Permission hardening** | **Do now** | All 4 reviewers flagged critical gaps |
| mats plugin | Skip | Too MATS-specific; cherry-pick patterns instead |
| hive-mind | Skip | Community feature, not needed |

---

## Part A: Permission Hardening (`claude/settings.json`)

### Reviewer consensus (4/4 agreed on these)

| Finding | All reviewers | Action |
|---------|--------------|--------|
| `allowedDomains: ["*"]` is the #1 gap | Gemini, Codex, Security, Tooling | **Restrict to allowlist** |
| Deny overrides sandbox auto-allow | All 4 confirmed | Deny list is effective |
| `env *` should be ASK not DENY | Codex, Tooling | **ASK** (legitimate `env VAR=val cmd` pattern) |
| `time *` should be ALLOW | Codex, Tooling | **ALLOW** (read-only instrumentation) |
| `bash -c *`, `eval *`, `exec *` should be DENY | Gemini, Security, Tooling (Codex: ASK) | **DENY** (3 of 4 agree) |
| Add `curl *` / `wget *` to ASK | Gemini, Security | **ASK** |
| `for:*` / `while:*` in allow is a universal bypass | Security (critical finding) | **Move to ASK** |
| `cat:*` etc in allow bypasses Read deny rules | Security | **Accept as limitation** — removing cat breaks too many workflows; sandbox provides primary defense |
| `allowUnsandboxedCommands: true` is risky | Codex, Security | **Defer** — evaluate after other changes |

### Additional findings (2+ reviewers)

| Finding | Reviewers | Action |
|---------|-----------|--------|
| `git push --force-with-lease` bypasses force deny | Codex | **Add to deny** |
| `sudo *` missing | Codex | **Add to deny** |
| `perl -e *`, `ruby -e *` missing | Gemini, Security | **Add to ask** |
| `ssh *`, `scp *`, `nc *` missing | Security | **Add to ask** |
| `bun run` common subcommands too noisy as ASK | Tooling | **Allow known-safe: dev/test/build/lint/start** |
| `npm run` same | Tooling | **Allow known-safe: test/build/lint/start** |
| PreToolUse hooks for compound patterns | Security, Codex | **Follow-up task** (separate from this change) |

### Final permission changes

#### DENY (add)
```json
"Bash(bash -c *)",
"Bash(sh -c *)",
"Bash(zsh -c *)",
"Bash(eval *)",
"Bash(exec *)",
"Bash(xargs sh *)",
"Bash(xargs bash *)",
"Bash(sudo *)",
"Bash(git push --force-with-lease *)"
```

#### ASK (add)
```json
"Bash(env *)",
"Bash(python -c *)",
"Bash(python3 -c *)",
"Bash(node -e *)",
"Bash(perl -e *)",
"Bash(ruby -e *)",
"Bash(nohup *)",
"Bash(timeout *)",
"Bash(find * -exec *)",
"Bash(find * -execdir *)",
"Bash(bun run *)",
"Bash(npm run *)",
"Bash(xargs *)",
"Bash(curl *)",
"Bash(wget *)",
"Bash(ssh *)",
"Bash(scp *)",
"Bash(nc *)",
"Bash(cat)",
"Read(**/.env)",
"Read(**/.env.*)",
"Read(**/.envrc)"
```

#### ALLOW (add)
```json
"Bash(time *)",
"Bash(bun run dev *)",
"Bash(bun run test *)",
"Bash(bun run build *)",
"Bash(bun run lint *)",
"Bash(bun run start *)",
"Bash(npm run test *)",
"Bash(npm run build *)",
"Bash(npm run lint *)",
"Bash(npm run start *)"
```

#### ALLOW (move to ASK)
```
"Bash(nohup *)"   → ask
```

#### ALLOW (keep, protect with PreToolUse hook)
```
"Bash(for *)"      — keep in allow, add hookify rule to inspect inner commands
"Bash(while *)"    — keep in allow, add hookify rule to inspect inner commands
```

The security reviewer flagged that `for x in 1; do DENIED_CMD; done` bypasses deny rules
because the command starts with `for`. Rather than moving to ask (too noisy), we'll add a
PreToolUse hook that inspects the body of for/while loops for denied patterns. This is the
best-of-both-worlds approach: no approval fatigue, but inner commands are still checked.

#### Network sandbox
The wildcard `["*"]` doesn't actually work — user still gets prompted for many sites.
Domain list scraped from all local `settings.local.json` files (15 domains used by Claude Code
infrastructure) plus research-relevant additions:

```json
"network": {
  "allowedDomains": [
    "*",
    "api.anthropic.com",
    "mcp-proxy.anthropic.com",
    "storage.googleapis.com",
    "api.githubcopilot.com",
    "mcp.context7.com",
    "registry.npmjs.org",
    "http-intake.logs.us5.datadoghq.com",
    "eu-central-1-1.aws.cloud2.influxdata.com",
    "oauth2.googleapis.com",
    "cloudcode-pa.googleapis.com",
    "github.com",
    "api.github.com",
    "index.crates.io",
    "static.crates.io",
    "mcp.linear.app"
  ]
}
```

Note: These are the same domains already in `settings.local.json`. The `"*"` wildcard
is kept since the user reports it doesn't fully work anyway (still prompts for some sites).
The explicit domains ensure those critical services are always allowed even if wildcard
behavior is buggy. This matches the existing `settings.local.json` pattern.
```

#### Syntax migration
- All `Bash(cmd:*)` → `Bash(cmd *)` throughout (allow, deny, ask)
- **Exception:** `Bash(git commit:*)` keeps colon (heredoc)
- Test 5 rules first in one session before bulk migration

---

## Part B: Register alignment-hive marketplace

**File:** `claude/templates/contexts/profiles.yaml`

### Step 1: Add marketplace
```yaml
marketplaces:
  alignment-hive:
    source: "Crazytieguy/alignment-hive"
```

### Step 2: Add plugins to profiles
```yaml
research:
  enable:
    - remote-kernels

base:
  - llms-fetch-mcp
```

### Step 3: Override llms-fetch-mcp to use bunx
Check `.mcp.json` in plugin cache after install. If it uses `npx`, override to `bunx`.

### Step 4: Sync
```bash
claude-context --sync && claude-context
```

---

## Part C: Install coven

### Add to install.sh
Add `coven` to the `--ai-tools` brew section (tap: `Crazytieguy/tap/coven`).

### Usage guidance
- `coven "prompt"` — lightweight interactive (better than `claude -p`)
- `coven ralph "task"` — autonomous iteration loops
- `coven --show-thinking "prompt"` — debug model reasoning
- Keep Claude Code TUI for full features; coven complements, doesn't replace

---

## Files to modify

| File | Changes |
|------|---------|
| `claude/settings.json` | Permission hardening (deny/ask/allow rules), network domain allowlist, syntax migration |
| `claude/templates/contexts/profiles.yaml` | Add alignment-hive marketplace + remote-kernels + llms-fetch-mcp |
| `install.sh` | Add `coven` to `--ai-tools` brew installations |

## Verification

1. **Deny rules work:** `bash -c 'echo test'` → blocked. `eval echo hi` → blocked.
2. **Ask rules work:** `for i in 1; do echo hi; done` → prompts. `env FOO=bar ls` → prompts. `curl example.com` → prompts.
3. **Allow rules work:** `time ls` → auto-approved. `bun run test` → auto-approved. `python script.py` → auto-approved.
4. **Network:** `curl google.com` → blocked by sandbox (not in allowlist). `curl api.github.com` → allowed by sandbox (in allowlist).
5. **Marketplace:** `claude-context --sync -v` succeeds. `claude-context --list` shows alignment-hive.
6. **Coven:** `coven --version` works. `coven "hello"` starts a session.

## In this change: PreToolUse hook for for/while bypass protection

Create a hookify rule (or direct PreToolUse hook) that:
1. Matches `Bash` tool calls where command starts with `for ` or `while `
2. Extracts the loop body (between `do` and `done`)
3. Checks inner commands against the deny list patterns
4. Blocks if inner commands match denied patterns (bash -c, eval, rm -rf, etc.)

Implementation: Use hookify prompt-based hook or a shell script hook.

## Follow-up tasks (not in this change)

- Additional PreToolUse hooks for compound patterns (pipes to shell, command substitution)
- Evaluate `allowUnsandboxedCommands: false` after living with new deny/ask rules
- Consider denying `Read` for `~/.ssh/**`, `~/.aws/**` and other credential paths
- Docker-based sandboxing as long-term option for untrusted projects
