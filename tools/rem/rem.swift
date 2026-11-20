// rem — minimal Apple Reminders CLI over EventKit.
//
//   rem lists
//   rem list [--list NAME] [--all]
//   rem add --list NAME --title T --due "YYYY-MM-DD HH:MM" [--repeat daily|weekly|weekly:Mon,Wed,Fri] [--notes N]
//   rem notes --id ID --append TEXT
//   rem due --id ID --due "YYYY-MM-DD HH:MM"   (moves the due time and its alert; repeat kept)
//   rem title --id ID --set NEW_TITLE
//   rem delete --id ID
//   rem complete --id ID
//
// Needs Reminders access for the calling terminal (System Settings > Privacy & Security > Reminders).
// Runs outside the Claude Code sandbox only (XPC to calaccessd is blocked inside it).
import EventKit
import Foundation

let store = EKEventStore()

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}

func requestAccess() {
    let sem = DispatchSemaphore(value: 0)
    var ok = false
    store.requestFullAccessToReminders { granted, _ in ok = granted; sem.signal() }
    if sem.wait(timeout: .now() + 60) == .timedOut || !ok { fail("no Reminders access") }
}

func opts(_ args: [String]) -> [String: String] {
    var out: [String: String] = [:]
    var i = 0
    while i < args.count {
        let k = args[i]
        guard k.hasPrefix("--") else { fail("unexpected argument: \(k)") }
        let key = String(k.dropFirst(2))
        if i + 1 < args.count, !args[i + 1].hasPrefix("--") {
            out[key] = args[i + 1]; i += 2
        } else {
            out[key] = "true"; i += 1
        }
    }
    return out
}

func calendar(named name: String) -> EKCalendar {
    guard let cal = store.calendars(for: .reminder).first(where: { $0.title == name }) else {
        fail("no list named \(name)")
    }
    return cal
}

func fetch(_ cals: [EKCalendar]?, includeCompleted: Bool) -> [EKReminder] {
    let pred = includeCompleted
        ? store.predicateForReminders(in: cals)
        : store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: cals)
    let sem = DispatchSemaphore(value: 0)
    var result: [EKReminder] = []
    store.fetchReminders(matching: pred) { r in result = r ?? []; sem.signal() }
    sem.wait()
    return result
}

let fmt: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd HH:mm"
    f.timeZone = .current
    return f
}()

func describe(_ r: EKReminder) -> String {
    let due = r.dueDateComponents.flatMap { Calendar.current.date(from: $0) }.map { fmt.string(from: $0) } ?? "-"
    let rep = (r.recurrenceRules ?? []).map { rule -> String in
        let freq = ["daily", "weekly", "monthly", "yearly"][rule.frequency.rawValue]
        let days = rule.daysOfTheWeek?.map { ["", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][$0.dayOfTheWeek.rawValue] }
        return days.map { "\(freq):\($0.joined(separator: ","))" } ?? freq
    }.joined(separator: ";")
    let notes = (r.notes ?? "").replacingOccurrences(of: "\n", with: " / ")
    return [r.calendarItemIdentifier, r.calendar.title, r.title ?? "", due, rep.isEmpty ? "-" : rep, r.isCompleted ? "done" : "open", notes]
        .joined(separator: " | ")
}

func recurrence(_ spec: String) -> EKRecurrenceRule {
    if spec == "daily" { return EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil) }
    if spec == "weekly" { return EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil) }
    if spec.hasPrefix("weekly:") {
        let names = ["Sun": EKWeekday.sunday, "Mon": .monday, "Tue": .tuesday, "Wed": .wednesday,
                     "Thu": .thursday, "Fri": .friday, "Sat": .saturday]
        let days = spec.dropFirst(7).split(separator: ",").map { d -> EKRecurrenceDayOfWeek in
            guard let w = names[String(d)] else { fail("bad weekday: \(d)") }
            return EKRecurrenceDayOfWeek(w)
        }
        return EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, daysOfTheWeek: days,
                                daysOfTheMonth: nil, monthsOfTheYear: nil, weeksOfTheYear: nil,
                                daysOfTheYear: nil, setPositions: nil, end: nil)
    }
    fail("bad --repeat: \(spec)")
}

func find(_ id: String) -> EKReminder {
    guard let r = store.calendarItem(withIdentifier: id) as? EKReminder else { fail("no reminder with id \(id)") }
    return r
}

let argv = Array(CommandLine.arguments.dropFirst())
guard let cmd = argv.first, cmd != "--help", cmd != "-h" else {
    print("""
    usage: rem <command> [options]   (Apple Reminders over EventKit; macOS only)

      lists                                  list reminder lists
      list [--list NAME] [--all]             open reminders (--all adds completed)
                                             output: ID | list | title | due | repeat | state | notes
      add --list NAME --title T [--due 'YYYY-MM-DD HH:MM']
          [--repeat daily|weekly|weekly:Mon,Wed,Fri] [--notes N]
      notes --id ID --append TEXT            append a line to the notes
      due --id ID --due 'YYYY-MM-DD HH:MM'   move due time and alert; repeat kept
      title --id ID --set NEW_TITLE          rename
      complete --id ID                       tick off
      delete --id ID                         delete (prints the reminder first)

    Needs Reminders access for the terminal (System Settings > Privacy & Security > Reminders).
    Exit codes: 0 ok, 1 error or no access.
    """)
    exit(0)
}
let o = opts(Array(argv.dropFirst()))
requestAccess()

switch cmd {
case "lists":
    for c in store.calendars(for: .reminder) { print(c.title) }
case "list":
    let cals = o["list"].map { [calendar(named: $0)] }
    for r in fetch(cals, includeCompleted: o["all"] != nil) { print(describe(r)) }
case "add":
    guard let list = o["list"], let title = o["title"] else { fail("add needs --list and --title") }
    let r = EKReminder(eventStore: store)
    r.calendar = calendar(named: list)
    r.title = title
    r.notes = o["notes"]
    if let dueStr = o["due"] {
        guard let due = fmt.date(from: dueStr) else { fail("bad --due, want YYYY-MM-DD HH:MM") }
        r.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
        r.addAlarm(EKAlarm(absoluteDate: due))
    }
    if let rep = o["repeat"] { r.addRecurrenceRule(recurrence(rep)) }
    do { try store.save(r, commit: true) } catch { fail("save failed: \(error.localizedDescription)") }
    print(describe(r))
case "notes":
    guard let id = o["id"], let text = o["append"] else { fail("notes needs --id and --append") }
    let r = find(id)
    r.notes = [r.notes, text].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
    do { try store.save(r, commit: true) } catch { fail("save failed: \(error.localizedDescription)") }
    print(describe(r))
case "due":
    guard let id = o["id"], let dueStr = o["due"], let due = fmt.date(from: dueStr) else {
        fail("due needs --id and --due 'YYYY-MM-DD HH:MM'")
    }
    let r = find(id)
    r.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
    for a in r.alarms ?? [] { r.removeAlarm(a) }
    r.addAlarm(EKAlarm(absoluteDate: due))
    do { try store.save(r, commit: true) } catch { fail("save failed: \(error.localizedDescription)") }
    print(describe(r))
case "title":
    guard let id = o["id"], let title = o["set"] else { fail("title needs --id and --set") }
    let r = find(id)
    r.title = title
    do { try store.save(r, commit: true) } catch { fail("save failed: \(error.localizedDescription)") }
    print(describe(r))
case "delete":
    guard let id = o["id"] else { fail("delete needs --id") }
    let r = find(id)
    print("deleting: " + describe(r))
    do { try store.remove(r, commit: true) } catch { fail("delete failed: \(error.localizedDescription)") }
case "complete":
    guard let id = o["id"] else { fail("complete needs --id") }
    let r = find(id)
    r.isCompleted = true
    do { try store.save(r, commit: true) } catch { fail("save failed: \(error.localizedDescription)") }
    print(describe(r))
default:
    fail("unknown command: \(cmd)")
}
