---
name: focus-modes
description: Switch, inspect or change Yulong's Cold Turkey and ScreenZen blocking modes (research, writing, admin) through `focus` and its vault note. Use on "switch to writing mode", "start research mode", "turn blocking off", "allow / unblock X", "block X", "why is X blocked", "add X to a mode", or any question about Cold Turkey, ScreenZen, focus modes or blocklists.
---

# Focus modes

Two blockers read one list. **Cold Turkey** blocks hard, one mode at a time: each mode is a block `mode: <name>` that blocks every site except its allowlist and blocks the apps of its app groups. **ScreenZen** gives friction and follows the mode: its "✅ always" group allows the shared list plus the running mode's sites (only the shared list when no mode runs), so everything else gets a pause screen; each switch or `focus off` rewrites it, closing and reopening ScreenZen. Its 🚫 groups block apps and sites always.

## Where things live

- **The list:** `~/vault/tooling/dotfiles/config/cold-turkey.md`, one fenced YAML block. Every site and app is defined once in `groups`; `always_allow`, `modes.<name>.allow|block` and `blocklists.screenzen|cold_turkey` only name groups. Yulong edits it in Obsidian too, so re-read it before every edit and keep his changes where he put them.
- **The tool:** `focus` (`custom_bins/focus`); `focus --help` and its docstring are the reference.
- **Backups:** `~/scratch/blocker-backups/` (the first full snapshot and its restore README are in `2026-10-29-before-ct-mode/`).

## Commands

Run `focus` with `dangerouslyDisableSandbox: true`: Cold Turkey's CLI talks to the running app over local IPC, and the ScreenZen write closes and reopens ScreenZen and writes under `~/Library`.

| Ask | Run |
|---|---|
| "switch to / start writing" | `focus writing` |
| "turn blocking off" | `focus off` |
| "deep focus for 90 minutes", "block AI chat for a bit" | `focus deep 90`: the `timer: deep` block, locked until it ends, on top of any mode. Starting it only tightens, so it runs at once; nobody can end it early |
| "what's running", "is it in sync" | `focus status` |
| "add X to travel / admin" | `focus add travel x.com` (edits the note, then runs sync and screenzen); `--app` for an app |
| "I added something inside Cold Turkey" | `focus pull --dry-run`, then `focus pull`: copies sites and apps Cold Turkey has but the note lacks into `from-<block>` groups that the owning mode, timer or blocklist names. Additions only; ScreenZen edits are not pulled and the next `focus screenzen` overwrites them |
| after editing the note by hand | `focus status`, then `focus sync` (applies the note to Cold Turkey and to ScreenZen for the running mode) |
| new mode blocks needed | `focus export`, then Yulong imports `~/Downloads/focus-blocks.ctbbl` (Blocks → menu → Import blocks from another installation…) |

## Loosening waits; do not work around it

When Claude runs it, `focus` delays anything that loosens blocking: stopping a mode, switching modes, a sync that allows new sites, a ScreenZen write that allows more or blocks less. **Exit code 3 means queued, not failed.** Tell Yulong the change and the time it becomes runnable, and stop. Run the same command once more after that time only if he still wants it. Never edit `~/.local/state/focus/pending.json`, `focus` or `agent_loosen_delay_minutes` to skip the wait, and never loop on the command. If he wants it now, give him the command to run himself. Starting a mode from none and anything that only tightens run at once.

## Changing the lists

- **"Allow X in research":** put X in the group that fits it (or a new group the mode names), never straight into a mode. Say which other modes get it through that group.
- **"Block X":** add it to an always-blocked group, or remove it from the allow group that lets it through.
- **"Why is X blocked":** check, in order, whether the running mode allows a group containing X, whether a Cold Turkey always-on block bans X (`focus status` prints `conflict:` lines; an exception never overrides another block), and whether a ScreenZen 🚫 group lists it.
- **What stays manual in Cold Turkey:** removing a site, changing a mode's apps, and loosening an always-on block (the Cold Turkey blocks under `blocklists.cold_turkey` in the note). `focus sync` tries to add newly banned sites to the always-on blocks through the CLI, which only tightens; whether the CLI accepts additions to a locked block is untested, and sync says when one did not land. `focus status` names every remaining difference; give Yulong that as the step to do by hand.
- **Why not write Cold Turkey's database directly:** it is possible (the settings are lightly obfuscated JSON), but it is exactly the path around the delay locks, and the running app can overwrite or corrupt it. Do not build or suggest it.
- **ScreenZen's 🚫 groups win inside ScreenZen.** A site a mode allows but a ScreenZen 🚫 group blocks is left out of "✅ always", so it keeps its pause screen all day.
- **Time windows come from the apps' own schedules, not from a mode.** Some always-on blocks are scheduled off at set hours; the note says which. A running mode still blocks everything it does not allow, so a window needs `focus off`. Schedules are edited in the apps, not the note.
- **Pattern syntax** is Cold Turkey's (`*` for any text, a path is its own entry). ScreenZen matches by substring, so `focus` cuts allow patterns at the first `*` and strips `*` from block patterns.
