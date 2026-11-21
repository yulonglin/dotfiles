// Focus Tick: the launcher that the once-a-minute launchd job runs, so macOS has a
// stable app to hold responsible for `focus tick`.
//
// The tick reads ScreenZen's group container, and macOS 15+ asks the responsible
// process before it reads another app's data. Under launchd the responsible process
// was `uv` (the shebang of custom_bins/focus). Homebrew's uv is ad-hoc signed and
// each upgrade puts it at a new Cellar path, so a grant (App Data or Full Disk
// Access) stopped matching at the next `brew upgrade uv` and the prompt came back
// every minute. Inside this bundle the grant attaches to com.yulonglin.focus.tick,
// and the children it spawns (uv, python) inherit it as their responsible process.
//
// Usage: Focus Tick PROGRAM [ARGS...]: runs PROGRAM with ARGS, with the same
// environment and stdio, and exits with its status. `focus install-agent` builds,
// signs and installs the bundle; see build_tick_app in custom_bins/focus.
import Foundation

let args = Array(CommandLine.arguments.dropFirst())
guard let program = args.first else {
    FileHandle.standardError.write("usage: focus-tick PROGRAM [ARGS...]\n".data(using: .utf8)!)
    exit(64)
}
let child = Process()
child.executableURL = URL(fileURLWithPath: program)
child.arguments = Array(args.dropFirst())
do {
    try child.run()
} catch {
    FileHandle.standardError.write("focus-tick: cannot run \(program): \(error)\n".data(using: .utf8)!)
    exit(127)
}
child.waitUntilExit()
exit(child.terminationReason == .exit ? child.terminationStatus : 128 + child.terminationStatus)
