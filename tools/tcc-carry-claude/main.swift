// tcc-carry-claude: give every installed Claude Code version the privacy answers you gave the last one.
//
// The native installer puts each release at its own path, ~/.local/share/claude/versions/<ver>,
// and macOS keys a bare binary's privacy grants by path, so each release asks again for
// Documents, Downloads, data from other apps and the rest. For each installed version this copies,
// per service and target, the most recent answer you gave any other version (allow or deny), and
// always denies Desktop. Rows already present, whoever wrote them, are left alone.
//
// Writing the user TCC database needs Full Disk Access for this binary. Full Disk Access itself
// lives in the SIP-protected system database, which this does not touch.
import Foundation
import Security
import SQLite3

// Services answered this way whatever was answered before.
let overrides: [String: Int32] = ["kTCCServiceSystemPolicyDesktopFolder": 0]

// Only binaries Anthropic signed get a row. A half-downloaded or swapped file fails this.
let anthropicRequirement =
    #"identifier "com.anthropic.claude-code" and anchor apple generic and certificate leaf[subject.OU] = "Q6L2SF6YDW""#

let home = FileManager.default.homeDirectoryForCurrentUser.path
var dbPath = home + "/Library/Application Support/com.apple.TCC/TCC.db"
var versionsDir = home + "/.local/share/claude/versions"
var dryRun = false

let usage = """
    usage: tcc-carry-claude [--dry-run] [--db PATH] [--versions-dir PATH]

    For every Anthropic-signed binary in the versions directory, copy into the user TCC database
    the latest answer you gave any other version for each service it has no row for. Desktop is
    always denied.

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
let clientPrefix = versionsDir + "/"

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

func dbFail(_ what: String) -> Never {
    fail("""
        \(what) failed on \(dbPath): \(String(cString: sqlite3_errmsg(db)))
        "unable to open" or "authorization denied" means this binary lacks Full Disk Access:
        System Settings > Privacy & Security > Full Disk Access > + \(CommandLine.arguments[0])
        """)
}

let openFlags = dryRun ? SQLITE_OPEN_READONLY : SQLITE_OPEN_READWRITE
guard sqlite3_open_v2(dbPath, &db, openFlags, nil) == SQLITE_OK else { dbFail("open") }
defer { sqlite3_close(db) }
sqlite3_busy_timeout(db, 5000)

let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

func prepare(_ sql: String, _ binds: [String]) -> OpaquePointer? {
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { dbFail("prepare") }
    for (i, value) in binds.enumerated() {
        sqlite3_bind_text(stmt, Int32(i + 1), value, -1, SQLITE_TRANSIENT)
    }
    return stmt
}

/// The latest answer per (service, target) given to any other version, still keyed as the
/// access table keys it. auth_reason 2 is an answered prompt and 3 a choice made in System
/// Settings, either directly or through a row this tool copied. Rows tccd set for other reasons
/// are not repeated.
let candidates = """
    SELECT a.rowid FROM access a
    WHERE a.client_type = 1 AND a.auth_reason IN (2, 3)
      AND substr(a.client, 1, length(?1)) = ?1 AND a.client != ?2
      AND a.last_modified = (
        SELECT max(b.last_modified) FROM access b
        WHERE b.client_type = 1 AND b.auth_reason IN (2, 3)
          AND substr(b.client, 1, length(?1)) = ?1 AND b.client != ?2
          AND b.service = a.service AND b.indirect_object_identifier = a.indirect_object_identifier)
      AND NOT EXISTS (
        SELECT 1 FROM access c
        WHERE c.client = ?2 AND c.client_type = 1
          AND c.service = a.service AND c.indirect_object_identifier = a.indirect_object_identifier)
    """

/// Overridden services the version has no row for, whether or not anything was answered before.
func missingOverrides(for client: String) -> [String] {
    overrides.keys.sorted().filter { service in
        let stmt = prepare("SELECT 1 FROM access WHERE client = ?1 AND client_type = 1 AND service = ?2", [client, service])
        defer { sqlite3_finalize(stmt) }
        return sqlite3_step(stmt) != SQLITE_ROW
    }
}

func pending(for client: String) -> [(service: String, target: String)] {
    let stmt = prepare("SELECT service, indirect_object_identifier FROM access WHERE rowid IN (\(candidates))",
                       [clientPrefix, client])
    defer { sqlite3_finalize(stmt) }
    var rows = [(service: String, target: String)]()
    while sqlite3_step(stmt) == SQLITE_ROW {
        rows.append((String(cString: sqlite3_column_text(stmt, 0)), String(cString: sqlite3_column_text(stmt, 1))))
    }
    let carried = Set(rows.map(\.service))
    return rows + missingOverrides(for: client).filter { !carried.contains($0) }.map { ($0, "UNUSED") }
}

func describe(_ service: String, _ target: String, _ authValue: Int32) -> String {
    let name = service.replacingOccurrences(of: "kTCCService", with: "")
    let decision = switch authValue { case 0: "deny"; case 2: "allow"; default: "auth_value \(authValue)" }
    return target == "UNUSED" ? "\(decision) \(name)" : "\(decision) \(name) -> \(target)"
}

func carry(to client: String, csreq: Data, label: String) {
    // Copy every candidate row with the new client and its own csreq; overrides replace auth_value.
    let overrideCase = overrides.map { "WHEN '\($0.key)' THEN \($0.value)" }.joined(separator: " ")
    let copy = """
        INSERT OR IGNORE INTO access
          (service, client, client_type, auth_value, auth_reason, auth_version, csreq, policy_id,
           indirect_object_identifier_type, indirect_object_identifier, indirect_object_code_identity,
           flags, last_modified, last_reminded)
        SELECT service, ?2, 1, CASE service \(overrideCase) ELSE auth_value END, auth_reason, auth_version, ?3, policy_id,
               indirect_object_identifier_type, indirect_object_identifier, indirect_object_code_identity,
               flags, CAST(strftime('%s','now') AS INTEGER), 0
        FROM access WHERE rowid IN (\(candidates))
        RETURNING service, indirect_object_identifier, auth_value
        """
    let fresh = """
        INSERT OR IGNORE INTO access
          (service, client, client_type, auth_value, auth_reason, auth_version, csreq, flags, last_modified, last_reminded)
        VALUES (?1, ?2, 1, ?3, 2, 1, ?4, 0, CAST(strftime('%s','now') AS INTEGER), 0)
        """
    let stmt = prepare(copy, [clientPrefix, client])
    _ = csreq.withUnsafeBytes { sqlite3_bind_blob(stmt, 3, $0.baseAddress, Int32(csreq.count), SQLITE_TRANSIENT) }
    while true {
        let rc = sqlite3_step(stmt)
        if rc == SQLITE_DONE { break }
        guard rc == SQLITE_ROW else { dbFail("insert") }
        let row = describe(String(cString: sqlite3_column_text(stmt, 0)),
                           String(cString: sqlite3_column_text(stmt, 1)),
                           sqlite3_column_int(stmt, 2))
        print("\(row) for \(label)")
    }
    sqlite3_finalize(stmt)
    for service in missingOverrides(for: client) {
        let value = overrides[service]!
        let ins = prepare(fresh, [service, client])
        sqlite3_bind_int(ins, 3, value)
        _ = csreq.withUnsafeBytes { sqlite3_bind_blob(ins, 4, $0.baseAddress, Int32(csreq.count), SQLITE_TRANSIENT) }
        guard sqlite3_step(ins) == SQLITE_DONE else { dbFail("insert") }
        sqlite3_finalize(ins)
        print("\(describe(service, "UNUSED", value)) for \(label)")
    }
}

for version in versions {
    let client = versionsDir + "/" + version
    let todo = pending(for: client)
    if todo.isEmpty { continue }
    guard let blob = csreq(for: client, requirement: requirement) else {
        print("skip \(version): not a valid Anthropic-signed binary")
        continue
    }
    if dryRun {
        for row in todo {
            let name = row.service.replacingOccurrences(of: "kTCCService", with: "")
            let target = row.target == "UNUSED" ? "" : " -> \(row.target)"
            print("would carry \(name)\(target) to \(version)")
        }
    } else {
        carry(to: client, csreq: blob, label: version)
    }
}
