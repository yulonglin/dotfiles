// builtin-display — turn the MacBook's built-in screen off and on while the lid
// stays open, so the built-in keyboard and trackpad keep working with an
// external monitor. macOS then treats the external monitor as the only display:
// no windows or cursor are lost on a dark panel, unlike brightness zero.
//
// Mechanism: CGSConfigureDisplayEnabled, a private CoreGraphics call (SkyLight
// exports it as SLSConfigureDisplayEnabled), applied inside a normal
// CGBeginDisplayConfiguration transaction. It is the same call display utilities
// use for "disconnect display"; being private, any macOS update can break it.
// The change is committed .forSession, so logging out or rebooting always brings
// the screen back.
//
// Compiled by custom_bins/builtin-display on first run; see that file for usage.

import AppKit
import CoreGraphics
import Darwin
import Foundation
import IOKit

// MARK: output

let useColour: Bool = {
    guard isatty(STDOUT_FILENO) == 1 else { return false }
    let noColour = ProcessInfo.processInfo.environment["NO_COLOR"] ?? ""
    return noColour.isEmpty
}()

enum Style: String {
    case green = "32", yellow = "33", red = "31", bold = "1", dim = "2"
}

func paint(_ text: String, _ style: Style) -> String {
    useColour ? "\u{1B}[\(style.rawValue)m\(text)\u{1B}[0m" : text
}

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data("builtin-display: \(message)\n".utf8))
    exit(code)
}

// MARK: private API

typealias ConfigureEnabledFn = @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError

func loadConfigureEnabled() -> ConfigureEnabledFn? {
    let handles: [UnsafeMutableRawPointer?] = [
        dlopen(nil, RTLD_NOW),
        dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW),
    ]
    for handle in handles.compactMap({ $0 }) {
        for name in ["CGSConfigureDisplayEnabled", "SLSConfigureDisplayEnabled"] {
            if let sym = dlsym(handle, name) {
                return unsafeBitCast(sym, to: ConfigureEnabledFn.self)
            }
        }
    }
    return nil
}

// MARK: display queries

func displayList(_ getter: (UInt32, UnsafeMutablePointer<CGDirectDisplayID>?, UnsafeMutablePointer<UInt32>?) -> CGError) -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    guard getter(0, nil, &count) == .success, count > 0 else { return [] }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard getter(count, &ids, &count) == .success else { return [] }
    return Array(ids.prefix(Int(count)))
}

func onlineDisplays() -> [CGDirectDisplayID] { displayList(CGGetOnlineDisplayList) }

// The built-in panel's ID is remembered when it is turned off, because a
// disabled display can drop out of both the active and the online list.
let stateFile: URL = {
    let base = ProcessInfo.processInfo.environment["XDG_STATE_HOME"].map { URL(fileURLWithPath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/state")
    return base.appendingPathComponent("builtin-display/display-id")
}()

func savedBuiltinID() -> CGDirectDisplayID? {
    guard let text = try? String(contentsOf: stateFile, encoding: .utf8) else { return nil }
    return CGDirectDisplayID(text.trimmingCharacters(in: .whitespacesAndNewlines))
}

func saveBuiltinID(_ id: CGDirectDisplayID) {
    try? FileManager.default.createDirectory(at: stateFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? "\(id)\n".write(to: stateFile, atomically: true, encoding: .utf8)
}

// "On" means online, not active: a built-in screen mirroring an external one is
// online but not in the active list (measured 2026-11-18, macOS 26).
func onlineBuiltinID() -> CGDirectDisplayID? {
    onlineDisplays().first { CGDisplayIsBuiltin($0) != 0 }
}

func builtinIsOn() -> Bool { onlineBuiltinID() != nil }

// With the built-in disabled and the last real monitor unplugged, WindowServer
// does not report zero displays: it brings up a placeholder whose vendor and
// model read as ASCII "unkn" / "virt" (0x756E6B6E / 0x76697274), serial 0. It
// shows nothing, so it must not count as an external, or the watcher never sees
// "last external gone" and leaves the screen dark (seen 2026-11-19, macOS 26).
func isPlaceholder(_ id: CGDirectDisplayID) -> Bool {
    CGDisplayVendorNumber(id) == 0x756E_6B6E && CGDisplayModelNumber(id) == 0x7669_7274
}

func externals() -> [CGDirectDisplayID] {
    onlineDisplays().filter { CGDisplayIsBuiltin($0) == 0 && !isPlaceholder($0) }
}

// A closed lid also takes the built-in screen offline; read it so "off" is honest.
func lidClosed() -> Bool {
    let root = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
    guard root != 0 else { return false }
    defer { IOObjectRelease(root) }
    let value = IORegistryEntryCreateCFProperty(root, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0)
    return (value?.takeRetainedValue() as? Bool) ?? false
}

// Inside a sandbox that blocks WindowServer, every display list comes back empty.
func requireWindowServer() {
    if onlineDisplays().isEmpty {
        fail("cannot see any display; WindowServer is unreachable (run it outside a sandbox)")
    }
}

func describe(_ id: CGDirectDisplayID) -> String {
    let name = CGDisplayIsBuiltin(id) != 0 ? "built-in" : "external"
    let size = "\(CGDisplayPixelsWide(id))x\(CGDisplayPixelsHigh(id))"
    var notes: [String] = []
    if CGDisplayIsMain(id) != 0 { notes.append("main") }
    let primary = CGDisplayMirrorsDisplay(id)
    if primary != kCGNullDirectDisplay { notes.append("mirroring id=\(primary)") }
    let detail = ([size] + notes).joined(separator: " ")
    return "\(paint(name, .bold)) id=\(id) \(paint(detail, .dim))"
}

// MARK: actions

// Returns nil on success, else what went wrong. The watcher logs the error and
// keeps running; the one-shot commands exit on it. Retries, because applying a
// configuration while the previous one is still settling fails with CGError
// 1001 (seen 3 s after an `off`, 2026-11-18).
func trySetEnabled(_ id: CGDirectDisplayID, _ enabled: Bool) -> String? {
    var error: String?
    for attempt in 1...5 {
        error = setEnabledOnce(id, enabled)
        if error == nil { return nil }
        if attempt < 5 { sleep(1) }
    }
    return error
}

func setEnabledOnce(_ id: CGDirectDisplayID, _ enabled: Bool) -> String? {
    guard let configure = loadConfigureEnabled() else {
        return "this macOS no longer exports CGSConfigureDisplayEnabled; the private API is gone"
    }
    var config: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&config) == .success, let config else {
        return "could not begin a display configuration"
    }
    let err = configure(config, id, enabled)
    guard err == .success else {
        CGCancelDisplayConfiguration(config)
        return "CGSConfigureDisplayEnabled(\(id), \(enabled)) returned CGError \(err.rawValue)"
    }
    let done = CGCompleteDisplayConfiguration(config, .forSession)
    guard done == .success else {
        return "could not apply the display configuration (CGError \(done.rawValue))"
    }
    return nil
}

func setEnabled(_ id: CGDirectDisplayID, _ enabled: Bool) {
    if let error = trySetEnabled(id, enabled) { fail(error) }
}

func waitFor(_ condition: () -> Bool, seconds: Double = 5) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if condition() { return true }
        usleep(200_000)
    }
    return condition()
}

func turnOff() {
    requireWindowServer()
    guard let id = onlineBuiltinID() else {
        let why = lidClosed() ? "the lid is closed" : "already off"
        print("built-in screen: \(paint("off", .yellow)) (\(why))")
        return
    }
    guard !externals().isEmpty else {
        fail("refusing: no external display is connected, so turning the built-in screen off would leave nothing to see")
    }
    saveBuiltinID(id)
    setEnabled(id, false)
    if waitFor({ !builtinIsOn() }) {
        print("built-in screen: \(paint("off", .green)) — run `builtin-display on` (or log out) to bring it back")
    } else {
        fail("the call was accepted but the built-in screen is still listed online; if it went dark, `builtin-display on` restores it")
    }
}

// Always sends the enable call, even when detection says the screen is on:
// whether a disabled panel leaves the online list is not something to bet the
// way back on. Enabling an already enabled display is a no-op.
func turnOn() {
    requireWindowServer()
    if lidClosed() {
        fail("the lid is closed; open it first")
    }
    guard let id = savedBuiltinID() ?? onlineBuiltinID() else {
        fail("no remembered built-in display ID; log out and back in to restore the screen")
    }
    setEnabled(id, true)
    if waitFor({ builtinIsOn() }) {
        print("built-in screen: \(paint("on", .green))")
    } else {
        fail("the call succeeded but the built-in screen did not come back; close and reopen the lid, or log out")
    }
}

func status() {
    requireWindowServer()
    if builtinIsOn() {
        print("built-in screen: \(paint("on", .green))")
    } else {
        let why = lidClosed() ? "lid closed" : "turned off"
        print("built-in screen: \(paint("off", .yellow)) (\(why))")
    }
    for id in onlineDisplays() { print("  \(describe(id))") }
}

// Turn off, wait, turn back on. Ctrl-C or SIGTERM during the wait also restores.
// Never exits between the disable and the enable, whatever detection reports;
// it prints what detection saw, which is the point of a first test.
func trial(seconds: UInt32) {
    requireWindowServer()
    guard let id = onlineBuiltinID() else { fail("the built-in screen is not online (lid closed or already off)") }
    guard !externals().isEmpty else { fail("refusing: no external display is connected") }
    saveBuiltinID(id)
    if let error = trySetEnabled(id, false) { fail(error) }
    let gone = waitFor({ !builtinIsOn() }, seconds: 3)
    print("disable sent; built-in \(gone ? paint("left the online list", .green) : paint("still listed online", .yellow))")
    for sig in [SIGINT, SIGTERM] {
        signal(sig) { _ in
            if let id = savedBuiltinID(), let configure = loadConfigureEnabled() {
                var config: CGDisplayConfigRef?
                if CGBeginDisplayConfiguration(&config) == .success, let config {
                    _ = configure(config, id, true)
                    _ = CGCompleteDisplayConfiguration(config, .forSession)
                }
            }
            exit(130)
        }
    }
    print(paint("restoring in \(seconds)s (Ctrl-C restores now)", .dim))
    sleep(seconds)
    if let error = trySetEnabled(id, true) {
        fail("re-enable FAILED (\(error)); log out to restore the screen")
    }
    let back = waitFor({ builtinIsOn() })
    print("enable sent; built-in \(back ? paint("back online", .green) : paint("not listed online — if it is still dark, log out", .red))")
    if !back { exit(1) }
}

// MARK: heal

// One-shot safety net, run by launchd every 10 s as a fresh process (the
// com.user.builtin-display-heal agent). It does not trust the long-lived
// watcher: on 2026-11-20 the watcher, 17 h old, never saw an unplug and left
// the screen dark, while a fresh `builtin-display on` read the state right at
// once. Silent when there is nothing to do; logs only when it has to act,
// which means the watcher missed an unplug.
func heal() {
    // An empty list means no WindowServer access (a sandbox), not "no display".
    guard !onlineDisplays().isEmpty else { return }
    guard externals().isEmpty, !builtinIsOn(), !lidClosed() else { return }
    let id = savedBuiltinID() ?? 1
    if let error = trySetEnabled(id, true) {
        log("heal: no external display and built-in off; turning it on FAILED: \(error)")
        exit(1)
    }
    log("heal: no external display and built-in off; built-in screen on (the watcher missed this)")
}

// MARK: watcher

// Run by the login agent (`builtin-display auto on`). It acts only on two
// transitions, so a manual choice sticks until the next plug event:
//   - an external display that was not connected before appears -> screen off
//   - no external display is present (lid open, built-in off) -> screen back
//     on. This one is checked on every poll, not only on the unplug event, so
//     you are never left with no visible screen
// `builtin-display on` while the Studio Display stays connected is therefore
// left alone. Reconfiguration events arrive in bursts, so each burst is handled
// once, 2 s after it settles.

// Externals are keyed by vendor/model/serial, not CGDirectDisplayID, in case a
// reconfiguration (such as re-enabling the built-in) renumbers them and makes an
// already connected monitor look new.
var knownExternals: Set<String> = []
var watchActivity: NSObjectProtocol?
var pendingCheck: DispatchWorkItem?

func hardwareKey(_ id: CGDirectDisplayID) -> String {
    "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
}

func log(_ message: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    print("\(stamp) \(message)")
    fflush(stdout)
}

var lastSnapshot = ""

func reconcile() {
    let now = Set(externals().map(hardwareKey))
    let added = now.subtracting(knownExternals)
    let snapshot = "externals=\(now.sorted()) builtin=\(builtinIsOn() ? "on" : "off") lid=\(lidClosed() ? "closed" : "open")"
    if snapshot != lastSnapshot {
        log("state: \(snapshot)")
        lastSnapshot = snapshot
    }
    defer { knownExternals = now }

    if !added.isEmpty, let id = onlineBuiltinID(), !lidClosed() {
        saveBuiltinID(id)
        if let error = trySetEnabled(id, false) {
            log("external display \(added.sorted()) connected; turning built-in off FAILED: \(error)")
        } else {
            log("external display \(added.sorted()) connected; built-in screen off")
        }
    } else if now.isEmpty, !builtinIsOn(), !lidClosed() {
        // A state rule, not a transition: whenever no real external is present,
        // the lid is open and the built-in is off, turn it on. The 2 s poll
        // re-checks it, so a missed unplug event, a placeholder display, an
        // agent restart while unplugged, or a failed enable all heal on the
        // next tick instead of leaving the screen dark. ID 1 is the built-in's
        // usual ID on Apple silicon, a fallback only if the state file is gone.
        let id = savedBuiltinID() ?? 1
        if let error = trySetEnabled(id, true) {
            log("no external display; turning built-in on FAILED (retrying next poll): \(error)")
        } else {
            log("no external display; built-in screen on")
        }
    }
}

func scheduleReconcile() {
    pendingCheck?.cancel()
    let item = DispatchWorkItem { reconcile() }
    pendingCheck = item
    DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: item)
}

func watch() {
    // At login the Studio Display may already be connected: knownExternals
    // starts empty, so the first reconcile treats it as newly connected.
    log("watching for display changes")
    let callback: CGDisplayReconfigurationCallBack = { _, flags, _ in
        if flags.contains(.beginConfigurationFlag) { return }
        DispatchQueue.main.async { scheduleReconcile() }
    }
    CGDisplayRegisterReconfigurationCallback(callback, nil)
    scheduleReconcile()
    // A bare command-line process never saw changes made elsewhere (unplugging
    // the monitor, or `on` from another shell): not through the callback, and
    // not by re-reading the display list, which stays cached until WindowServer
    // events are processed. Measured 2026-11-18 under dispatchMain and
    // CFRunLoopRun. Running as a faceless NSApplication (no Dock icon, no menu)
    // gives the process a real WindowServer connection; the 2 s poll is a
    // backstop in case a notification is missed.
    NSApplication.shared.setActivationPolicy(.prohibited)
    // A faceless app is a prime App Nap candidate, and App Nap throttles timers
    // and event delivery. Suspected (not proven) cause of the 2026-11-20 miss.
    // The activity token must live as long as the process, so it is kept global.
    watchActivity = ProcessInfo.processInfo.beginActivity(
        options: .userInitiatedAllowingIdleSystemSleep,
        reason: "builtin-display watches for display plug events"
    )
    NotificationCenter.default.addObserver(
        forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
    ) { _ in scheduleReconcile() }
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + 2, repeating: 2)
    timer.setEventHandler { reconcile() }
    timer.resume()
    NSApplication.shared.run()
}

let usage = """
usage: builtin-display <command>

Turn the MacBook's built-in screen off while the lid stays open, so the
built-in keyboard and trackpad keep working with an external display.

commands:
  status          show whether the built-in screen is on, and the active displays
  off             turn the built-in screen off (refuses unless an external display is active)
  on              turn the built-in screen back on
  toggle          off if on, on if off (bind this to a hotkey)
  try [SECONDS]   turn off, then back on after SECONDS (default 10) — a safe first test
  auto on|off|status
                  login agent that turns the screen off whenever an external display
                  connects, and back on when the last one is unplugged. `on` or
                  `toggle` still work while it runs; your choice holds until the
                  next plug event
  watch           what the agent runs (foreground; logs each action)
  heal            one-shot: turn the built-in on if no external display is
                  present and the lid is open; `auto on` runs it every 10 s

Uses a private macOS API, so an update can break it. The change lasts for the
login session: logging out or rebooting always restores the screen.
Agent log: ~/Library/Logs/builtin-display.log
exit codes: 0 ok, 1 failed, 2 usage error
"""

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "status": status()
case "off": turnOff()
case "on": turnOn()
case "toggle": builtinIsOn() ? turnOff() : turnOn()
case "try":
    let seconds = args.count > 1 ? UInt32(args[1]) : 10
    guard let seconds, seconds > 0 else { fail("try takes a positive number of seconds", code: 2) }
    trial(seconds: seconds)
case "watch": watch()
case "heal": heal()
case "-h", "--help", "help": print(usage)
case nil: print(usage); exit(2)
default: fail("unknown command '\(args[0])'\n\(usage)", code: 2)
}
