# Claude Code Re-Prompts For Folders On Every Update

macOS asks again for Documents, Downloads, Desktop and "data from other apps" after nearly every Claude Code release. No other app does this, because macOS keys an app's grants by its bundle ID, and ordinary CLI tools run under the terminal's identity.

## Why it happens

- The native installer puts each release at its own path, `~/.local/share/claude/versions/<ver>`, and points `~/.local/bin/claude` at it.
- Some Claude Code process runs as its own TCC-responsible process, not under the terminal. The likely one is the background daemon after an upgrade: it logs `self-restarting for upgrade`, then `respawned N/N stale workers`. On 2026-10-01 the respawn was at 20:11:00 UTC and the 2.1.287 prompt row at 20:11:04. This rests on timing only, and the exact process was not pinned down (the workers running at check time were attributed to Ghostty).
- For a bare binary, TCC records the grant against that path (`client_type = 1`), so every release is a new client. On this Mac the user TCC.db held rows for 33 distinct version paths between 2026-06-28 and 2026-10-01.
- Claude Code already ships a fix attempt: `~/.local/share/claude/ClaudeCode.app` (bundle ID `com.anthropic.claude-code`, hard-linked to the current version), which the pty host re-execs through with responsibility disclaimed. The per-version rows show that the upgrade-respawn path still lands on the versioned path. The real fix is upstream.

## The workaround: repeat your last answer on each new version

`tools/tcc-carry-claude/main.swift` handles every Anthropic-signed binary in the versions directory. For each service and target that binary has no row for, it copies the most recent answer you gave any other version. That covers allows and denials, and Documents, Downloads, other apps' data, Media Library, Apple Events targets and File Provider domains alike. An answer counts when its `auth_reason` is 2 (prompt) or 3 (System Settings). Desktop is always denied, whatever was answered before.

It never changes an existing row, so an answer you give by hand wins, and a wrong click is fixed by toggling it in System Settings. It skips any file that fails the requirement `identifier "com.anthropic.claude-code"` signed by team `Q6L2SF6YDW`. As `csreq` it writes that binary's own designated requirement, byte-identical to what tccd stores. Full Disk Access lives in the SIP-protected system TCC.db, which this does not touch, so that prompt still appears per version.

Install with `scripts/setup/setup_tcc_carry_claude.sh`. It builds the helper to `~/.local/libexec/tcc-carry-claude/` (outside `~/code`, so a sandboxed agent cannot swap the binary holding the grant) and loads `com.user.tcc-carry-claude`. The agent runs on changes to the versions directory and every five minutes. The helper needs Full Disk Access, granted by hand. Every rebuild changes its code hash, so the grant must be re-added. Logs go to `~/.local/state/tcc-carry-claude/agent.log`. `--dry-run` previews; `--uninstall` unloads the agent.

`tools/tcc-carry-claude/probe.py` runs a command as its own responsible process, which reproduces how the daemon's workers are attributed. Use it to check that tccd honours an inserted row.
