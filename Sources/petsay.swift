// petsay: talk to the Touch Bar Pet.
//
//   petsay "Build finished!" --mood done   show a short note for a few seconds
//   petsay --mood working                  just change what the cat is doing
//   petsay --hook                          handle a Claude Code hook event (JSON on stdin)
//   petsay --demo                          show each state in turn
//   petsay --status                        list what the cat thinks each Claude is doing
//   petsay --theme ginger | --show | --hide | --clear | --quit

import AppKit

let bundleID = "com.benelsom.touchbarpet"
let sayNote = Notification.Name("com.benelsom.touchbarpet.say")
let moods = ["inactive", "waiting", "working", "needs", "done", "alert"]
let themes = ["grey", "ginger", "cream", "blue", "calico"]
let prefs = UserDefaults(suiteName: bundleID)!

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}

func usage() -> Never {
    print("""
    petsay: talk through your Touch Bar cat

      petsay "message" [--mood MOOD] [--seconds N]   show a short note beside the cat
      petsay --mood MOOD             change what the cat is doing for a few seconds
      echo "message" | petsay        read the note from stdin
      petsay --theme NAME            recolour the cat: \(themes.joined(separator: ", "))
      petsay --pet [--seconds N]     pet the cat from here (same as touching it)
      petsay --demo                  show each state in turn, about a minute
      petsay --status                list what the cat thinks each Claude is doing
      petsay --clear                 forget every Claude (for a note that's stuck)
      petsay --show                  put the cat's bar back on the Touch Bar
      petsay --hide                  clear a note early
      petsay --quit                  quit the pet (Claude hooks won't relaunch it
                                     until you run petsay yourself again)
      petsay --hook                  handle a Claude Code hook event (JSON on stdin)

    Moods: \(moods.joined(separator: ", "))
    """)
    exit(0)
}

// MARK: - Talking to the app

func isRunning() -> Bool {
    !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
}

func appURL() -> URL? {
    if let u = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) { return u }
    let fallback = URL(fileURLWithPath: NSHomeDirectory() + "/Applications/Touch_Bar_Pet.app")
    return FileManager.default.fileExists(atPath: fallback.path) ? fallback : nil
}

@discardableResult
func ensureRunning() -> Bool {
    if isRunning() { return true }
    guard let url = appURL() else { return false }
    let cfg = NSWorkspace.OpenConfiguration()
    cfg.activates = false
    cfg.addsToRecentItems = false
    let done = DispatchSemaphore(value: 0)
    NSWorkspace.shared.openApplication(at: url, configuration: cfg) { _, _ in done.signal() }
    _ = done.wait(timeout: .now() + 5)
    Thread.sleep(forTimeInterval: 1.2) // let it set up its listener
    return isRunning()
}

func post(_ info: [String: String]) {
    DistributedNotificationCenter.default().postNotificationName(
        sayNote, object: nil, userInfo: info, deliverImmediately: true)
}

// MARK: - Claude Code hooks

/// "Combo Caller" from ".../Vibe Coded Projects/Combo Caller"; Claude's own
/// scratch folders just become "Claude".
func projectName(_ cwd: String?) -> String {
    guard var cwd, !cwd.isEmpty else { return "Claude" }
    // A worktree belongs to the project it was made from.
    if let r = cwd.range(of: "/.claude/worktrees/") { cwd = String(cwd[..<r.lowerBound]) }
    let base = (cwd as NSString).lastPathComponent
    if base.hasPrefix("scratch-") || base.isEmpty || cwd == NSHomeDirectory() { return "Claude" }
    return base.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
}

/// The Claude process running this hook: the first ancestor that isn't a shell.
/// The cat watches it, so a closed session stops asking for you. 0 if not found.
func claudeProcess() -> pid_t {
    let shells: Set<String> = ["sh", "bash", "zsh", "dash", "fish", "env"]
    var pid = getppid()
    for _ in 0..<6 {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard pid > 1, sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return 0 }
        let name = withUnsafeBytes(of: info.kp_proc.p_comm) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
        if !shells.contains(name.trimmingCharacters(in: ["-"])) { return pid }
        pid = info.kp_eproc.e_ppid
    }
    return 0
}

/// Only when this file exists, for working out which events Claude really sends.
let hookLog = NSHomeDirectory() + "/Library/Logs/Touch_Bar_Pet_hooks.log"

func logHook(_ info: [String: String], raw: [String: Any]) {
    guard let h = FileHandle(forWritingAtPath: hookLog) else { return }
    let stamp = ISO8601DateFormatter().string(from: Date())
    let type = raw["notification_type"] as? String ?? ""
    let line = "\(stamp) \(raw["hook_event_name"] ?? "?") -> \(info["hook"] ?? "") \(info["kind"] ?? "") "
        + "tool=\(info["tool"] ?? "") type=\(type) session=\((info["session"] ?? "").prefix(8)) "
        + "project=\(info["project"] ?? "") pid=\(info["pid"] ?? "")\n"
    h.seekToEndOfFile()
    h.write(line.data(using: .utf8)!)
    h.closeFile()
}

func handleHook() -> Never {
    // Hooks must never block Claude or print anything: UserPromptSubmit's
    // stdout would be added to Claude's context.
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let event = j["hook_event_name"] as? String else { exit(0) }

    var info: [String: String] = [
        "hook": event,
        "session": j["session_id"] as? String ?? "?",
        "project": projectName(j["cwd"] as? String),
        "pid": String(claudeProcess()),
    ]
    let tool = j["tool_name"] as? String
    // The session-watch mod calls these every 10 seconds in every session, which
    // would make idle Claudes look busy forever. They're never real work anyway.
    if let tool, tool.hasPrefix("mcp__ccd_session_mgmt__") { exit(0) }
    if let tool { info["tool"] = tool }
    // These tools are Claude stopping to ask you something.
    let asksYou = tool == "AskUserQuestion" || tool == "ExitPlanMode"
    switch event {
    case "PermissionRequest":
        info["hook"] = "Notification"
        info["kind"] = asksYou ? "help" : "access"
    case "PreToolUse" where asksYou:
        info["hook"] = "Notification"
        info["kind"] = "help"
    case "Notification":
        let type = (j["notification_type"] as? String ?? "").lowercased()
        let msg = (j["message"] as? String ?? "").lowercased()
        if type.contains("idle") || msg.contains("waiting for your input") {
            info["kind"] = "idle"
        } else if type.contains("permission") || msg.contains("permission") {
            info["kind"] = "access"
        } else {
            info["kind"] = "help"
        }
    default: break
    }
    logHook(info, raw: j)

    if !isRunning() {
        // Respect `petsay --quit`; otherwise wake the cat up.
        if prefs.bool(forKey: "stayQuit") { exit(0) }
        guard ensureRunning() else { exit(0) }
    }
    post(info)
    exit(0)
}

// MARK: - Looking at the states

/// Each state as it really looks, whatever Claude is doing right now.
func demo() -> Never {
    guard ensureRunning() else { fail("Couldn't find or start Touch_Bar_Pet.app. Run install.sh first.") }
    let steps: [(about: String, mood: String, note: String?)] = [
        ("Asleep: no Claude is doing anything", "inactive", nil),
        ("Walking: your reward, Claude is working and nothing needs you", "working", nil),
        ("Sitting with a note: a Claude has finished and is waiting for you", "waiting", "Combo Caller needs you"),
        ("Sitting with a note: several are waiting", "waiting", "3 Claudes need you"),
        ("Pawing with a yellow note: blocked on a permission", "needs", "Combo Caller needs access"),
        ("Pawing with a yellow note: blocked on a question", "needs", "Combo Caller needs help"),
    ]
    let hold = 8.0
    for step in steps {
        print(step.about)
        var info = ["mood": step.mood, "seconds": String(hold + 1)]
        if let note = step.note { info["text"] = note }
        post(info)
        Thread.sleep(forTimeInterval: hold)
    }
    print("Being petted (touch the cat to do this yourself)")
    post(["command": "hide"])
    post(["command": "pet", "seconds": String(hold)])
    Thread.sleep(forTimeInterval: hold)
    print("Back to what's really happening")
    exit(0)
}

func status() -> Never {
    let file = NSHomeDirectory() + "/Library/Application Support/Touch_Bar_Pet/sessions.json"
    guard let data = FileManager.default.contents(atPath: file),
          let all = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]], !all.isEmpty else {
        print("No Claude sessions known.")
        exit(0)
    }
    let rows = all.sorted { ($0.value["updated"] as? String ?? "") < ($1.value["updated"] as? String ?? "") }
    for (id, s) in rows {
        let state = (s["state"] as? String ?? "?").padding(toLength: 8, withPad: " ", startingAt: 0)
        print("\(state) \(id.prefix(8))  \(s["project"] ?? "?")  \(s["note"] ?? "")  since \(s["updated"] ?? "?")")
    }
    exit(0)
}

// MARK: - Arguments

var mood: String?
var seconds: String?
var theme: String?
var quit = false, hide = false, show = false, hook = false, petCat = false, clear = false
var words: [String] = []

var args = CommandLine.arguments.dropFirst().makeIterator()
while let a = args.next() {
    switch a {
    case "-h", "--help": usage()
    case "-m", "--mood": mood = args.next()
    case "-s", "--seconds": seconds = args.next()
    case "--theme": theme = args.next()
    case "--quit": quit = true
    case "--hide": hide = true
    case "--show": show = true
    case "--hook": hook = true
    case "--pet": petCat = true
    case "--demo": demo()
    case "--status": status()
    case "--clear": clear = true
    default: words.append(a)
    }
}

if hook { handleHook() }

if quit {
    prefs.set(true, forKey: "stayQuit")
    if isRunning() { post(["command": "quit"]) }
    exit(0)
}

// Any manual use means "I want the cat around".
prefs.set(false, forKey: "stayQuit")

let oldNames = ["idle": "waiting", "think": "waiting", "work": "working", "sleep": "inactive"]
if let m = mood { mood = oldNames[m] ?? m }
if let m = mood, !moods.contains(m) { fail("Unknown mood '\(m)'. Try: \(moods.joined(separator: ", "))") }
if let t = theme, !themes.contains(t) { fail("Unknown theme '\(t)'. Try: \(themes.joined(separator: ", "))") }

var text = words.joined(separator: " ")
let nothingElse = mood == nil && theme == nil && !hide && !show && !petCat && !clear
if text.isEmpty && nothingElse && isatty(STDIN_FILENO) == 0 {
    text = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
if text.isEmpty && nothingElse { usage() }

guard ensureRunning() else { fail("Couldn't find or start Touch_Bar_Pet.app. Run install.sh first.") }

if let t = theme { post(["command": "theme", "theme": t]) }
if show { post(["command": "show"]) }
if hide { post(["command": "hide"]) }
if clear { post(["command": "clear"]) }
if petCat {
    post(["command": "pet", "seconds": seconds ?? "3"])
    exit(0)
}
if !text.isEmpty || mood != nil {
    var info: [String: String] = [:]
    if !text.isEmpty { info["text"] = text }
    if let mood { info["mood"] = mood }
    if let seconds { info["seconds"] = seconds }
    post(info)
}
