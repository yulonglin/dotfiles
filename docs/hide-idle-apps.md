# Hide Idle Apps

macOS-only background job that clears the screen of apps you have stopped looking at. Off by default — enable with `deploy.sh --hide-idle-apps`. The manual counterpart is `clear-mac-apps`, wired to a macOS Shortcut. Both read one config and share one escalation path.

## The ladder

A covered-up app walks three rungs, each with its own clock: **hide** (Cmd+H equivalent, via System Events `visible`) after `hide_after` minutes covered → **close windows** after a further `close_after` → **quit** after a further `quit_after`. Defaults 15 / 15 / 30 minutes.

Escalation is not reimplemented in the idle job: it calls `clear-mac-apps --only "<App>" [--max-action close]`, so config vetoes apply to both triggers through one code path. `--only` filters before classification, `--max-action` caps after it. At most one destructive action runs per poll, most overdue first — a slow quit must not overrun the poll interval and trip the job's own gap check.

## Policy

Each app in `config/app-lifecycle.yaml` carries `manual:` (what the Shortcut does to it right now) and `auto:` (what the idle job may do), on the ordered scale `skip` < `hide` < `close` < `quit`.

The ladder stops at `min(manual:, auto:)`, but that ceiling binds **only the destructive rungs**. Hiding is governed by `auto:` alone, and `auto: skip` is the only exemption from being hidden — it is what the old `[hide-idle-exclude]` section became.

| Config | Hidden? | Windows closed? | Quit? |
|---|---|---|---|
| `{auto: skip}` | no | no | no |
| `{manual: skip}` (Lettera, zoom.us) | yes | no | no |
| `{manual: hide}` (Obsidian, Focusmate) | yes | no | no |
| `{manual: close}` (Spotify, Things) | yes | yes | no |
| unlisted (defaults) | yes | yes | yes |

The `skip` and `hide` rows are identical here because this table is about the idle ladder, and the two differ only in the manual trigger: the Shortcut leaves a `skip` app untouched and hides a `hide` one. Neither ever has a window closed.

Both scripts read the YAML through `custom_bins/app-lifecycle-config`, so no zsh parses YAML. Only the poll interval lives elsewhere, in `config/hide-idle.conf`: it is not a policy about apps, and it has to match the launchd `StartInterval` or gap detection means nothing.

Environment overrides both files: `HIDE_AFTER_MINUTES`, `CLOSE_AFTER_MINUTES`, `QUIT_AFTER_MINUTES`, `USER_IDLE_MINUTES`, `HIDE_IDLE_MIN_VISIBLE_PERCENT`, `HIDE_IDLE_POLL_SECONDS`. `hide-idle-apps --help` lists them.

## The idle gate

The destructive rungs additionally require the machine to be idle: no HID input for `USER_IDLE_MINUTES` (`ioreg -c IOHIDSystem`, `HIDIdleTime`) and no live microphone (a `coreaudiod` power assertion listing `audio-in`).

Busy **pauses** those clocks rather than resetting them, so a working session does not earn every app a fresh 15 minutes each time you touch the trackpad. **Either signal being unreadable counts as busy** — "cannot tell whether the mic is live" must never license closing windows. Hiding never consults this gate; occlusion is its whole test.

## Measuring visibility

`tools/window-exposure/main.swift` (compiled once) reads `CGWindowListCopyWindowInfo` and computes, per window, the fraction of its frame not covered by the **union** of the opaque, different-PID windows in front of it — exact, via coordinate compression, with single-window containment kept as a fast path. Being a union, it detects several windows jointly covering one. It reads only the window-list keys that are populated without Screen Recording permission.

Two things are never hidden whatever their coverage: whatever is **frontmost**, and any app with no window in the onscreen list (another Space, fullscreen, minimised) — that is *unknown*, not *not-exposed*. Hiding also requires two consecutive covered polls.

`HIDE_IDLE_MIN_VISIBLE_PERCENT` is a whole percent — 40, not 0.4 (which is valid and means 0.4%). An out-of-range value hides nothing and says why on stderr, rather than falling back to a default nobody asked for.

A small OS-chrome set (Finder, Dock, SystemUIServer, loginwindow, WindowServer) is hardcoded-excluded in `custom_bins/hide-idle-apps` and is not user-configurable.

## State and self-healing

Per-PID state lives in `~/.cache/hide-idle-apps/state` (format `#v3`), carrying each app's rung and a *pause-adjusted* clock epoch, so `now - phase_clock_epoch` reads elapsed **unpaused** seconds. A state file from an older version is discarded and rebuilt, never migrated.

The rung has to be stored because exposure alone cannot tell "on another Space" from "hidden by us" — neither owns an onscreen window.

Any untrustworthy poll — unreadable config, older-version state, helper failure, empty window list, or a gap over 3× the interval (sleep, logout, session switch) — acts on nothing and restarts every timer.

An app that becomes frontmost, or owns an onscreen window again, drops back to the bottom rung. That is also what self-heals a hide or a close that silently failed. Dropping back resets the exposure timer as well as the phase clock, so an app you un-hide is not hidden again in the same second.

That self-heal cannot rescue a *hidden* app, which owns no onscreen window by construction. So a rung is advanced **before** the call — a job killed mid-close must not re-fire every poll — and given back if the call returns nonzero, or a close that failed would start the quit clock.

That give-back only works if `clear-mac-apps` reports the run rather than something incidental, so its `main()` counts failed actions and returns them explicitly. It once ended on `(( ${#slow_quit_set} > 0 )) && echo …`, which made the exit status report *whether the config listed a `slow: true` app* — with one listed the give-back never fired, without one it always did. The close path likewise reports the window count it left behind instead of swallowing it in `|| true`, and the parallel hide loop waits on each PID, because `wait` with no arguments discards every job's status.

The one deliberate exception is the fast-quit loop, which keeps a bare `wait`: `tell application "X" to quit` waits for a reply the app often dies before sending, so honouring that status would manufacture failures rather than find them. Nothing consumes it — the give-back applies to `close` alone.

The two callers want that failure reported two different ways. The idle job passes `--only` and consumes the status, so there it propagates. A bare invocation is the macOS Shortcut, where "Run Shell Script" turns any nonzero status into a Shortcut error dialog — far too loud for one app keeping a window open. That path posts a notification naming the rung and the app, and exits clean.

The subtlest version of the same bug was a *refusal* reported as success. When a run capped at `close` found, on rescan, that an app's last protected window had gone, it declined to quit — correctly — and returned 0 having closed nothing. The close rung then read as complete. A capped run now closes the windows instead, which is what that rung was asking for anyway.

## Closing windows without stealing focus

`clear-mac-apps` closes windows by clicking each window's `AXCloseButton` via System Events, instead of making the app frontmost and typing Cmd+W at it. Apps whose windows have no such button fall back to the keystroke path (Cmd+W, escalating to Cmd+Shift+W for tabbed apps).

Which apps those are is remembered in `~/.cache/hide-idle-apps/ax-capability` as `name<TAB>epoch`, keyed by app name, trusted for `AX_CAPABILITY_TTL_DAYS` (default 30) and then re-probed. A record with no timestamp predates expiry and counts as stale. Expiry matters because the record is only consulted when one exists: a permanent record meant an app that *gained* a close button in an update was typed at forever.

An app with **no** windows is skipped entirely and never recorded — a probe that fails for want of a window says nothing about what the app supports. A missing close button fails the click immediately, but a *slow* close is not held against the app: the probe gives up only after `patience` (default 3) **consecutive** clicks leave the window count unmoved.

## Calibrating

`hide-idle-apps --dry-run` prints one resolved decision per app: measured visibility, current rung, the app's `manual:`/`auto:` values, the rung it is heading for, and what is holding it there — `frontmost`, `visible enough`, `no window here`, `streak 1/2`, `in 10m`, `busy`, or `ceiling` — plus whether the machine is currently busy.

Visibility alone answers "is the threshold right"; the gate column answers "why is this app still sitting here", which for a paused clock is otherwise indistinguishable from a stuck one.

## Known limits

State is keyed by PID, so a recycled PID can inherit another app's rung. In practice a poll then sees a different name and the app drops back to the bottom rung; the window is one poll wide.

Neither script takes a lock. launchd will not run two copies of the same job concurrently, but a hand-run `hide-idle-apps` racing the scheduled one can lose a rung advance — both write state by atomic rename, so the file stays valid and the later writer wins.
