# Terminal, Shell & Dev Tools Reference

Operational detail for the terminal/shell/dev-tool components, moved out of the README. Deploy mechanics live in [`deploy-components.md`](./deploy-components.md); this file holds the usage detail documented nowhere else.

## Ghostty Theme Aliases

Default Ghostty config uses Catppuccin Mocha. The `g0`–`g9` aliases launch a **single fresh window** (no tab restoration) with a different theme — useful for visually distinguishing contexts:

| Alias | Theme                          | Character                        |
| ----- | ------------------------------ | -------------------------------- |
| `g0`  | TokyoNight                     | Deep blue bg — neon city         |
| `g1`  | Dracula                        | Purple-grey bg — vibrant classic |
| `g2`  | Nord                           | Arctic blue-grey bg — calm       |
| `g3`  | Rose Pine                      | Deep purple bg — botanical       |
| `g4`  | Kanagawa Dragon                | Warm near-black bg — Japanese ink |
| `g5`  | Gruvbox Dark                   | Neutral warm bg — retro          |
| `g6`  | Everforest Dark Hard           | Green-grey bg — forest           |
| `g7`  | Solarized Dark Higher Contrast | Dark teal bg — high contrast     |
| `g8`  | Melange Dark                   | Warm brown bg — earthy           |
| `g9`  | Material Ocean                 | Near-black bg — minimal          |

```bash
g1                        # Launch Ghostty with Dracula theme
gtheme "Tomorrow Night"   # Launch with any theme by name
ghostty +list-themes      # See all available themes
```

## SSH Color Switching

Terminal colors automatically change when SSH-ing to help identify which machine you're on; colors revert when the session ends.

```bash
ssh myserver     # In Ghostty: colors change automatically
sshc myserver    # Explicit color-changing SSH (works in any terminal)
```

Configure per-host colors by editing `SSH_HOST_COLORS` in `config/ssh_themes.sh`:

```bash
# Format: "background:foreground:cursor" in hex
SSH_HOST_COLORS[prod*]="#3d0000:#ffffff:#ff6666"      # Red-tinted for production
SSH_HOST_COLORS[dev*]="#002200:#ffffff:#66ff66"       # Green-tinted for dev
SSH_HOST_COLORS[gpu*]="#1a0033:#ffffff:#cc66ff"       # Purple for GPU servers
SSH_HOST_COLORS[default]="#0d1926:#c5d4dd:#88c0d0"    # Blue-gray fallback
```

Patterns support wildcards (`prod*` matches `prod1`, `prod-web`, etc.); the `default` key applies to any host without a specific match.

## Powerlevel10k Prompt

[Powerlevel10k](https://github.com/romkatv/powerlevel10k) provides a fast ZSH prompt with custom segments for SSH-aware machine identification.

**Requirements**: a [Nerd Font](https://github.com/romkatv/powerlevel10k#meslo-nerd-font-patched-for-powerlevel10k) for icons.

**Reconfigure**: run `p10k configure` (when prompted, overwrite `p10k.zsh` but don't apply to `.zshrc`).

| Segment         | Description                                              |
| --------------- | -------------------------------------------------------- |
| **Remote host** | Machine name + emoji (SSH sessions only)                 |
| **Directory**   | Current path with git root highlighting                  |
| **Git status**  | Branch, dirty indicator, stash count                     |
| **Right side**  | Exit code, command duration, Python venv, cloud contexts |

### SSH-Aware Machine Identification

When SSH'd to a remote machine, the prompt shows a consistent machine name derived from your SSH config — `🌊 mats ~/code/project (main)` instead of `user@ip-172-31-42-17` — with a unique emoji hashed from the name.

How it works: (1) looks up your public IP against `~/.ssh/config` `HostName` entries; (2) uses the matching `Host` alias as the display name; (3) falls back to abbreviated hostname if no match; (4) hashes the name to assign a stable emoji from a curated palette.

Customization: `SERVER_NAME` env var overrides everything; `MACHINE_EMOJI` overrides the auto-assigned emoji.

## Claude Code Statusline

Configured in `claude/settings.json` (`statusLine.command = "claude-tools statusline"`).

```
🌊 mats [code python] ~/code/project (main*) · 📊 45% · $0.23 · 12m
│        │             │              │      │        │        └─ Session duration
│        │             │              │      │        └─ Session cost
│        │             │              │      └─ Context usage (color-coded)
│        │             │              └─ Branch (* = dirty)
│        │             └─ Active Claude context profiles
│        └─ Directory
└─ Machine name (SSH only, same as p10k)
```

Context % is color-coded: green <70%, yellow 70–89%, red 90%+. Machine name uses the same `machine-name` script as Powerlevel10k, so identification is consistent across tools.

`ccusage statusline` is deliberately not wired into the live Claude hook path because it can OOM on large local histories; guard logic still uses lightweight `ccusage blocks --active --json` where available.

## Ignore Pattern Management

`claude-tools ignore` manages per-repo `.gitignore` and `.ignore` patterns interactively.

```bash
claude-tools ignore                    # Launch TUI (same as `ignore apply`)
claude-tools ignore apply              # Interactive pattern selection
claude-tools ignore apply --dry-run    # Preview without writing
claude-tools ignore apply --non-interactive  # Apply defaults without TUI
claude-tools ignore status             # Show current managed patterns
```

The TUI shows patterns grouped by category with tri-state toggles:

- `[   ]` skip — pattern not applied
- `[ G ]` gitignore — added to `.gitignore` only
- `[G+S]` gitignore + searchable — added to `.gitignore` AND negated in `.ignore`

Patterns in `[G+S]` state are git-ignored but remain searchable by rg, fd, Claude Code, and Cursor. Pattern definitions live in `config/ignore/patterns`.

## SSH Key Management

The ZSH config automatically adds your SSH key to ssh-agent on shell startup (interactive shells only):

- Checks for `~/.ssh/id_ed25519` (customizable via `SSH_KEY_PATH`, e.g. `export SSH_KEY_PATH=~/.ssh/id_rsa`)
- **Prompts to generate** if the key doesn't exist (never overwrites existing keys)
- Adds to macOS Keychain (`--apple-use-keychain`) or Linux ssh-agent; skips if already loaded

First-time flow: shell starts → detects no key → prompts "Generate a new ed25519 SSH key now? [y/N]" → if yes, generates and shows the command to copy the public key. Configuration: `config/ssh_setup.sh`.

## htop

`./deploy.sh --htop` deploys `config/htop/htoprc`, whose dynamic layout adapts CPU meters to the machine's core count — no manual adjustment across machines.

## pdb++ (Python Debugger)

`./deploy.sh --pdb` deploys a high-contrast color scheme for [pdb++](https://github.com/pdbpp/pdbpp) to `~/.pdbrc.py` (symlinked).

**Global config works with per-project installations**: pdb++ is installed per-project via `uv add --dev pdbpp` but reads the global config at runtime.

**Auto-detects terminal background** via the OSC 11 escape sequence: light terminals get solarized-light, dark get monokai, and detection failures (SSH, older terminals) fall back to the dark theme. Detection succeeds in iTerm2, Ghostty, Kitty, Alacritty.

Test: `uv add --dev pdbpp && python -c "import pdb; pdb.set_trace()" <<< "c"` should show high-contrast colors. Per-project override: a `.pdbrc.py` in the project root takes precedence.

## macOS Media Recovery

If Spotify, FaceTime, FineTune, or other audio apps hang together, use the manual `reset-mac-media` helper. It saves a private diagnostic bundle before restarting only CoreAudio and FaceTime's supporting services; it does not quit the affected GUI apps or restart Bluetooth or WindowServer.

```bash
reset-mac-media --dry-run   # Preview the bounded action
reset-mac-media             # Capture diagnostics, restart media services, verify recovery
```

The real run requires administrator authentication and briefly interrupts all audio, video, and active calls. Reports go to `~/Library/Logs/reset-mac-media/`; a bundle can contain device metadata, local paths, and call or app context, so review it before sharing. If the helper cannot verify that the old service PIDs disappeared while their launchd jobs remain loaded, it exits nonzero and keeps the report; rebooting remains the fallback. To reduce recurrence, add FaceTime to FineTune's ignore list and use the MacBook microphone when Bluetooth call routing is unstable.

## Automation Extras

Detail missing from the per-component docs:

- **Claude Code session cleanup**: manual control via `clear-claude-code` (aliases `ccl`, `cci`, `ccf`); status with `clear-claude-code --list`; uninstall with `scripts/cleanup/setup_claude_cleanup.sh --uninstall`.
- **Gist sync**: uninstall with `scripts/cleanup/setup_gist_sync.sh --uninstall`. **Secret gists are unlisted, not encrypted** — only non-secret config (SSH config, authorized_keys, git identity) should be synced via gist.

## Codex Layout

`codex/` (symlinked to `~/.codex` by `./deploy.sh --codex`): `AGENTS.md` (global instructions, references CLAUDE.md as source of truth), `config.toml` (model settings, status line, per-project trust levels), `rules/` (synced from Claude Code's `rules/`), and `skills/` → symlink to `claude/skills/` so both CLIs share one skill set. Sync mechanics: [`cross-tool-extensibility.md`](./cross-tool-extensibility.md).

## Shell Utility Functions & Aliases

- **`config/modern_tools.sh`**: `mkd` (mkdir+cd), `cdf` (cd to Finder window, macOS), `targz` (smart compression), `dataurl`, `digga` (DNS lookup), `getcertnames` (SSL certs), `o` (cross-platform open), `server` (quick HTTP server)
- **`config/aliases/net.sh`**: `flush` (DNS cache), `afk` (lock screen, macOS), `week` (ISO week number)
- Aliases are themed per file under `config/aliases/` (git.sh, nav.sh, net.sh, …); add your own to the matching file.
