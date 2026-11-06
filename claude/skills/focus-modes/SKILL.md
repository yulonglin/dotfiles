---
name: focus-modes
description: Switch, inspect or change Yulong's Cold Turkey and ScreenZen blocking modes (research, writing, admin) through `focus` and its vault note. Use on "switch to writing mode", "start research mode", "turn blocking off", "allow / unblock X", "block X", "why is X blocked", "add X to a mode", or any question about Cold Turkey, ScreenZen, focus modes or blocklists.
---

# Focus modes

Two blockers read one list. **Cold Turkey** blocks hard, one mode at a time: each mode is a block `mode: <name>` that blocks every site except its allowlist and blocks the apps of its app groups. **ScreenZen** gives friction and follows the mode: focus owns one allow group per mode ("✅ focus: research" and so on, plus "✅ focus: shared" for no mode), each holding the shared list plus that mode's sites. "✅ focus: shared" holds every mode's sites, so no mode is the widest state in both apps and every mode only tightens it. Exactly one is on, so everything else gets a pause screen; each switch or `focus off` turns the right one on, closing and reopening ScreenZen. Its 🚫 groups block apps and sites always.

## Where things live

- **The list:** `~/vault/tooling/dotfiles/config/cold-turkey.md`, one fenced YAML block. Every site and app is defined once in `groups`; `always_allow`, `modes.<name>.allow|block` and `blocklists.screenzen|cold_turkey` only name groups. Yulong edits it in Obsidian too, so re-read it before every edit and keep his changes where he put them.
- **The tool:** `focus` (`custom_bins/focus`); `focus --help` and its docstring are the reference.
- **Backups:** `~/scratch/blocker-backups/` (the first full snapshot and its restore README are in `2026-10-29-before-ct-mode/`).

## Commands

Run `focus` with `dangerouslyDisableSandbox: true`: Cold Turkey's CLI talks to the running app over local IPC, and the ScreenZen write closes and reopens ScreenZen and writes under `~/Library`.

| Ask | Run |
|---|---|
| "switch to / start writing" | `focus writing` |
| "take a break", "pause for 15 minutes" | `focus break 15`: stops the mode, which starts again by itself after the break (at most `break_max_minutes`). `focus install-agent` adds a once-a-minute launchd job so a break ends even after a restart |
| "turn blocking off" | `focus off`, which works only in the note's `off_hours`; at any other time offer a break or another mode instead. Never route around this |
| "deep focus for 90 minutes", "block AI chat for a bit" | `focus deep 90`: the `timer: deep` block, locked until it ends, on top of any mode. Starting it only tightens, so it runs at once; nobody can end it early |
| "only Bear and ChatGPT for 45 minutes", "let me pick what's allowed", "something like Micromanager" | `focus only` opens the search (a terminal and fzf, so Yulong runs it himself); `focus only bear chatgpt 45` names the picks, as a group, a word in one group, or an installed app. See "Only sessions" below |
| "what's running", "is it in sync" | `focus status` |
| "add X to travel / admin" | `focus add travel x.com` (edits the note, then runs sync and screenzen); `--app` for an app |
| "I added something inside Cold Turkey" | `focus pull --dry-run`, then `focus pull`: copies sites and apps Cold Turkey has but the note lacks into `from-<block>` groups that the owning mode, timer or blocklist names. Additions only; ScreenZen edits are not pulled and the next `focus screenzen` overwrites them |
| after editing the note by hand | `focus status`, then `focus sync` (applies the note to Cold Turkey and to ScreenZen for the running mode) |
| new mode blocks needed | `focus export`, then Yulong imports `~/Downloads/focus-blocks.ctbbl` (Blocks → menu → Import blocks from another installation…) |

## Only sessions are friction, not a block

`focus only` is like Cold Turkey Micromanager, but it can be passed, because Micromanager felt too strict for a forgotten tool (Yulong, 2026-11-05). It uses ScreenZen alone: "✅ focus: only" holds the note's `only.keep` groups plus the picks, and "🚫 focus: only" holds every installed app except those, less menu-bar agents, copied from an all-day 🚫 group so it has that group's pause. A session stops the running mode and uses no Cold Turkey block, so only the always-on blocks stay hard. Unpicked `always_allow` groups get a pause too; that is what makes picking AI chat mean something.

- **While it runs:** `focus only` adds to it, `focus only 20` sets the end to 20 minutes from now, `focus only end` ends it. Any `focus <mode>` also ends it.
- **At the end:** a notification, then the mode it replaced starts again. `focus break` and `focus off` refuse during a session and name `focus only end`.
- **The cost, accepted by Yulong:** a session has no time cap, so it is a pause-only state that `off_hours` and `break_max_minutes` do not limit.
- **Keep list:** add to the `only-tools` group an app that must never pause, such as the terminal that runs `focus`.

## Loosening waits; do not work around it

When Claude runs it, `focus` delays anything that loosens blocking: stopping a mode, switching modes, a sync that allows new sites, a ScreenZen write that allows more or blocks less. **Exit code 3 means queued, not failed.** Tell Yulong the change and the time it becomes runnable, and stop. Run the same command once more after that time only if he still wants it. Never edit `~/.local/state/focus/pending.json`, `focus` or `agent_loosen_delay_minutes` to skip the wait, and never loop on the command. If he wants it now, give him the command to run himself. Starting a mode from none and anything that only tightens run at once.

## Changing the lists

- **"Allow X in research":** put X in the group that fits it (or a new group the mode names), never straight into a mode. Say which other modes get it through that group.
- **"Block X":** add it to an always-blocked group, or remove it from the allow group that lets it through.
- **"Why is X blocked":** check, in order, whether the running mode allows a group containing X, whether a Cold Turkey always-on block bans X (`focus status` prints `conflict:` lines; an exception never overrides another block), and whether a ScreenZen 🚫 group lists it.
- **What stays manual in Cold Turkey:** removing a site, changing a mode's apps, and loosening an always-on block (the Cold Turkey blocks under `blocklists.cold_turkey` in the note). `focus sync` tries to add newly banned sites to the always-on blocks and timers through the CLI, which only tightens; whether the CLI accepts additions to a locked block is untested, and sync says when one did not land. `focus status` says "focus sync adds these" for a difference sync can make; for the rest, give Yulong that line as the step to do by hand. Sync sends additions one at a time, because every block lives in one settings value that each add rewrites, then waits once, up to 3 s, for all of them. The CLI's "isn't responding" does not say whether a change landed, so only the database counts.
- **Why not write Cold Turkey's database directly:** it is possible (the settings are lightly obfuscated JSON), but it is exactly the path around the delay locks, and the running app can overwrite or corrupt it. Do not build or suggest it.
- **ScreenZen's 🚫 groups win inside ScreenZen.** A site a mode allows but a ScreenZen 🚫 group blocks is left out of every "✅ focus:" group, so it keeps its pause screen all day. A 🚫 group with `off_in: [admin]` in the note stands aside while those modes run (messaging apps during admin) and is back on otherwise.
- **Time windows come from the apps' own schedules, not from a mode.** Some always-on blocks are scheduled off at set hours; the note says which. A running mode still blocks everything it does not allow, so a window needs `focus off`. Schedules are edited in the apps, not the note.
- **Pattern syntax** is Cold Turkey's (`*` for any text, a path is its own entry). ScreenZen matches by substring, so `focus` cuts allow patterns at the first `*` and strips `*` from block patterns.
