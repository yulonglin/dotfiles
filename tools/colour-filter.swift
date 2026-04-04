// colour-filter: Toggle macOS colour filters
// Usage: colour-filter [off|grey|red]
//   off  — disable colour filters
//   grey — enable greyscale
//   red  — enable red tint (max intensity)
//   (no arg) — cycle: off → red → grey → off
//
// Compile: swiftc colour-filter.swift -o colour-filter
import Foundation

let ma = dlopen("/System/Library/Frameworks/MediaAccessibility.framework/MediaAccessibility", RTLD_LAZY)!
let ua = dlopen("/System/Library/PrivateFrameworks/UniversalAccess.framework/UniversalAccess", RTLD_LAZY)!

// MediaAccessibility: toggle colour filters on/off, set type
typealias GetEnabledCat = @convention(c) (Int32) -> Bool
typealias SetEnabledCat = @convention(c) (Int32, Bool) -> Void
let getEnabled = unsafeBitCast(dlsym(ma, "MADisplayFilterPrefGetCategoryEnabled"), to: GetEnabledCat.self)
let setEnabled = unsafeBitCast(dlsym(ma, "MADisplayFilterPrefSetCategoryEnabled"), to: SetEnabledCat.self)

// UniversalAccess: greyscale has its own dedicated API
typealias GetBool = @convention(c) () -> Bool
typealias SetBool = @convention(c) (Bool) -> Void
let getGray = unsafeBitCast(dlsym(ua, "UAGrayscaleIsEnabled"), to: GetBool.self)
let setGray = unsafeBitCast(dlsym(ua, "UAGrayscaleSetEnabled"), to: SetBool.self)

let defaults = UserDefaults(suiteName: "com.apple.mediaaccessibility")!

func currentMode() -> String {
    if getGray() { return "grey" }
    if getEnabled(1) {
        let filterType = defaults.integer(forKey: "__Color__-MADisplayFilterType")
        if filterType == 16 { return "red" }
        return "on"
    }
    return "off"
}

func setOff() {
    setGray(false)
    setEnabled(1, false)
    print("off")
}

func setGrey() {
    setEnabled(1, false)  // clear any existing filter
    setGray(true)
    print("grey")
}

func setRed() {
    setGray(false)  // clear greyscale
    setEnabled(1, false)

    // Configure red tint: type 16, hue 0, max intensity
    defaults.set(16, forKey: "__Color__-MADisplayFilterType")
    defaults.set(Float(0.0), forKey: "MADisplayFilterSingleColorHue")
    defaults.set(Float(1.0), forKey: "MADisplayFilterSingleColorIntensity")
    defaults.synchronize()

    setEnabled(1, true)
    print("red")
}

let arg = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : nil

switch arg {
case "off":
    setOff()
case "grey", "gray":
    setGrey()
case "red":
    setRed()
case "status":
    print(currentMode())
case nil:
    // Cycle: off → red → grey → off
    switch currentMode() {
    case "off": setRed()
    case "red": setGrey()
    default: setOff()
    }
default:
    fputs("Usage: colour-filter [off|grey|red|status]\n", stderr)
    exit(1)
}
