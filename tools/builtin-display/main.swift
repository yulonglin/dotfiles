// builtin-display — turn the MacBook's built-in screen off and on while the lid
// stays open, so the built-in keyboard and trackpad keep working with an
// external monitor. macOS then treats the external monitor as the only display:
// no windows or cursor are lost on a dark panel, unlike brightness zero.
//
// Mechanism: CGSConfigureDisplayEnabled, a private CoreGraphics call (SkyLight
// exports it as SLSConfigureDisplayEnabled), applied in a CGBeginDisplayConfiguration
// transaction committed `.forAppOnly`, as LightsOut does (AlonX2/LightsOut,
// DisplaysViewModel.swift). Only one long-lived "holder" process ever turns the
// screen off, and it turns the screen back on itself before it exits: the same
// private call with `true`, from the same process, then the public
// CGRestorePermanentDisplayConfiguration. Apple documents that `.forAppOnly`
// changes revert when the process exits; whether that also holds for the private
// call (so a killed holder still brings the screen back) is NOT verified yet.
//
// Why not `.forSession` (the first version, 2026-11-18): there a later, separate
// process sent the enable call, and on 2026-11-22 (macOS 26, M5 Pro) it returned
// success twice while the panel stayed dark. Lid cycles did not help (the log
// shows several); the screen came back only after the monitor disconnected.
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

func log(_ message: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    print("\(stamp) \(message)")
    fflush(stdout)
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

// "On" means online, not active: a built-in screen mirroring an external one is
// online but not in the active list (measured 2026-11-18, macOS 26).
func onlineBuiltinID() -> CGDirectDisplayID? {
    onlineDisplays().first { CGDisplayIsBuiltin($0) != 0 }
}

func builtinIsOn() -> Bool { onlineBuiltinID() != nil }

// With the built-in disabled and the last real monitor unplugged, WindowServer
// does not report zero displays: it brings up a placeholder whose vendor and
// model read as ASCII "unkn" / "virt" (0x756E6B6E / 0x76697274), serial 0. It
// shows nothing, so it must not count as an external (seen 2026-11-19, macOS 26).
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

func waitFor(_ condition: () -> Bool, seconds: Double = 5) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if condition() { return true }
        usleep(200_000)
    }
    return condition()
}

// MARK: holder bookkeeping

let stateDir: URL = {
    let base = ProcessInfo.processInfo.environment["XDG_STATE_HOME"].map { URL(fileURLWithPath: $0) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/state")
    return base.appendingPathComponent("builtin-display")
}()
let pidFile = stateDir.appendingPathComponent("holder.pid")
let logFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/builtin-display.log")

func processName(_ pid: pid_t) -> String {
    var buf = [CChar](repeating: 0, count: 256)
    return proc_name(pid, &buf, UInt32(buf.count)) > 0 ? String(cString: buf) : ""
}

// The running holder's PID, or nil. Checks the name too, so a stale PID file
// whose number the system has reused never gets someone else's process killed.
func holderPID() -> pid_t? {
    guard let text = try? String(contentsOf: pidFile, encoding: .utf8),
          let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 0,
          kill(pid, 0) == 0, processName(pid) == "builtin-display"
    else { return nil }
    return pid
}

// Start `builtin-display hold` as its own process, logging to the agent log.
// It outlives this process. Whether launchd's bootout of the watcher also ends
// it is not verified; `builtin-display on` always does.
func spawnHolder() -> String? {
    guard let exe = Bundle.main.executableURL else { return "cannot find own executable" }
    try? FileManager.default.createDirectory(at: logFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    if !FileManager.default.fileExists(atPath: logFile.path) {
        FileManager.default.createFile(atPath: logFile.path, contents: nil)
    }
    let task = Process()
    task.executableURL = exe
    task.arguments = ["hold"]
    task.standardInput = FileHandle.nullDevice
    if let out = try? FileHandle(forWritingTo: logFile) {
        out.seekToEndOfFile()
        task.standardOutput = out
        task.standardError = out
    }
    do { try task.run() } catch { return "could not start the holder: \(error.localizedDescription)" }
    return nil
}

// MARK: restore paths

// Fallbacks for when no holder is left but the panel is still dark: first the
// public reset, then the old private enable, which is what a panel turned off
// `.forSession` by the first version of this tool needs.
func forceRestore() {
    CGRestorePermanentDisplayConfiguration()
    if waitFor({ builtinIsOn() }, seconds: 3) { return }
    guard let configure = loadConfigureEnabled() else { return }
    var config: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&config) == .success, let config else { return }
    // ID 1 is the built-in's usual ID on Apple silicon; a dark panel is not listed.
    guard configure(config, onlineBuiltinID() ?? 1, true) == .success else {
        CGCancelDisplayConfiguration(config)
        return
    }
    _ = CGCompleteDisplayConfiguration(config, .forSession)
}

// MARK: hold

// The only code that turns the screen off. Stays running while it holds the
// change, and exits when any of these happen, which brings the screen back:
//   - no real external display is present (checked every second)
//   - SIGTERM / SIGINT / SIGHUP (`on`, Ctrl-C, launchd bootout)
//   - the optional time limit runs out (`try`)
// It runs as a faceless NSApplication because a bare command-line process does
// not see display changes made elsewhere (measured 2026-11-18).
var holdActivity: NSObjectProtocol?
var signalSources: [DispatchSourceSignal] = []
var holdTimer: DispatchSourceTimer?

var heldID: CGDirectDisplayID = 1
var emptyPolls = 0

// Turn the panel back on from this same process (what LightsOut's reconnect
// does), then the public reset, then exit. Exiting may revert it as well.
func releaseHold(_ why: String) -> Never {
    log("hold: \(why); releasing, built-in screen back on")
    if holderPID() == getpid() { try? FileManager.default.removeItem(at: pidFile) }
    if let configure = loadConfigureEnabled() {
        var config: CGDisplayConfigRef?
        if CGBeginDisplayConfiguration(&config) == .success, let config {
            if configure(config, heldID, true) == .success {
                _ = CGCompleteDisplayConfiguration(config, .forAppOnly)
            } else {
                CGCancelDisplayConfiguration(config)
            }
        }
    }
    CGRestorePermanentDisplayConfiguration()
    _ = waitFor({ builtinIsOn() }, seconds: 3)
    log("hold: built-in \(builtinIsOn() ? "back online" : "still offline after release")")
    exit(0)
}

func hold(seconds: Double?) -> Never {
    requireWindowServer()
    if let pid = holderPID() { fail("already off (holder pid \(pid))") }
    guard let id = onlineBuiltinID() else {
        fail(lidClosed() ? "the lid is closed" : "the built-in screen is not online")
    }
    guard !externals().isEmpty else {
        fail("refusing: no external display is connected, so turning the built-in screen off would leave nothing to see")
    }
    guard let configure = loadConfigureEnabled() else {
        fail("this macOS no longer exports CGSConfigureDisplayEnabled; the private API is gone")
    }
    var config: CGDisplayConfigRef?
    guard CGBeginDisplayConfiguration(&config) == .success, let config else {
        fail("could not begin a display configuration")
    }
    let err = configure(config, id, false)
    guard err == .success else {
        CGCancelDisplayConfiguration(config)
        fail("CGSConfigureDisplayEnabled(\(id), false) returned CGError \(err.rawValue)")
    }
    let done = CGCompleteDisplayConfiguration(config, .forAppOnly)
    guard done == .success else { fail("could not apply the display configuration (CGError \(done.rawValue))") }
    heldID = id

    try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
    try? "\(getpid())\n".write(to: pidFile, atomically: true, encoding: .utf8)
    log("hold: built-in screen off (pid \(getpid()))")

    for sig in [SIGTERM, SIGINT, SIGHUP] {
        signal(sig, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
        source.setEventHandler { releaseHold("signal \(sig)") }
        source.resume()
        signalSources.append(source)
    }
    NSApplication.shared.setActivationPolicy(.prohibited)
    holdActivity = ProcessInfo.processInfo.beginActivity(
        options: .userInitiatedAllowingIdleSystemSleep, reason: "builtin-display holds the built-in screen off"
    )
    let started = Date()
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + 1, repeating: 1)
    timer.setEventHandler {
        // Three empty reads in a row (3 s), so one bad read cannot flap the screen.
        emptyPolls = externals().isEmpty ? emptyPolls + 1 : 0
        if emptyPolls >= 3 { releaseHold("no external display") }
        if let seconds, Date().timeIntervalSince(started) >= seconds { releaseHold("\(Int(seconds))s trial over") }
    }
    timer.resume()
    holdTimer = timer
    NSApplication.shared.run()
    exit(0)
}

// MARK: one-shot commands

func status() {
    requireWindowServer()
    if builtinIsOn() {
        print("built-in screen: \(paint("on", .green))")
    } else {
        let why = lidClosed() ? "lid closed" : (holderPID().map { "held off by pid \($0)" } ?? "off, no holder running")
        print("built-in screen: \(paint("off", .yellow)) (\(why))")
    }
    for id in onlineDisplays() { print("  \(describe(id))") }
}

func turnOff() {
    requireWindowServer()
    if let pid = holderPID() {
        print("built-in screen: \(paint("off", .yellow)) (already held by pid \(pid))")
        return
    }
    guard builtinIsOn() else { fail(lidClosed() ? "the lid is closed" : "the built-in screen is already offline") }
    guard !externals().isEmpty else {
        fail("refusing: no external display is connected, so turning the built-in screen off would leave nothing to see")
    }
    if let error = spawnHolder() { fail(error) }
    if waitFor({ !builtinIsOn() }) {
        print("built-in screen: \(paint("off", .green)) — `builtin-display on`, unplugging the monitor, or ending the holder brings it back")
    } else {
        fail("the holder did not turn the screen off; see \(logFile.path)")
    }
}

func turnOn() {
    requireWindowServer()
    if lidClosed() { fail("the lid is closed; open it first") }
    if let pid = holderPID() {
        kill(pid, SIGTERM)
        if waitFor({ builtinIsOn() }) {
            print("built-in screen: \(paint("on", .green))")
            return
        }
        kill(pid, SIGKILL)
    }
    if !builtinIsOn() { forceRestore() }
    if waitFor({ builtinIsOn() }) {
        print("built-in screen: \(paint("on", .green))")
    } else {
        fail("the built-in screen did not come back; unplug the external monitor, or log out")
    }
}

// MARK: heal

// One-shot safety net, run by launchd every 2 s as a fresh process (the
// com.user.builtin-display-heal agent). The holder already exits when the last
// external goes; this covers a holder that hangs, and a panel left dark with no
// holder at all (such as one turned off by the first version). Silent when
// there is nothing to do.
func heal() {
    // An empty list means no WindowServer access (a sandbox), not "no display".
    guard !onlineDisplays().isEmpty else { return }
    guard externals().isEmpty, !builtinIsOn(), !lidClosed() else { return }
    if let pid = holderPID() {
        kill(pid, SIGKILL)
        log("heal: no external display but holder \(pid) still running; killed it")
        if waitFor({ builtinIsOn() }, seconds: 3) { return }
    }
    forceRestore()
    log("heal: no external display and built-in off; restore \(builtinIsOn() ? "worked" : "FAILED")")
}

// MARK: watcher

// Run by the login agent (`builtin-display auto on`). It acts on one
// transition: an external display that was not connected before appears, with
// the lid open and the built-in on -> start a holder. Turning the screen back on
// at unplug is the holder's job, so `builtin-display on` while the monitor stays
// connected sticks until the next plug event. Reconfiguration events arrive in
// bursts, so each burst is handled once, 2 s after it settles.

// Externals are keyed by vendor/model/serial, not CGDirectDisplayID, in case a
// reconfiguration renumbers them and makes a connected monitor look new.
var knownExternals: Set<String> = []
var watchActivity: NSObjectProtocol?
var pendingCheck: DispatchWorkItem?
var lastSnapshot = ""

func hardwareKey(_ id: CGDirectDisplayID) -> String {
    "\(CGDisplayVendorNumber(id))-\(CGDisplayModelNumber(id))-\(CGDisplaySerialNumber(id))"
}

func reconcile() {
    let now = Set(externals().map(hardwareKey))
    let added = now.subtracting(knownExternals)
    let holder = holderPID().map(String.init) ?? "none"
    let snapshot = "externals=\(now.sorted()) builtin=\(builtinIsOn() ? "on" : "off") lid=\(lidClosed() ? "closed" : "open") holder=\(holder)"
    if snapshot != lastSnapshot {
        log("state: \(snapshot)")
        lastSnapshot = snapshot
    }
    defer { knownExternals = now }
    guard !added.isEmpty, builtinIsOn(), !lidClosed(), holderPID() == nil else { return }
    if let error = spawnHolder() {
        log("external display \(added.sorted()) connected; starting holder FAILED: \(error)")
    } else {
        log("external display \(added.sorted()) connected; holder started")
    }
}

func scheduleReconcile() {
    pendingCheck?.cancel()
    let item = DispatchWorkItem { reconcile() }
    pendingCheck = item
    DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: item)
}

func watch() {
    // At login the monitor may already be connected: knownExternals starts
    // empty, so the first reconcile treats it as newly connected.
    log("watching for display changes")
    let callback: CGDisplayReconfigurationCallBack = { _, flags, _ in
        if flags.contains(.beginConfigurationFlag) { return }
        DispatchQueue.main.async { scheduleReconcile() }
    }
    CGDisplayRegisterReconfigurationCallback(callback, nil)
    scheduleReconcile()
    // A faceless NSApplication gets a real WindowServer connection, so it sees
    // changes made elsewhere; App Nap is held off because it throttles timers.
    NSApplication.shared.setActivationPolicy(.prohibited)
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
  status          show whether the built-in screen is on, and the online displays
  off             turn the built-in screen off (refuses unless an external display is present)
  on              turn the built-in screen back on
  toggle          off if on, on if off (bind this to a hotkey)
  try [SECONDS]   hold the screen off for SECONDS (default 10) in the foreground,
                  then exit, which must bring it back: the first test on a new macOS
  auto on|off|status
                  login agent that turns the screen off whenever an external display
                  connects; `on` or `toggle` still work while it runs
  hold            what `off` starts in the background: keeps the screen off while it
                  runs, and exits (screen back) when no external display is left
  watch           what the agent runs (foreground; logs each action)
  heal            one-shot safety net that `auto on` runs every 2 s

The screen stays off only while the holder process runs: `on`, Ctrl-C,
unplugging the monitor, logging out or rebooting brings it back. Whether a
crashed or killed holder also brings it back is not verified yet.
Uses a private macOS API, so an update can break it.
Log: ~/Library/Logs/builtin-display.log
exit codes: 0 ok, 1 failed, 2 usage error
"""

// MARK: main

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "status": status()
case "off": turnOff()
case "on": turnOn()
case "toggle": if holderPID() != nil || !builtinIsOn() { turnOn() } else { turnOff() }
case "try":
    let seconds = args.count > 1 ? Double(args[1]) : 10
    guard let seconds, seconds >= 1, seconds <= 120 else { fail("try takes SECONDS between 1 and 120", code: 2) }
    print(paint("holding the built-in screen off for \(Int(seconds))s; it must come back by itself (fallback: `builtin-display on` from the external monitor, unplug it, or log out)", .dim))
    hold(seconds: seconds)
case "hold": hold(seconds: nil)
case "watch": watch()
case "heal": heal()
case "-h", "--help", "help": print(usage)
case nil: print(usage); exit(2)
default: fail("unknown command '\(args[0])'\n\(usage)", code: 2)
}
