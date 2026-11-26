# OBS Focusmate Feed Freezes

When the Focusmate virtual camera looks frozen, OBS itself is usually still running. One of its inputs has stopped. `obs-watchdog` recovers both known cases on its own; this page says how to tell them apart and what to capture when a new one appears.

## Two inputs froze on 2026-11-25 while OBS kept rendering

The OBS log for that session (`~/Library/Application Support/obs-studio/logs/2026-11-25 14-01-37.txt`) shows 861,165 frames sent to the virtual camera with 13 late, and a clean quit at 22:00:44. The freezes were in the inputs:

| Time | Input | Cause | Evidence |
|---|---|---|---|
| 20:37:40 | Screen-capture overlay | Display sleep. macOS stops the ScreenCaptureKit stream and OBS never restarts it | OBS log `[ mac-screencapture ]: Stream stopped as no capture source was not found.` in the same second as `pmset -g log` "Display is turned off"; unified log `Stopping stream due to stream frameStatus=5` after `kCGSDisplayWillSleep` |
| 21:31:37 | Studio Display Camera | Unknown. The video-effects thread inside OBS (Portrait / Studio Light, run on the Neural Engine) made its last Neural Engine request and never logged again; no display event, no error | Per-second `com.apple.cmio` "effect duration" lines from OBS stop; kernel `AppleH16ANEInterface` lines on the same thread stop |

The earlier restart that day, at 14:01, followed the same camera signature at 13:58:24, which was a display wake. Both times the fix was quitting and relaunching OBS.

## obs-watchdog restarts the screen capture and, for a frozen camera, OBS

`custom_bins/obs-watchdog` runs every 20 seconds from the `com.user.obs-watchdog` LaunchAgent, which `deploy.sh --obs` installs through `scripts/cleanup/setup_obs_watchdog.sh`. It talks to OBS over obs-websocket, which `obs-watchdog --setup` enables with password auth; OBS reads that setting only at start, so restart OBS once after setup.

- **Screen:** when the newest OBS log has a `Stream stopped` line it has not handled and the display is awake, it presses the screen source's own "Restart capture" button (`reactivate_capture`). Pressing it when nothing failed is a no-op in OBS.
- **Camera:** while the virtual camera is on, it screenshots each visible camera source. A frame that is bit-identical on three checks in a row is frozen, since a live sensor never repeats a frame exactly. It saves `sample OBS 3` to `~/.local/state/obs-watchdog/` and restarts OBS through `obs-start`. Near-uniform frames (lens covered, dark room) are skipped, and it restarts at most once per 15 minutes, notifying instead after that.

```
obs-watchdog --status    # websocket, connection, cameras watched, last actions
obs-watchdog --dry-run   # what one check would do
```

Its log is `~/Library/Logs/com.user.obs-watchdog.log`.

## The camera cause is still open

Two tests narrow it down:

- **Video effects off.** Turn off Portrait and Studio Light for OBS in Control Center (Video Effects, with OBS in front). If camera freezes stop, the effects step was the cause.
- **Thread samples.** Each automatic restart saves a `sample-*.txt`. A camera thread blocked in `ANE` or `VideoEffects` frames points at macOS video effects; an idle capture queue points at the camera or its driver.
