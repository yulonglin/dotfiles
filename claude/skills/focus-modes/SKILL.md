---
name: focus-modes
description: Switch, inspect or change Yulong's Cold Turkey and ScreenZen blocking modes (research, writing, admin) through `focus` and its vault note. Use on "switch to writing mode", "start research mode", "turn blocking off", "allow / unblock X", "block X", "why is X blocked", "add X to a mode", or any question about Cold Turkey, ScreenZen, focus modes or blocklists.
---

# Focus modes

Two blockers read one list. **Cold Turkey** blocks hard, one mode at a time: each mode is a block `mode: <name>` that blocks every site except its allowlist and blocks the apps of its app groups. **ScreenZen** gives friction and follows the mode: focus owns one allow group per mode ("✅ focus: research" and so on, plus "✅ focus: shared" for no mode), each holding the shared list plus that mode's sites. "✅ focus: shared" holds every mode's sites, so no mode is the widest state in both apps and every mode only tightens it. Exactly one is on, so everything else gets a pause screen; each switch or `focus off` turns the right one on, closing and reopening ScreenZen. Its 🚫 groups block apps and sites always, except during an only session, when they stand aside for that session's own 🚫 group.

**A mode with `kind: blocklist` is the reverse** (admin, since 22 Nov 2026: errands reach too many sites to list). Its Cold Turkey block bans only the sites of its `block` groups, and ScreenZen switches every ✅ group off while it runs, as in an open window, so only the 🚫 groups pause. Its `allow` list stays: it feeds "✅ focus: shared", so no mode pauses nothing new, and it stays in its Cold Turkey exceptions beside `always_allow` (Yulong, 2026-11-26). The one exception: an allowed site whose host equals, sits under or contains a banned host (`touches_ban`) is left out of them, because an exception overrides its own block and would undo that ban. A path exception on a parent domain (`google.com/travel*` beside a banned `news.google.com`) is kept. Starting one loosens even from no mode, so an agent waits, and a break from it is tighter than the mode itself. A block that still lists `*.*` shows in `focus status` as a hand removal; sync never adds `*.*` back.

## Where things live

- **The list:** `~/vault/tooling/dotfiles/config/cold-turkey.md`, one fenced YAML block. Every site and app is defined once in `groups`; `always_allow`, `modes.<name>.allow|block` and `blocklists.screenzen|cold_turkey` only name groups. Yulong edits it in Obsidian too, so re-read it before every edit and keep his changes where he put them.
- **The tool:** `focus` (`custom_bins/focus`); `focus --help` and its docstring are the reference.
- **Backups:** `~/scratch/blocker-backups/` (the first full snapshot and its restore README are in `2026-10-29-before-ct-mode/`).

## Commands

Run `focus` with `dangerouslyDisableSandbox: true`: Cold Turkey's CLI writes the app's preferences and reads its database, and the ScreenZen write closes and reopens ScreenZen and writes under `~/Library`.

| Ask | Run |
|---|---|
| "switch to / start writing" | `focus writing` |
| "start research by itself in the morning", "what runs by default" | the note's `default_mode`: the launchd job starts it once a day between its `start` and `until` (09:00–12:00 on weekdays unless set) when nothing runs; a mode stopped by hand stays stopped that day |
| "admin in the evening", "what starts at 21:30" | the note's `scheduled_mode` (a capped mode): the launchd job starts it once a day in its span (every day unless `days` is set) as a stretch that ends at `until` in no mode, so the 22:00 social window opens by itself. No reason, no daily start used; a committed block or only session skips it that day |
| "take a break", "pause for 15 minutes" | `focus break 15`: stops the mode, which starts again by itself after the break (at most `break_max_minutes`). One break per `break_every_minutes` (default 60), counted from the last break's start. `focus break 10 --emergency` skips that wait, and only that, after Yulong types back a random text of `emergency_text_chars` characters (default 100; commitments use `commit_text_chars`, default 150) and a reason logged with `emergency: true`; it needs a terminal, so agents and Alfred cannot use it. `focus install-agent` adds a once-a-minute launchd job so a break ends even after a restart |
| "open windows", "why did research stop at 12:30" | the note's `windows` (`["12:30-13:00", ...]`): the launchd job's first tick in each window stops the unlocked modes as a break that ends with the window, and ScreenZen switches every focus group off, so only Cold Turkey's always-on blocks hold. A committed block or only session keeps that window closed; a mode started by hand in a window runs as usual. `focus off` works in a window (Yulong, 2026-11-20) |
| "turn blocking off" | `focus off`, which works only in the note's `off_hours`; at any other time offer a break or another mode instead. Never route around this |
| "deep focus for 90 minutes", "block AI chat for a bit" | `focus deep 90`: the `timer: deep` block, locked until it ends, on top of any mode. Starting it only tightens, so it runs at once; nobody can end it early |
| "only Bear and ChatGPT for 45 minutes", "let me pick what's allowed", "something like Micromanager" | `focus only` opens the search (a terminal and fzf, so Yulong runs it himself: SPACE or TAB ticks several, the header lists the picks, ENTER starts); in Alfred, `focus only` ticks one row per ENTER and the top row starts them all; `focus only bear chatgpt 45` names the picks, as a group, a word in one group, or an installed app. See "Only sessions" below |
| "a stretch of a capped mode", "another half hour of it" | `focus <capped mode> [MINUTES]`: at most the mode's `minutes`, then back to the mode before it. A later start the same day asks Yulong for a reason, at the terminal or in a macOS dialog when there is none (Alfred), so an agent can make only the first. See "Capped modes" below |
| "a long day in a capped mode" | `focus <capped mode> --day [MINUTES]`: one stretch from the daily budget, with a reason; Yulong runs it himself |
| "lock me into research for two hours", "commit to writing" | `focus research 120 --commit`: starts the mode and keeps its block locked until the end. Refuses unless the launchd job from `focus install-agent` is loaded for this focus and note. See "Committed blocks" below |
| "allow X" or "end it" during a committed block | `focus allow X` or `focus end`: a typed text and a reason at the terminal, so Yulong runs these himself; the change lands when Cold Turkey's lock runs out |
| "what's running", "is it in sync", "is X locked strongly enough" | `focus status` |
| "show me the modes", "let me pick a mode" | bare `focus` at a terminal opens a menu (`claude-tools select`) of the modes, timers, `only`, `break`, `off` and `status`, asks minutes where the command takes them, then runs the pick as if typed; off a terminal (an agent, a pipe) it prints the list instead, as `focus list` always does |
| "add X to travel / admin" | `focus add travel x.com` (edits the note, then runs sync and screenzen); `--app` for an app |
| "I added something inside Cold Turkey" | `focus pull --dry-run`, then `focus pull`: copies sites and apps Cold Turkey has but the note lacks into `from-<block>` groups that the owning mode, timer or blocklist names. Additions only; ScreenZen edits are not pulled, and the next launchd tick overwrites them within a minute |
| after editing the note by hand | `focus status`, then `focus sync` (applies the note to Cold Turkey and to ScreenZen for the running mode) |
| new mode blocks needed | `focus export`, then Yulong imports `~/Downloads/focus-blocks.ctbbl` (Blocks → menu → Import blocks from another installation…) |

## Only sessions are friction, not a block

`focus only` is like Cold Turkey Micromanager, but it can be passed, because Micromanager felt too strict for a forgotten tool (Yulong, 2026-11-05). It uses ScreenZen alone: "✅ focus: only" holds the note's `only.keep` groups plus the picks, and "🚫 focus: only" holds every installed app except those, less menu-bar agents, copied from an all-day 🚫 group so it has that group's pause. A session stops the running mode and uses no Cold Turkey block, so only the always-on blocks stay hard. Unpicked `always_allow` groups get a pause too; that is what makes picking AI chat mean something.

- **While it runs:** `focus only` adds to it, `focus only 20` sets the end to 20 minutes from now, `focus only end` ends it. Any `focus <mode>` also ends it.
- **At the end:** a notification, then the mode it replaced starts again. `focus break` and `focus off` refuse during a session and name `focus only end`.
- **The cost, accepted by Yulong:** a session has no time cap, so it is a pause-only state that `off_hours` and `break_max_minutes` do not limit.
- **Keep list:** add to the `only-tools` group an app that must never pause, such as a browser or a blocker.
- **Defaults:** `only.default` lists picks a new session starts with, groups or installed apps in no group (Things, Spotify, Bear, the terminals). They start ticked in the picker, so SPACE unticks one; named picks bring them along and `no:NAME` leaves one out (`focus only ai-chat no:spotify`); in Alfred ENTER on a ticked default drops it. During a session `focus only no:NAME` takes a pick away, at once, since it only tightens. An app that should sometimes pause belongs here, not in `only-tools` (Yulong, 2026-11-19).

## Status flags blocks with a weak lock

The note's optional `strong_lock_blocks: [<block>, ...]` lists Cold Turkey blocks that should carry a random-text lock. `focus status` prints a yellow `weak lock:` line for each listed block whose lock is none or a delay lock, since a delay lock is one short wait from being turned off, and for a listed block that Cold Turkey does not have. Without the key, nothing is printed. The lock itself is set by hand in Cold Turkey; Cold Turkey's stored form of a random-text lock is unknown, so any lock other than none or a delay counts as strong enough.

## Capped modes run for a limited stretch

The note's optional `capped_modes: {<mode>: {minutes: 30, day_minutes: 180, fallback: <mode>}}` caps a mode. `focus <mode> [MINUTES]` runs it for at most `minutes`, then switches back to the mode that ran before it, or to `fallback` if none did, with a notification. A detached waiter and the launchd tick (`focus install-agent`) end it, so it ends after a restart too.

- **Renewal:** allowed at once, with no cooldown. Every start of the mode after the first of the local day asks for a one-line reason: at the terminal, or without one (Alfred) in a macOS dialog; an agent gets no dialog and is refused. An empty or blank reason is refused with an error and asked again; Ctrl-C or Cancel changes nothing. Each reason goes to `~/.local/state/focus/commit-log.jsonl` with the time and the command.
- **Day budget:** `--day [MINUTES]` runs one longer stretch from `day_minutes`, asking the reason once. A day stretch left early gives its unused minutes back; later starts that day are normal stretches.
- **The mode before is kept:** a renewal keeps it, and a break or only session started during a stretch returns to it, never to the capped mode without its cap. A switch to another mode by hand ends the stretch.
- **One worker at a time:** a start, a renewal and an expiry each hold `~/.local/state/focus/capped.lock` from reading the record to the last switch and write, and re-read it once they hold it, so an expiry never ends a stretch renewed meanwhile. The committed block does the same with `commit.lock`. A reason prompt holds the lock while Yulong types.
- **The agent delay still applies:** switching into a capped mode from another mode, and renewing one, wait like any loosening.

## Committed blocks hold a person too

`focus <mode> [MINUTES] --commit` (default 60) starts the mode and keeps its Cold Turkey block locked until the end time. This reverses "people are never delayed" for that time (2026-11-18). The lock rolls: the launchd tick, and every focus command before it does its own work, keep it about `commit_wait_minutes` (default 5, at least 2) ahead with `-start <block> -lock N`, extending it once less than about 2.5 minutes remain. Each extension brings Cold Turkey to the front for about 0.5 s. State is in `~/.local/state/focus/commit.json`.

- **What refuses:** `focus break`, `focus off`, `focus only` and starting any other mode, capped or not, each naming `focus allow` and `focus end`. `focus deep` still runs, since it only tightens. `focus status` and the overview show the committed block and its end time.
- **Allow and end:** each shows a random text of `commit_text_chars` (default 150) characters to type back exactly, then asks for a reason, logged to `~/.local/state/focus/commit-log.jsonl`. Both need a terminal, so an agent cannot finish them, and an agent also meets the usual delay first. focus then stops extending the lock and prints when it runs out. Cold Turkey then stops the block, and a waiter applies the request within a few seconds.
- **Allow, applied:** the sites go into the note group `added-<mode>`, which the mode's `allow` list names, and into the block as exceptions; then the block starts and locks again. Only sites, not apps.
- **End, applied:** the block stops and the commitment is cleared; ScreenZen follows as for `focus off`.
- **A stopped block is put back:** if the tick finds the block stopped before the end with nothing pending (a missed tick, sleep, a locked screen), it starts and locks it again and logs that. Commands cannot land while the screen is locked.
- **At the end time:** the last lock runs out and the mode stays on, unlocked.
- **Two keepers:** the commitment starts only when `launchctl print` shows the job loaded and running this focus with this note; a plist on disk is not enough, since `launchctl` may have refused it. A detached keeper also runs the same check every 30 s until the end.
- **Accepted limitation:** unloading the launchd job and stopping the keeper (or restarting with the job unloaded), or deleting the state file, lets the lock lapse within one wait. Never do either to get past a commitment, and never edit the state or the log.

## A person who loosens types a reason

Since 20 Nov 2026 every loosening by hand asks a one-line reason, at the terminal or in a macOS dialog (Alfred), and an empty or blank reason is refused with an error and asked again; Ctrl-C, Cancel or the dialog timing out changes nothing. Reasons go to `~/.local/state/focus/commit-log.jsonl`.

- **What asks:** `focus break`, `focus off`, an only session that replaces a running mode, adding picks to or extending a session, and a mode switch that loosens. A switch loosens when the target is a capped mode or opens an app a running mode blocks. Sites are not compared, so research to writing, and any capped mode back to research, ask nothing.
- **What does not:** starting a mode from no mode, tightening, ending a session for a mode that is not capped, and the launchd job's own starts (default, scheduled, break and stretch ends).
- **An agent is never asked:** it has no terminal or dialog, so the delay below holds it instead.

## Loosening waits; do not work around it

When Claude runs it, `focus` delays anything that loosens blocking: stopping a mode, switching modes, a sync that allows new sites, a ScreenZen write that allows more or blocks less. **Exit code 3 means queued, not failed.** Tell Yulong the change and the time it becomes runnable, and stop. Run the same command once more after that time only if he still wants it. Never edit `~/.local/state/focus/pending.json`, `focus` or `agent_loosen_delay_minutes` to skip the wait, and never loop on the command. If he wants it now, give him the command to run himself. Starting a mode from none and anything that only tightens run at once.

## Cold Turkey's CLI needs a wake-up

- **Mechanism:** the CLI is the app in a second process. It writes its arguments to the `commandArgs` preference within 0.1 s, then idles for about 5 s and prints "isn't responding", even for `-help`. The reply decides nothing; only the database says whether a change landed.
- **One slot, read on activation:** the agent reads and deletes `commandArgs` when it becomes the active app, and does not look otherwise. A second command replaces an unread first, which is how `focus sync` used to lose sites.
- **How `focus` handles it:** `ct_apply` sends the command, activates the agent by pid for a moment, watches the database, and hands the front back. A real `focus deep 1` took 0.51 s this way (6 Nov 2026), and the same call failed twice without the activation. No Automation permission is needed.
- **A start or stop is sent twice before it fails:** on a second miss `focus` reports it as well as exiting with the error. A mode switch ends by stopping every other unlocked mode block it finds running, read fresh, so two modes never stay on together (20 Nov 2026: research stayed on beside comms and kept Messages blocked).
- **A failed command is taken back:** left in the slot, it would run whenever Cold Turkey next came to the front, so `ct_apply` deletes its own unread command on a miss (23 Nov 2026: a default start missed in a 09:14 dark wake ran at 12:48 and brought research back in the lunch window). A command sent by hand outside focus is not taken back. Never probe with a real command by calling the CLI by hand. `defaults read com.getcoldturkey.blocker commandArgs` shows what is waiting: a missing key means nothing is.
- **A failure from Alfred is a dialog, not a notification:** a macOS Focus mode can hide a notification. The Alfred workflow sets `FOCUS_FROM_ALFRED=1`, and detached copies inherit it. Under it, any failed exit and any failed `sz-apply` or capped-stretch end show a `display alert` that stays until dismissed. Cancel on the reason dialog shows nothing. The launchd tick has no such variable, so it keeps notifications (Yulong, 22 Nov 2026).
- **Mode changes return before ScreenZen finishes:** for a person, `focus` starts a detached `focus sz-apply`, which reads what is running once it holds the lock and reports a failure. An agent stays in the foreground so that it sees the delay. `sz-apply` is internal.
- **The launchd tick keeps ScreenZen in line:** every minute, after its own work and even when a Cold Turkey command went unread, it writes ScreenZen from what Cold Turkey runs now, only when the two differ. Failures go to `~/Library/Logs/focus-tick.log`. So a missed switch heals within a minute, and nobody needs to run `focus screenzen` by hand (21 Nov 2026: a messaging stretch kept "🚫 distractions" on and paused Instagram DMs).

## Changing the lists

- **"Allow X in research":** put X in the group that fits it (or a new group the mode names), never straight into a mode. Say which other modes get it through that group.
- **"Block X":** add it to an always-blocked group, or remove it from the allow group that lets it through.
- **"Why is X blocked":** check, in order, whether the running mode allows a group containing X, whether a Cold Turkey always-on block bans X (`focus status` prints `conflict:` lines; an exception never overrides another block), and whether a ScreenZen 🚫 group lists it.
- **A mode allowing what an always-on block bans, on purpose:** list the site under the note's top-level `overlaps:` with a one-line reason. `focus status` then prints it dimmed as `by design:` instead of a yellow `conflict:`, and prints `stale overlap:` once the site no longer overlaps, so the list cannot go stale silently.
- **What stays manual in Cold Turkey:** removing a site, changing a mode's apps, and loosening an always-on block (the Cold Turkey blocks under `blocklists.cold_turkey` in the note). `focus sync` tries to add the sites the always-on blocks and timers lack through the CLI, banned and allowed alike (allowed ones pass the agent delay, since they loosen); a lock may refuse them, and sync says when one did not land and names the hand edit. Until 19 Nov 2026 it skipped allowed sites there while `focus status` said sync would add them. `focus status` says "focus sync adds these" for a difference sync can make; for the rest, give Yulong that line as the step to do by hand. Sync sends additions one at a time and waits about 1 s for each to land before sending the next, because the command slot holds one, and each one brings Cold Turkey to the front for a moment, so a person sees a flicker per site and a progress bar. A list of more than 10 new sites for one block goes to `~/Downloads/focus-<block>-<exceptions|web>.txt` instead, and sync prints the block-editor steps (Import > Websites from file...) for Yulong to import it in one go (2026-11-18). That Import is the one inside the block's editor; the Blocks page's own Import takes only `.ctbbl` and calls a `.txt` an "Invalid File" (2026-11-26).
- **Why not write Cold Turkey's database directly:** it is possible (the settings are lightly obfuscated JSON), but it is exactly the path around the delay locks, and the running app can overwrite or corrupt it. Do not build or suggest it.
- **ScreenZen's 🚫 groups win inside ScreenZen.** A site a mode allows but a ScreenZen 🚫 group blocks is left out of every "✅ focus:" group, so it keeps its pause screen all day. A 🚫 group with `off_in: [admin]` in the note stands aside while those modes run (messaging apps during admin) and is back on otherwise.
- **ScreenZen skips an app the running mode's Cold Turkey block already blocks.** Each write leaves out of its 🚫 groups the apps that the running `mode:` block holds in Cold Turkey (read from Cold Turkey, not the note), so WhatsApp and Spark get Cold Turkey alone in research and writing; with no mode they get the ScreenZen pause again. Leaving them out is not a loosening, so it never waits on the agent delay. Sites are not deduplicated (Yulong, 2026-11-20).
- **Time windows come from the apps' own schedules, not from a mode.** Some always-on blocks are scheduled off at set hours; the note says which. A running mode still blocks everything it does not allow, so a window needs `focus off`. Schedules are edited in the apps, not the note.
- **Pattern syntax** is Cold Turkey's (`*` for any text, a path is its own entry). ScreenZen matches by substring, so `focus` cuts allow patterns at the first `*` and strips `*` from block patterns.
