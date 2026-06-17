# Machine Registry: Persistent Machine Names with Auto-Registration

## Context

Currently, `machine-name` identifies servers dynamically by matching public IP against `~/.ssh/config` entries. This works but has gaps:
- Only activates in SSH sessions (`$SSH_CONNECTION` check)
- Fails when SSH config IP doesn't match (jump hosts, dynamic IPs)
- No support for local machines
- No persistent list of "known" machines
- No auto-registration for new/unknown servers

**Goal:** A persistent machine registry that names machines once and remembers them, with an interactive prompt for unknown machines.

## Design

### Registry File: `config/machines.conf`

Simple line-based format (committed to dotfiles, syncs via git):

```
# machine-id|name|emoji (emoji optional, auto-assigned if empty)
4a4957ecd56f40d8b7fbe3d71bd7e6ef|dev-server|🖥️
a1b2c3d4e5f6...|macbook-pro|💻
```

- **Machine ID**: `/etc/machine-id` (Linux) or `ioreg` IOPlatformUUID (macOS)
- Committed to dotfiles → syncs to all machines via git
- Comments and blank lines allowed

### Resolution Priority (updated `machine-name`)

1. `$SERVER_NAME` env var (explicit override, unchanged)
2. **Registry lookup** by machine-id (NEW)
3. SSH config alias matching public IP (existing, kept as fallback)
4. Abbreviated hostname (existing fallback)

### Auto-Registration Flow

On zsh startup (`zshrc.sh`), if machine-id is NOT in registry:

```
🆕 Unregistered machine detected (hostname: 4a1e96303f2b)
   Enter a name for this machine (or press Enter to skip): █
```

- Interactive prompt, non-blocking (skip = use fallback name for this session)
- On name entry: appends to `config/machines.conf`, auto-assigns emoji
- Sets a `~/.cache/machine-registered` flag so it only prompts ONCE (even if skipped)
- Skipped machines can be registered later with `machine-register` command

### New Command: `custom_bins/machine-register`

```bash
machine-register              # Interactive: prompt for name
machine-register my-server    # Non-interactive: register with given name
machine-register --list       # Show all registered machines
machine-register --remove     # Remove current machine from registry
```

## Files to Modify

| File | Change |
|------|--------|
| `config/machines.conf` | **NEW** — registry file, seed with current machine |
| `custom_bins/machine-name` | Add registry lookup (step 2 in priority), remove SSH-only gate for registry matches |
| `custom_bins/machine-register` | **NEW** — registration CLI |
| `config/zshrc.sh` | Add auto-registration prompt on startup |
| `claude/statusline.sh` | Remove SSH-only gate (registry handles local machines too) |
| `tools/claude-tools/src/statusline.rs` | Remove SSH-only gate |
| `config/p10k.zsh` | Update `prompt_remote_host` to work for registered local machines too |

## Key Decisions

1. **`machine-name` works for ALL registered machines** (not just SSH). If your local machine is in the registry, it shows in prompt/statusline. Unregistered local machines still show nothing (backwards-compatible).
2. **SSH config remains as fallback** — no need to duplicate SSH aliases in registry if IP matching works.
3. **Auto-prompt only once** — uses `~/.cache/machine-registered` flag. Won't nag on every shell.
4. **Registry in dotfiles** — committed, syncs via git push/pull. All your machines see the full list.

## Verification

1. Run `machine-register` on current machine, verify entry in `config/machines.conf`
2. Run `machine-name` — should return registered name + emoji
3. Source `zshrc.sh` on an unregistered machine — should see prompt
4. Check p10k prompt shows machine name
5. Check Claude Code statusline shows machine name
