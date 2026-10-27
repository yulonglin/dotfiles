# macOS Media Wedge: Several Apps Hang While CPU Stays Low

When several unrelated apps stop working at once and CPU, memory and network all look healthy, check the audio stack first. A wedged `coreaudiod` — left by a crash-looping `avconferenced`, or deadlocked inside itself (2026-10-26) — means every app that touches audio, camera or contacts then blocks in synchronous IPC. Flat resource graphs are the signature of this wedge, not evidence against it. Run `reset-mac-media --check` (read-only, about a second), then `reset-mac-media` to fix it without a reboot.

## The symptoms look like a network or display fault

On 2026-09-24 the first symptoms were read as a network problem and cost about 15 minutes on the wrong lead. Any of these, together, points here:

- Safari and Chrome tabs do not load, while `curl`, `ping` and DNS from the terminal are fast. Both browsers' network processes hold only CLOSED sockets.
- An Electron app (Spark) launches, restores its windows and then shows nothing, with no network sockets.
- FaceTime, Spotify or other audio apps freeze; the UI feels stuck.
- NordVPN's Shield extension logs `Failed to talk to secd after 4 attempts` every few seconds. This is a downstream symptom: it stopped as soon as the media daemons restarted. Killing Shield does nothing, because launchd respawns a system extension at once.
- `~/Library/Logs/DiagnosticReports` holds a run of `avconferenced-*.ips` files a few seconds to minutes apart.
- One app hangs every time it launches (Telegram on 2026-10-26, first mistaken for a WindowServer fault), and `/Library/Logs/DiagnosticReports` holds `.hang` reports whose header reads `Deadlock: coreaudiod`.

## Confirm it in thirty seconds

```bash
reset-mac-media --check              # exit 0 healthy, 1 wedged, 3 recent crashes but audio answers, 4 probe errored
reset-mac-media --check --since 240  # widen the crash-report window (minutes)
```

The check asks CoreAudio for its device list with a 20-second timeout. A healthy Mac answers in about a second; a wedged one never answers. It also lists `avconferenced`, `audiomxd` and `coreaudiod` crash reports from the window. It needs no sudo and restarts nothing.

## Fix it with reset-mac-media, and reboot only as the fallback

```bash
reset-mac-media --dry-run   # preview
reset-mac-media             # save diagnostics, restart the media daemons, verify
```

It needs administrator authentication and interrupts audio, video and calls for a moment. Apps that were blocked recover on their own. A deadlocked `coreaudiod` cannot act on SIGTERM, because its handler runs on a dispatch queue that is itself blocked: on 2026-10-26 it kept PID 634 through two runs. So the helper now sends SIGKILL to a daemon whose PID has not changed 5 s after SIGTERM, and to that daemon only. Brew-upgraded apps that were running during the upgrade (see below) should be quit and relaunched as well. If the helper is not at hand, this is the minimal equivalent:

```
sudo killall -9 \
  coreaudiod \
  audiomxd \
  avconferenced
```

If neither clears it, reboot. A normal restart can hang for over ten minutes because frozen apps cannot quit (2026-08-24), so be ready to hold the power button.

## Four incidents, two mechanisms, a call in every one

The first three incidents share one crash site: `avconferenced` terminating itself from `+[VCXPCConnection selfTerminateDueToTimeout:]` on an XPC call timeout, repeated seconds to minutes apart.

| Date | What happened just before | Other crash | Fixed by |
|---|---|---|---|
| 2026-08-24 | FaceTime call with a broken peer; Alfred's audio-device switcher crashed on a vanished CoreAudio device | `audiomxd` abort | Hard reboot |
| 2026-09-22 | AirPods broke CoreAudio's Bluetooth route before a call (session notes; verification was left pending) | FineTune suspected | `killall` of the media daemons |
| 2026-09-24 | A manual `brew update` then `brew upgrade` (run by Yulong) quit or replaced 15 running apps from 17:04:00 (AlDente and Alfred first); first `avconferenced` crash at 17:04:28 | FineTune crashed 17:05:16 | `killall` of the media daemons |
| 2026-10-26 | A Google Meet call in Safari on AirPods ended at 14:40:04; about 10 s later `coreaudiod` deadlocked. No `avconferenced` loop until the reset restarted it | None; two Telegram `.hang` reports named `Deadlock: coreaudiod` | `reset-mac-media` failed twice (SIGTERM ignored); `killall -9 coreaudiod` pending |

The 2026-10-26 wedge is a different mechanism: a lock-order deadlock inside `coreaudiod`, with no crash. One thread was updating a process tap's format for the AirPods (`HALS_Tap::_UpdateTapFormatFromDeviceFormat`), which happens when they leave headset mode at the end of a call. The other was removing an audio client (`HALS_System::RemoveClient`). Each held the lock the other needed. A process tap exists only if some app captures or reroutes other apps' audio, and two were running: FineTune, which taps every app for per-app volume, and Granola, which records the meeting through Chromium's Core Audio tap (its Electron framework carries `AudioHardwareCreateProcessTap` and the `MacCatap*` capture flags, including `MacCatapRestartOnDeviceChange`). Granola's tap is the one tied to the call, so the owner is about even between the two, unproven. No public report of this exact deadlock was found on 2026-10-26; the nearest is a leaked process tap that wedged `coreaudiod` system-wide ([screenpipe #3942](https://github.com/screenpipe/screenpipe/issues/3942)). The thread timestamps count awake time only, so the deadlock time needs the 14:46–14:50 sleep added back; that correction is what places it at the end of the call. Evidence: `~/scratch/coreaudio-wedge-2026-10-26/`.

On 2026-09-24 the FaceTime call ended at about 17:03, one minute before the upgrade began, and `avconferenced` was still logging RTCP timeouts from its teardown at 17:03:08. NordVPN Shield's `secd` errors had begun at 15:59:29, the second the camera came on for that call. So brew quit AlDente and Alfred while the call was still being torn down, on a stack that may already have been strained; the upgrade guard alone might not have prevented it.

A call is present in all three incidents: during it on 2026-08-24, just before it on 2026-09-22, and in its teardown on 2026-09-24. That is the strongest common factor.

The other common thread is a sudden change under CoreAudio's feet — a device vanishing, or a running app's bundle disappearing — with a third-party CoreAudio hook (Alfred's switcher, then FineTune) present each time. That link is a pattern across three cases, not a proven cause. Which bundle swap set off the 2026-09-24 loop is unproven: AlDente, Alfred, Codex and Conductor were replaced in the 28 seconds before it, and Discord and Claude were not running.

## Prevention: skip running apps on upgrade, and limit FineTune

A cask upgrade takes a running app away mid-session. Casks that declare an uninstall `quit` stanza (AlDente, Alfred, Spark, WhatsApp, superwhisper, VS Code and most others here) are quit by Homebrew; the rest (Chrome, Cursor, Conductor, RemNote) have their bundle swapped under the live process. Two guards now skip running apps:

- **Interactive:** a bare `brew upgrade` (zsh wrapper in `config/aliases/brew.sh`) lists outdated apps that are running, marks the ones holding a live audio session, and offers to skip them. It runs `reset-mac-media --check --since 15` afterwards. `command brew upgrade` bypasses the wrapper; an upgrade that names packages passes straight through.
- **Unattended:** the weekly `update-packages` run upgrades formulae and only the casks whose app is not running, logs the ones it skipped, and runs the same health check. The cost: an app that is always open (Telegram, Dropbox, ChatGPT, Tailscale) is never upgraded by this run and relies on its own updater. The weekly job is not installed on this Mac as of 2026-09-24.

The 2026-09-24 upgrade was a manual, plain `brew upgrade`, started at 16:11:32. It waited at a password prompt until about 17:04 (Yulong confirmed entering a password), so the apps were quit and replaced a minute after the call ended. All 15 casks it upgraded declare `auto_updates`, and a plain upgrade still included them: on this Homebrew 7 install, a plain `brew outdated --cask` lists `auto_updates` casks such as Conductor, and `--greedy` adds only those that "would otherwise be skipped" (which ones is not verified). Do not rely on self-updating apps being left alone by a plain upgrade. This is exactly the case the wrapper covers: a bare, interactive `brew upgrade`. A long password wait is also a timing hazard in its own right, because the upgrade then starts whenever the password is typed, perhaps just after a call. The wrapper honours `HOMEBREW_UPGRADE_GREEDY` when it is set.

Both use `brew-running-casks`, which maps each outdated cask to its `.app`, matches running processes by executable path, and reads `pmset -g assertions` to flag audio use. Run it directly to see what an upgrade would touch:

```bash
brew-running-casks            # running outdated casks: token, app, pids, audio flag
brew-running-casks --greedy   # include casks that update themselves
```

**Wait a few minutes after a call ends before running `brew upgrade`**, and do not start one during a call.

**Add FaceTime to FineTune's ignore list** (decided 2026-09-24). FineTune's GitHub issues document friction with calls specifically, not a general fault: about ten FaceTime reports, five still open, where FineTune's audio tap fights FaceTime's voice-processing mode and leaves call audio near-silent or crackling ([#113](https://github.com/ronitsingh10/FineTune/issues/113), [#156](https://github.com/ronitsingh10/FineTune/issues/156), [#262](https://github.com/ronitsingh10/FineTune/issues/262)), plus a cluster on AirPods and Bluetooth routing ([#185](https://github.com/ronitsingh10/FineTune/issues/185), [#255](https://github.com/ronitsingh10/FineTune/issues/255), [#316](https://github.com/ronitsingh10/FineTune/issues/316), [#326](https://github.com/ronitsingh10/FineTune/issues/326)). No issue reports a system-wide `coreaudiod` wedge (searched 2026-09-24). On 2026-09-24 FineTune crashed 48 s after the loop began, in its window code rather than its audio path, so it may have been a victim that day rather than the trigger. Use the MacBook microphone when Bluetooth call routing is unstable.

**FineTune is quit as a test, not yet uninstalled** (2026-10-26). The fourth incident followed, so the 2026-09-24 trigger to remove it is met. But this time the tap owner could be FineTune or Granola (both create process taps), and quitting one is the test that tells them apart. It is not a login item, so it stays off across reboots until opened by hand. If AirPods calls run for a week without a wedge, uninstall it and move its `config/apps.conf` line to `config/apps-excluded.conf`; if a wedge recurs with FineTune off, Granola's tap is next.

## A watcher posts a notification when CoreAudio wedges

`coreaudio-watch` runs every 2 minutes from the `coreaudio-watch` LaunchAgent (`scripts/cleanup/setup_coreaudio_watch.sh`, deploy component `coreaudio-watch`, on by default on macOS). It reads crash and hang reports written since its last run, without touching CoreAudio, and probes with `reset-mac-media --check` only when a report blames `coreaudiod`, on every run while the state is wedged, or every 15 minutes as a backstop. It posts a notification when CoreAudio wedges, an hourly reminder while it stays wedged, one when it recovers, and one per new batch of media-daemon crash reports. State lives in `~/.local/state/coreaudio-watch/` and its log in `~/Library/Logs/com.user.coreaudio-watch.log`; `coreaudio-watch --dry-run` shows what a run would do. The notifications are Mac banners only, with no phone push.

## Diagnosis steps that worked, in order

1. `/bin/ls -lt ~/Library/Logs/DiagnosticReports | head` — a crash loop is visible in seconds.
2. `reset-mac-media --check` — the red/green verdict.
3. Only if both are clean, move on to network, display or per-app debugging.
