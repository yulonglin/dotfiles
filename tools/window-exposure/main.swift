// window-exposure - report which apps currently have a sufficiently visible window.
//
// Reads the on-screen window list front-to-back and, for each layer-0 window,
// computes what fraction of its frame is NOT covered by the opaque windows in
// front of it. A window counts as exposed when that fraction is at least
// --min-visible (default 40%).
//
// Coverage is the UNION of the occluding rectangles, computed exactly by
// coordinate compression: the candidate's and occluders' edges induce a small
// grid, and each cell is covered if its centre falls inside any occluder.
// Because it is a union, several windows that jointly cover a candidate are
// detected — unlike a single-window containment test, which misses that case.
// Full containment by one window is kept as a fast path for the common case.
//
// Output: one "<pid>\t<0|1>" line per PID that owns at least one candidate window,
// 1 = at least one window exposed. Apps with no candidate window are simply absent
// from the output — that is "unknown", not "not exposed", and the caller must never
// treat absence as grounds to hide. --verbose adds a third column with the best
// visible fraction for that PID, for diagnostics only.
//
// Exit codes: 0 ok · 1 no usable window list (caller: hide nothing) · 2 screen locked
// · 64 bad usage.
//
// Uses only required window-list keys (bounds, layer, alpha, owner PID), which are
// populated without Screen Recording permission. Owner name and window title are
// optional keys whose availability is permission-dependent — never used here.

import CoreGraphics
import Foundation

// A window must be at least this large to count as a real, user-visible window.
// Drops tooltips, shadows, and stray tracking windows.
let minCandidateArea: Double = 5000

// A window must be at least this opaque to hide what is beneath it.
let opaqueAlpha: Double = 0.95

struct Win {
    let pid: pid_t
    let alpha: Double
    let rect: CGRect

    var area: Double { rect.width * rect.height }

    // True if `other` lies entirely inside this window's frame.
    func covers(_ other: Win) -> Bool {
        rect.minX <= other.rect.minX
            && rect.minY <= other.rect.minY
            && rect.maxX >= other.rect.maxX
            && rect.maxY >= other.rect.maxY
    }
}

func fail(_ message: String, _ code: Int32) -> Never {
    FileHandle.standardError.write(Data("window-exposure: \(message)\n".utf8))
    exit(code)
}

// Fraction of `candidate` left visible once every rect in `occluders` is painted
// over it. Exact for axis-aligned rectangles; 1.0 when nothing overlaps.
func visibleFraction(of candidate: CGRect, under occluders: [CGRect]) -> Double {
    let total = candidate.width * candidate.height
    guard total > 0 else { return 0 }
    if occluders.isEmpty { return 1 }

    // Clamp every edge into the candidate, so the grid only spans the candidate.
    func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { min(max(v, lo), hi) }
    var xs: Set<Double> = [candidate.minX, candidate.maxX]
    var ys: Set<Double> = [candidate.minY, candidate.maxY]
    for o in occluders {
        xs.insert(clamp(o.minX, candidate.minX, candidate.maxX))
        xs.insert(clamp(o.maxX, candidate.minX, candidate.maxX))
        ys.insert(clamp(o.minY, candidate.minY, candidate.maxY))
        ys.insert(clamp(o.maxY, candidate.minY, candidate.maxY))
    }
    let xg = xs.sorted()
    let yg = ys.sorted()

    var covered: Double = 0
    for i in 0..<(xg.count - 1) {
        let width = xg[i + 1] - xg[i]
        if width <= 0 { continue }
        let cx = (xg[i] + xg[i + 1]) / 2
        for j in 0..<(yg.count - 1) {
            let height = yg[j + 1] - yg[j]
            if height <= 0 { continue }
            let centre = CGPoint(x: cx, y: (yg[j] + yg[j + 1]) / 2)
            for o in occluders where o.contains(centre) {
                covered += width * height
                break
            }
        }
    }
    return clamp((total - covered) / total, 0, 1)
}

var minVisible: Double = 0.40
var verbose = false
var argv = Array(CommandLine.arguments.dropFirst())
var argIndex = 0
while argIndex < argv.count {
    switch argv[argIndex] {
    case "--min-visible":
        argIndex += 1
        guard argIndex < argv.count, let percent = Double(argv[argIndex]),
              percent >= 0, percent <= 100
        else { fail("--min-visible needs a percentage between 0 and 100", 64) }
        minVisible = percent / 100
    case "--verbose":
        verbose = true
    default:
        fail("unknown argument: \(argv[argIndex])", 64)
    }
    argIndex += 1
}

// A locked screen says nothing about what the user can see.
if let session = CGSessionCopyCurrentDictionary() as? [String: Any],
   let locked = session["CGSSessionScreenIsLocked"] as? Int, locked == 1 {
    fail("screen locked", 2)
}

guard let raw = CGWindowListCopyWindowInfo(
    [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
) as? [[String: Any]], !raw.isEmpty else {
    fail("no window list (NULL or empty)", 1)
}

// Layer-0 windows only, front-to-back order preserved. Higher layers are menus,
// the Dock, and overlays: neither tracked as app windows nor trusted as occluders.
var windows: [Win] = []
for info in raw {
    guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
          let rawPID = info[kCGWindowOwnerPID as String] as? Int,
          let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
          let rect = CGRect(dictionaryRepresentation: boundsDict as CFDictionary)
    else { continue }
    let pid = pid_t(rawPID)
    let alpha = (info[kCGWindowAlpha as String] as? Double) ?? 1.0
    windows.append(Win(pid: pid, alpha: alpha, rect: rect))
}

// Best visible fraction seen for each PID. A window of the same app never counts
// as an occluder: an app covering itself is still that app on screen.
var bestFractionByPID: [pid_t: Double] = [:]
for (i, candidate) in windows.enumerated() where candidate.area >= minCandidateArea {
    var occluders: [CGRect] = []
    var fullyContained = false
    for j in 0..<i {
        let front = windows[j]
        guard front.alpha >= opaqueAlpha, front.pid != candidate.pid else { continue }
        if front.covers(candidate) {
            fullyContained = true
            break
        }
        if front.rect.intersects(candidate.rect) { occluders.append(front.rect) }
    }
    let fraction = fullyContained ? 0 : visibleFraction(of: candidate.rect, under: occluders)
    bestFractionByPID[candidate.pid] = max(bestFractionByPID[candidate.pid] ?? 0, fraction)
}

// No candidate windows at all on a non-empty list means we are looking at something
// other than an ordinary desktop (Mission Control, a Space transition). Unknown, not empty.
if bestFractionByPID.isEmpty {
    fail("no layer-0 candidate windows", 1)
}

var out = ""
for pid in bestFractionByPID.keys.sorted() {
    let fraction = bestFractionByPID[pid]!
    out += "\(pid)\t\(fraction >= minVisible ? 1 : 0)"
    if verbose { out += String(format: "\t%.3f", fraction) }
    out += "\n"
}
FileHandle.standardOutput.write(Data(out.utf8))
