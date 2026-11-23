# clear-mac-apps moves to Swift behind the same command

Spec, draft 1, 23 Nov 2026. Written by Claude Opus 5.5 for Yulong's review. Nothing in it has been built or measured yet.

## Overview

`clear-mac-apps` clears the screen of apps. The macOS Shortcut runs it by hand, and `hide-idle-apps` runs it on a timer. Today it is 1,155 lines of zsh that drive System Events through osascript. It is hard to read, and its comments record more than twenty past bugs, most of them shell traps or AppleScript traps.

This spec replaces the zsh with one Swift program that calls the macOS APIs directly. The command name, the flags, the config file and the exit codes stay the same, so the Shortcut and `hide-idle-apps` do not change.

What the rewrite should gain:

- **Readable code.** Real types for apps, actions and failures, with one function per stage.
- **Fewer moving parts.** No osascript, no System Events, and no AppleScript text built from app names.
- **Possibly speed.** This has not been measured. Requirement R9 measures it, and the rewrite is worth doing even if there is no speed gain.

What it does not gain: the Safari web-app name clash and the focus stealing on close are already fixed in the zsh version (`docs/hide-idle-apps.md`, lines 28 and 72). The rewrite must keep those fixes, but it does not add them.

The main risk is **Accessibility permission**. See R7: a recompiled binary may lose its grant.

## Requirements

### R1. The command, its flags and its exit codes stay exactly as they are

- MUST keep the path `custom_bins/clear-mac-apps`. It becomes a short zsh launcher that compiles `tools/clear-mac-apps/main.swift` when the binary is missing or older than the source, then runs the binary with the same arguments. This is the pattern `hide-idle-apps` already uses for `tools/window-exposure`. `deploy.sh` also compiles it.
- MUST accept every current flag with the same meaning: `--dry-run`/`-n`, `--only NAME` (repeatable), `--except NAME` (repeatable), `--except-browsers`, `--max-action close|quit`, `--allow-focus-steal`, `--migrate-config FILE`, `--config`, `--edit` and `--help`. The first line of `--help` names the config path.
- MUST keep the exit codes:
  - 0 for success, any dry run, `--config` and `--help`.
  - 1 for a bad flag or an unreadable config, and, under `--only`, for a failed inventory or any failed action. `hide-idle-apps` reads this status to give an app its rung back.
  - A bare run never exits non-zero for a failed action. It posts a notification instead, because the Shortcut turns a non-zero exit into an error dialog.

### R2. The config stays YAML and is still read by app-lifecycle-config

- MUST read `config/app-lifecycle.yaml` through `custom_bins/app-lifecycle-config`, with a new `--json` output that Swift decodes. Swift has no built-in YAML reader, and the Python helper already validates every value (invalid values exit 78).
- MUST use the same keys the zsh uses: `defaults.manual`, and for each app `manual`, `slow` and `protect_windows`.
- MUST keep reading `config/safari_web_apps.local` (format `name|bundle_id|path`) and refresh it with `safari-web-apps-scan` when it is missing or more than a day old.
- MUST resolve both paths from the real location of the binary's source tree, not from the working directory.

### R3. Each zsh stage maps to a native call

| Stage | zsh today (System Events via osascript) | Swift |
|---|---|---|
| List apps | `unix id`, `name`, `bundle identifier` of processes whose `background only` is false | `NSWorkspace.shared.runningApplications`, filtered to `activationPolicy != .prohibited` |
| Quit | `tell application id <bid> to quit` | `NSRunningApplication.terminate()` |
| Slow quit | quit, then poll by unix id every 2 s for 30 s | `terminate()`, then poll `isTerminated` with the same timing |
| Hide | `set visible to false` | `NSRunningApplication.hide()` |
| Minimise | set `AXMinimized` on each window | `AXUIElementSetAttributeValue(window, kAXMinimizedAttribute, true)` |
| Count windows | `count windows` | `kAXWindowsAttribute` on `AXUIElementCreateApplication(pid)` |
| Close | click the button with subrole `AXCloseButton` | `AXUIElementPerformAction(kAXCloseButtonAttribute value, kAXPressAction)` |
| Keystroke fallback | make the app frontmost, then `keystroke "w"` with Cmd, or Cmd+Shift | `CGEvent` key events, kept behind `--allow-focus-steal` |
| Window titles | `name of window 1` | `kAXTitleAttribute` on every window |
| Chrome tabs | Chrome's AppleScript dictionary | still AppleScript, through `NSAppleScript`, since Chrome has no other API for tab titles |
| Notification | `display notification` | still `osascript -e 'display notification …'`, since a bare binary with no app bundle cannot use `UNUserNotificationCenter` |

- MUST address every action by PID or bundle id, never by name. Every Safari web app shares the process name `Web App`.
- SHOULD check every window title, not just window 1, for `protect_windows`. This lifts a known limit of the zsh version, and is the one place where behaviour may change on purpose.

### R4. Classification and action order match the zsh exactly

- MUST classify in this order, first match wins: `--only` and `--except` filters (case-insensitive exact name), then skip, hide, minimise, close, then the protect check, then the app's own `manual:` falling back to `defaults.manual`. A quit becomes a slow quit when the app has `slow: true`.
- MUST apply `--max-action close` after classification, turning every quit and slow quit into a close.
- MUST run actions in the same order and with the same concurrency: quits in parallel, hides and minimises in parallel, closes one at a time, slow quits in parallel, selective closes one at a time.
- MUST keep the close ladder: zero windows counts as success. Otherwise press the close button up to 20 times, polling 0.2 s up to 5 times after each press, and give up after 3 presses in a row that change nothing. An app whose windows have no close button is remembered in `~/.cache/hide-idle-apps/ax-capability.v2` for `AX_CAPABILITY_TTL_DAYS` (default 30). Without `--allow-focus-steal` such an app is hidden instead.
- MUST keep the selective close for Chrome: close only unprotected windows, check again afterwards, quit Chrome if no windows are left (unless capped), and report failure if a targeted window is still open.

### R5. Dry-run output stays byte-identical

- MUST print the dry run in exactly the format of `tests/fixtures/clear_mac_apps.dry-run.txt`, with the same sections, order and quoting.
- MUST keep writing `~/.cache/hide-idle-apps/last-run.log`, truncated on each real run, and the end-of-run summary ("Done.", the config sets, and "Failed actions: …").

### R6. A failed read is a failure, never an empty list

Several past zsh bugs came from treating a failed read as "no apps" or "no windows", which then allowed a quit. The Swift code must not repeat them.

- MUST treat a failed inventory, a failed Chrome tab read and a failed window rescan as errors, recorded in the failure list. Never as an empty result.
- MUST drop malformed records (no PID, a tab character in the name) with a warning, not act on them.
- MUST count every action that does not do what it says, including hides and minimises. The exit status and the notification come from that list alone.

### R7. Accessibility permission survives a rebuild, or the cost is known

macOS keys an unsigned binary's privacy grants to that exact binary, so each recompile may ask for Accessibility again. `tools/tcc-carry-claude` exists because of the same problem with Claude Code releases. Which process macOS asks about also depends on who launched the binary: probably Shortcuts for the Shortcut, and the binary itself for the launchd job. **None of this has been tested on this Mac.**

- MUST check `AXIsProcessTrusted()` at start-up. If it is false, fail loudly by the R1 rules (a notification on a bare run, exit 1 under `--only`), naming System Settings → Privacy & Security → Accessibility.
- MUST, before the rest of the build, run a pilot (A1) that settles which process needs the grant for each caller, and whether a rebuild loses it.
- SHOULD sign the binary with a stable self-signed identity if the pilot shows that a rebuild loses the grant, so the grant follows the identity rather than the binary's hash.

### R8. Behaviour is tested through a fake system, not through osascript stubs

The current suite stubs osascript and matches substrings of the AppleScript text, so it cannot test a binary that makes no AppleScript calls. Only about five of its 25 sections would still run.

- MUST put every macOS call behind one Swift protocol with two implementations: the real one, and a fake that reads apps and windows from a JSON fixture and logs each call made. An environment variable selects the fake, for tests only.
- MUST port each of the 25 sections of `tests/test_clear_mac_apps.zsh` to the fake, keeping each section's assertion about what was done to which PID or bundle id.
- MUST keep one test per past bug listed in the zsh comments that can still happen in Swift: addressing by name, a delimiter in a name, an empty list after a failed read, `hide` and `minimise` falling through to quit, `slow` outranking close, `defaults.manual` handling, exit status not matching the failures, and a capped selective close returning 0.
- MUST keep `tests/test_hide_idle_apps.zsh` passing unchanged.

### R9. Run time is measured before and after

- Question: is the Swift version faster on a bare dry run of this Mac's real apps? The answer could be no.
- Independent variable: the implementation, zsh or Swift, run on the same set of open apps.
- Dependent variable: wall-clock seconds for `clear-mac-apps --dry-run`, 10 runs each, alternating zsh and Swift, reported as median and range.
- Null: no difference. A difference smaller than the run-to-run range counts as no difference.
- This number is reported, not gated. The rewrite ships on R1–R8 alone.

### R10. The zsh version stays available for two weeks, then goes

- SHOULD keep the zsh script as `custom_bins/clear-mac-apps-legacy` for two weeks after the switch, with `CLEAR_MAC_APPS_LEGACY=1` making the launcher run it instead.
- MUST delete it after that, along with the osascript stub in the test suite.

## Acceptance Criteria

### A1. The permission pilot answers three questions before the main build

A minimal Swift binary that only calls `AXIsProcessTrusted()` and counts Finder's windows is run three ways: from the Shortcut, from the `hide-idle-apps` launchd job, and from a terminal. It is then rebuilt and run the three ways again. The write-up records, for each caller, which entry in Accessibility had to be on, and whether the rebuild lost it. If a rebuild loses it, a stable self-signed identity is tried and the result recorded.

### A2. The ported test suite passes and covers every section

The Swift suite passes with every one of the 25 old sections ported, and the per-bug tests from R8 present. `tests/test_hide_idle_apps.zsh` passes unchanged.

### A3. Dry runs match on real apps

On this Mac with a normal set of apps open, `clear-mac-apps --dry-run` from the zsh version and from the Swift version give identical output. The golden-file test also matches byte for byte.

### A4. One real day of use with no regression

For one working day, the Shortcut and the idle job run the Swift version. `last-run.log` and the notifications show no app quit that the config says to skip, close or hide, and no new failure class. Yulong confirms the Shortcut behaves as before.

### A5. The R9 timing is reported

The median and range for both versions are written up next to the A4 result.

## Open points for Yulong

- **Keystroke fallback.** `CGEvent` may be able to send Cmd+W to a background app without making it frontmost. If so, the `--allow-focus-steal` flag could go. This is unverified, and the spec keeps the flag until it is shown.
- **A doc mismatch found on the way.** `docs/hide-idle-apps.md:28` says the inventory iterates "inline", but the code and its comments say the opposite (inline iteration hung for minutes). The rewrite makes this moot, but the doc should be fixed either way.
