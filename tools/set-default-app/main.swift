// tools/set-default-app/main.swift
// Sets macOS default app for file extensions via Launch Services.
// Usage: set-default-app <bundle-id> <ext> [ext...]
// Example: set-default-app com.todesktop.230313mzl4w4u92 py md json

import Foundation
import UniformTypeIdentifiers

// Suppress deprecation warning — Apple deprecated LSSetDefaultRoleHandlerForContentType
// in macOS 12 with no replacement. All tools (duti, utiluti, dutix) use this same API.
// It still works on macOS 15 (Sequoia).
@_silgen_name("LSSetDefaultRoleHandlerForContentType")
func LSSetDefaultRoleHandlerForContentType(
    _ inContentType: CFString,
    _ inRole: Int,
    _ inHandlerBundleID: CFString
) -> Int32

// LSRolesMask.all = 0xFFFFFFFF (viewer + editor + shell + none)
let kLSRolesAll: Int = -1  // 0xFFFFFFFF as signed

func main() {
    let args = CommandLine.arguments
    guard args.count >= 3 else {
        fputs("Usage: set-default-app <bundle-id> <ext> [ext...]\n", stderr)
        exit(1)
    }

    let bundleID = args[1]
    let extensions = Array(args[2...])
    var failures = 0

    for ext in extensions {
        guard let utType = UTType(filenameExtension: ext) else {
            fputs("⚠️  skip: .\(ext) — no UTI found\n", stderr)
            continue
        }

        let uti = utType.identifier
        let result = LSSetDefaultRoleHandlerForContentType(
            uti as CFString,
            kLSRolesAll,
            bundleID as CFString
        )

        if result == 0 {
            print("✓ .\(ext) → \(uti) → \(bundleID)")
        } else {
            fputs("✗ .\(ext) → \(uti) — error \(result)\n", stderr)
            failures += 1
        }
    }

    if failures > 0 {
        exit(1)
    }
}

main()
