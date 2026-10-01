// tcc-carry-claude: give every installed Claude Code version the same folder decisions.
//
// The native installer puts each release at its own path, ~/.local/share/claude/versions/<ver>,
// and macOS keys a bare binary's privacy grants by path. The background daemon respawns its
// workers on every upgrade as their own responsible process, so each release asks again for
// Documents, Downloads and Desktop. This writes one fixed decision per folder for each
// installed version that has none. Rows already present, whoever wrote them, are left alone.
//
// Writing the user TCC database needs Full Disk Access for this binary.
import Foundation
import Security
import SQLite3

let policy: [(service: String, folder: String, allow: Bool)] = [
    ("kTCCServiceSystemPolicyDocumentsFolder", "Documents", true),
    ("kTCCServiceSystemPolicyDownloadsFolder", "Downloads", true),
    ("kTCCServiceSystemPolicyDesktopFolder", "Desktop", false),
]

// Only binaries Anthropic signed get a row. A half-downloaded or swapped file fails this.
let anthropicRequirement =
    #"identifier "com.anthropic.claude-code" and anchor apple generic and certificate leaf[subject.OU] = "Q6L2SF6YDW""#

let home = FileManager.default.homeDirectoryForCurrentUser.path
var dbPath = home + "/Library/Application Support/com.apple.TCC/TCC.db"
var versionsDir = home + "/.local/share/claude/versions"
var dryRun = false

let usage = """
    usage: tcc-carry-claude [--dry-run] [--db PATH] [--versions-dir PATH]

    Insert Documents=allow, Downloads=allow, Desktop=deny into the user TCC database for
    every Anthropic-signed binary in the versions directory that has no row for that folder.

      --dry-run           print what would be inserted; open the database read-only
      --db PATH           TCC database (default: \(dbPath))
      --versions-dir PATH Claude Code versions (default: \(versionsDir))
    """

var args = CommandLine.arguments.dropFirst()
while let arg = args.popFirst() {
    switch arg {
    case "--dry-run": dryRun = true
    case "--db", "--versions-dir":
        guard let value = args.popFirst() else { fail(usage, code: 2) }
        if arg == "--db" { dbPath = value } else { versionsDir = value }
    case "-h", "--help": print(usage); exit(0)
    default: fail("unknown argument: \(arg)\n\(usage)", code: 2)
    }
}

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

/// The binary's designated requirement as the blob tccd stores in `csreq`, or nil when the
/// binary is not validly signed by Anthropic.
func csreq(for path: String, requirement: SecRequirement) -> Data? {
    var code: SecStaticCode?
    guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess,
          let code,
          SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess
    else { return nil }
    var designated: SecRequirement?
    var blob: CFData?
    guard SecCodeCopyDesignatedRequirement(code, [], &designated) == errSecSuccess,
          let designated,
          SecRequirementCopyData(designated, [], &blob) == errSecSuccess,
          let blob
    else { return nil }
    return blob as Data
}

var requirement: SecRequirement?
guard SecRequirementCreateWithString(anthropicRequirement as CFString, [], &requirement) == errSecSuccess,
      let requirement
else { fail("could not compile the signing requirement") }

let versions: [String]
do {
    versions = try FileManager.default.contentsOfDirectory(atPath: versionsDir)
        .filter { !$0.hasPrefix(".") }
        .sorted()
} catch {
    fail("cannot list \(versionsDir): \(error.localizedDescription)")
}

var db: OpaquePointer?
let openFlags = dryRun ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE
guard sqlite3_open_v2(dbPath, &db, openFlags, nil) == SQLITE_OK else {
    fail("cannot open \(dbPath): \(String(cString: sqlite3_errmsg(db)))")
}
defer { sqlite3_close(db) }
sqlite3_busy_timeout(db, 5000)

func dbFail(_ what: String) -> Never {
    fail("""
        \(what) failed on \(dbPath): \(String(cString: sqlite3_errmsg(db)))
        "authorization denied" means this binary lacks Full Disk Access:
        System Settings > Privacy & Security > Full Disk Access > + \(CommandLine.arguments[0])
        """)
}

let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

func existingServices(for client: String) -> Set<String> {
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, "SELECT service FROM access WHERE client = ? AND client_type = 1", -1, &stmt, nil) == SQLITE_OK
    else { dbFail("query") }
    defer { sqlite3_finalize(stmt) }
    sqlite3_bind_text(stmt, 1, client, -1, SQLITE_TRANSIENT)
    var found = Set<String>()
    while true {
        let rc = sqlite3_step(stmt)
        if rc == SQLITE_DONE { break }
        guard rc == SQLITE_ROW else { dbFail("query") }
        found.insert(String(cString: sqlite3_column_text(stmt, 0)))
    }
    return found
}

func insert(service: String, client: String, allow: Bool, csreq: Data) {
    var stmt: OpaquePointer?
    // auth_reason 2 is user consent, the value tccd writes when the prompt is answered.
    let sql = """
        INSERT OR IGNORE INTO access
          (service, client, client_type, auth_value, auth_reason, auth_version, csreq, flags, last_modified, last_reminded)
        VALUES (?, ?, 1, ?, 2, 1, ?, 0, CAST(strftime('%s','now') AS INTEGER), 0)
        """
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { dbFail("insert") }
    defer { sqlite3_finalize(stmt) }
    sqlite3_bind_text(stmt, 1, service, -1, SQLITE_TRANSIENT)
    sqlite3_bind_text(stmt, 2, client, -1, SQLITE_TRANSIENT)
    sqlite3_bind_int(stmt, 3, allow ? 2 : 0)
    _ = csreq.withUnsafeBytes { sqlite3_bind_blob(stmt, 4, $0.baseAddress, Int32(csreq.count), SQLITE_TRANSIENT) }
    guard sqlite3_step(stmt) == SQLITE_DONE else { dbFail("insert") }
}

for version in versions {
    let client = versionsDir + "/" + version
    let missing = policy.filter { !existingServices(for: client).contains($0.service) }
    if missing.isEmpty { continue }
    guard let blob = csreq(for: client, requirement: requirement) else {
        print("skip \(version): not a valid Anthropic-signed binary")
        continue
    }
    for entry in missing {
        let decision = entry.allow ? "allow" : "deny"
        if dryRun {
            print("would \(decision) \(entry.folder) for \(version)")
        } else {
            insert(service: entry.service, client: client, allow: entry.allow, csreq: blob)
            print("\(decision) \(entry.folder) for \(version)")
        }
    }
}
