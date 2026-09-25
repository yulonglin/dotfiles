# macOS Media Wedge: Several Apps Hang While CPU Stays Low

When several unrelated apps stop working at once and CPU, memory and network all look healthy, check the audio stack first. A crash-looping `avconferenced` leaves `coreaudiod` wedged, and every app that touches audio, camera or contacts then blocks in synchronous IPC. Flat resource graphs are the signature of this wedge, not evidence against it. Run `reset-mac-media --check` (read-only, about a second), then `reset-mac-media` to fix it without a reboot.

## The symptoms look like a network or display fault

On 2026-09-24 the first symptoms were read as a network problem and cost about 15 minutes on the wrong lead. Any of these, together, points here:

- Safari and Chrome tabs do not load, while `curl`, `ping` and DNS from the terminal are fast. Both browsers' network processes hold only CLOSED sockets.
- An Electron app (Spark) launches, restores its windows and then shows nothing, with no network sockets.
- FaceTime, Spotify or other audio apps freeze; the UI feels stuck.
- NordVPN's Shield extension logs `Failed to talk to secd after 4 attempts` every few seconds. This is a downstream symptom: it stopped as soon as the media daemons restarted. Killing Shield does nothing, because launchd respawns a system extension at once.
- `~/Library/Logs/DiagnosticReports` holds a run of `avconferenced-*.ips` files a few seconds to minutes apart.

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

It needs administrator authentication and interrupts audio, video and calls for a moment. Apps that were blocked recover on their own. Brew-upgraded apps that were running during the upgrade (see below) should be quit and relaunched as well. If the helper is not at hand, this is the minimal equivalent:

```
sudo killall -9 \
  coreaudiod \
  audiomxd \
  avconferenced
```

If neither clears it, reboot. A normal restart can hang for over ten minutes because frozen apps cannot quit (2026-08-24), so be ready to hold the power button.

## Three incidents share one crash but not one trigger

Every incident has the same crash site: `avconferenced` terminating itself from `+[VCXPCConnection selfTerminateDueToTimeout:]` on an XPC call timeout, repeated seconds to minutes apart.

| Date | What happened just before | Other crash | Fixed by |
|---|---|---|---|
| 2026-08-24 | FaceTime call with a broken peer; Alfred's audio-device switcher crashed on a vanished CoreAudio device | `audiomxd` abort | Hard reboot |
| 2026-09-22 | AirPods broke CoreAudio's Bluetooth route before a call (session notes; verification was left pending) | FineTune suspected | `killall` of the media daemons |
| 2026-09-24 | A cask upgrade quit or replaced 15 running apps from 17:04:00 (AlDente and Alfred first); first `avconferenced` crash at 17:04:28 | FineTune crashed 17:05:16 | `killall` of the media daemons |

On 2026-09-24 the FaceTime call ended at about 17:03, one minute before the upgrade began, and `avconferenced` was still logging RTCP timeouts from its teardown at 17:03:08. NordVPN Shield's `secd` errors had begun at 15:59:29, the second the camera came on for that call. So brew quit AlDente and Alfred while the call was still being torn down, on a stack that may already have been strained; the upgrade guard alone might not have prevented it.

A call is present in all three incidents: during it on 2026-08-24, just before it on 2026-09-22, and in its teardown on 2026-09-24. That is the strongest common factor.

The other common thread is a sudden change under CoreAudio's feet — a device vanishing, or a running app's bundle disappearing — with a third-party CoreAudio hook (Alfred's switcher, then FineTune) present each time. That link is a pattern across three cases, not a proven cause. Which bundle swap set off the 2026-09-24 loop is unproven: AlDente, Alfred, Codex and Conductor were replaced in the 28 seconds before it, and Discord and Claude were not running.

## Prevention: skip running apps on upgrade, and limit FineTune

A cask upgrade takes a running app away mid-session. Casks that declare an uninstall `quit` stanza (AlDente, Alfred, Spark, WhatsApp, superwhisper, VS Code and most others here) are quit by Homebrew; the rest (Chrome, Cursor, Conductor, RemNote) have their bundle swapped under the live process. Two guards now skip running apps:

- **Interactive:** a bare `brew upgrade` (zsh wrapper in `config/aliases/brew.sh`) lists outdated apps that are running, marks the ones holding a live audio session, and offers to skip them. It runs `reset-mac-media --check --since 15` afterwards. `command brew upgrade` bypasses the wrapper; an upgrade that names packages passes straight through.
- **Unattended:** the weekly `update-packages` run upgrades formulae and only the casks whose app is not running, logs the ones it skipped, and runs the same health check. The cost: an app that is always open (Telegram, Dropbox, ChatGPT, Tailscale) is never upgraded by this run and relies on its own updater. The weekly job is not installed on this Mac as of 2026-09-24.

All 15 casks upgraded on 2026-09-24 declare `auto_updates`, which Homebrew 7 skips unless the upgrade is greedy (`--greedy` or `HOMEBREW_UPGRADE_GREEDY`). The only upgrades in shell history that day are plain `brew upgrade`, and nothing on this Mac sets greedy mode, so how they were upgraded is unexplained. Since these apps update themselves, the simplest prevention is to not run greedy upgrades at all. The wrapper honours `HOMEBREW_UPGRADE_GREEDY` when it is set.

Both use `brew-running-casks`, which maps each outdated cask to its `.app`, matches running processes by executable path, and reads `pmset -g assertions` to flag audio use. Run it directly to see what an upgrade would touch:

```bash
brew-running-casks            # running outdated casks: token, app, pids, audio flag
brew-running-casks --greedy   # include casks that update themselves
```

**Wait a few minutes after a call ends before running `brew upgrade`**, and do not start one during a call.

**Add FaceTime to FineTune's ignore list** (decided 2026-09-24). FineTune's GitHub issues document friction with calls specifically, not a general fault: about ten FaceTime reports, five still open, where FineTune's audio tap fights FaceTime's voice-processing mode and leaves call audio near-silent or crackling ([#113](https://github.com/ronitsingh10/FineTune/issues/113), [#156](https://github.com/ronitsingh10/FineTune/issues/156), [#262](https://github.com/ronitsingh10/FineTune/issues/262)), plus a cluster on AirPods and Bluetooth routing ([#185](https://github.com/ronitsingh10/FineTune/issues/185), [#255](https://github.com/ronitsingh10/FineTune/issues/255), [#316](https://github.com/ronitsingh10/FineTune/issues/316), [#326](https://github.com/ronitsingh10/FineTune/issues/326)). No issue reports a system-wide `coreaudiod` wedge (searched 2026-09-24). On 2026-09-24 FineTune crashed 48 s after the loop began, in its window code rather than its audio path, so it may have been a victim that day rather than the trigger. Use the MacBook microphone when Bluetooth call routing is unstable, and remove FineTune if a fourth incident follows.

## Diagnosis steps that worked, in order

1. `/bin/ls -lt ~/Library/Logs/DiagnosticReports | head` — a crash loop is visible in seconds.
2. `reset-mac-media --check` — the red/green verdict.
3. Only if both are clean, move on to network, display or per-app debugging.
