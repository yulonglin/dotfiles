// av-prefer camera helper — read or set the camera macOS hands to apps that
// have not saved a choice of their own. The zsh wrapper custom_bins/av-prefer
// compiles this on first run and handles audio itself through SwitchAudioSource.
//
//   av-prefer-camera status            print the current default camera
//   av-prefer-camera list              print every camera, one per line
//   av-prefer-camera pick NAME [NAME…] print the first present camera whose
//                                      name contains NAME (case-insensitive)
//   av-prefer-camera set NAME [NAME…]  the same, and make it the preferred camera
//
// How it works: setting AVCaptureDevice.userPreferredCamera from any process
// changes AVCaptureDevice.default(for: .video) — and the device order — that
// every other process sees. Apple documents the preference as persisting
// across launches and reboots, with a short device history so a camera that
// returns is preferred again. Measured 2026-11-18 on macOS 26 (25G241): a
// second, separately compiled binary saw the new default at once, both ways.
// userPreferredCamera itself reads back nil in other processes, so status
// reports default(for:) — the value apps actually get.
import AVFoundation
import Foundation

func cameras() -> [AVCaptureDevice] {
    AVCaptureDevice.DiscoverySession(
        deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
        mediaType: .video, position: .unspecified
    ).devices
}

func fail(_ msg: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(("av-prefer: " + msg + "\n").data(using: .utf8)!)
    exit(code)
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "status":
    print(AVCaptureDevice.default(for: .video)?.localizedName ?? "none")
case "list":
    for d in cameras() { print(d.localizedName) }
case "set", "pick":
    let wanted = args.dropFirst()
    if wanted.isEmpty { fail("\(args[0]) needs at least one camera name", code: 2) }
    let present = cameras()
    for name in wanted {
        if let d = present.first(where: { $0.localizedName.localizedCaseInsensitiveContains(name) }) {
            if args[0] == "set" { AVCaptureDevice.userPreferredCamera = d }
            print(d.localizedName)
            exit(0)
        }
    }
    fail("no camera matches \(wanted.joined(separator: ", ")); present: "
        + present.map(\.localizedName).joined(separator: ", "))
default:
    fail("usage: av-prefer-camera status | list | pick|set NAME [NAME…]", code: 2)
}
