// petsay: send a message (and/or a mood) to the Touch Bar Pet.
//
//   petsay "Build finished!" --mood done
//   petsay --mood work            (just change what the cat is doing)
//   echo "hello" | petsay
//   petsay --hook                 (read a Claude Code hook event from stdin)
//   petsay --theme ginger | --quit | --hide

import AppKit

let bundleID = "com.benelsom.touchbarpet"
let sayNote = Notification.Name("com.benelsom.touchbarpet.say")
let moods = ["idle", "think", "work", "done", "needs", "alert", "sleep"]
let themes = ["grey", "ginger", "cream", "blue", "calico"]
let prefs = UserDefaults(suiteName: bundleID)!

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}

func usage() -> Never {
    print("""
    petsay: talk through your Touch Bar cat

      petsay "message" [--mood MOOD] [--seconds N]
      petsay --mood MOOD             change the cat's mood without a message
      echo "message" | petsay        read the message from stdin
      petsay --theme NAME            recolour the cat: \(themes.joined(separator: ", "))
      petsay --hide                  put the bubble away
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

/// Pulls Claude's latest reply out of the hook payload or the session transcript.
func lastAssistantText(_ j: [String: Any]) -> String? {
    if let s = j["last_assistant_message"] as? String, !s.isEmpty { return s }
    guard let path = j["transcript_path"] as? String,
          let fh = FileHandle(forReadingAtPath: path) else { return nil }
    defer { try? fh.close() }
    let size = fh.seekToEndOfFile()
    let window: UInt64 = 2_000_000
    fh.seek(toFileOffset: size > window ? size - window : 0)
    let text = String(decoding: fh.readDataToEndOfFile(), as: UTF8.self)
    for line in text.split(separator: "\n").reversed() {
        guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
        if o["type"] as? String == "user", (o["message"] as? [String: Any])?["content"] is String {
            return nil // reached the user's prompt without finding a reply
        }
        guard o["type"] as? String == "assistant",
              let msg = o["message"] as? [String: Any],
              let content = msg["content"] as? [[String: Any]] else { continue }
        let parts = content.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
        let joined = parts.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if !joined.isEmpty { return joined }
    }
    return nil
}

/// Turns a markdown reply into one short Touch Bar-friendly line.
func tidy(_ s: String, max: Int = 160) -> String {
    var t = s
    let rules: [(String, String)] = [
        ("```[\\s\\S]*?```", " "),              // code blocks
        ("\\[([^\\]]+)\\]\\([^)]*\\)", "$1"),   // links → their text
        ("(?m)^\\s*#+\\s*", ""),                // headings
        ("(?m)^\\s*>\\s?", ""),                 // quotes
        ("(?m)^\\s*([-*•]|\\d+\\.)\\s+", ""),   // list markers
        ("\\*\\*|__|`", ""),                    // bold, code ticks
        ("\\|", " "),                           // table pipes
        ("\\s+", " "),
    ]
    for (pattern, replacement) in rules {
        t = t.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
    }
    t = t.trimmingCharacters(in: .whitespaces)
    if t.count <= max { return t }
    let head = String(t.prefix(max))
    // Prefer ending on a full sentence if there's a decent one.
    if let r = head.range(of: "[.!?](?=\\s)", options: [.regularExpression, .backwards]),
       head.distance(from: head.startIndex, to: r.lowerBound) > 40 {
        return String(head[...r.lowerBound])
    }
    if let sp = head.lastIndex(of: " ") { return String(head[..<sp]) + "…" }
    return head + "…"
}

func handleHook() -> Never {
    // Hooks must never block Claude or print anything: UserPromptSubmit's
    // stdout would be added to Claude's context.
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { exit(0) }
    let event = j["hook_event_name"] as? String ?? ""

    var info: [String: String] = [:]
    switch event {
    case "SessionStart": info = ["mood": "idle", "quiet": "1"]
    case "UserPromptSubmit": info = ["mood": "think", "quiet": "1"]
    case "PreToolUse": info = ["mood": "work", "quiet": "1"]
    case "Notification":
        let msg = (j["message"] as? String) ?? "Claude needs you"
        info = ["mood": "needs", "text": tidy(msg)]
    case "Stop":
        // A short pause gives the transcript time to catch up with the final reply.
        var reply = lastAssistantText(j)
        if reply == nil { Thread.sleep(forTimeInterval: 0.4); reply = lastAssistantText(j) }
        info = ["mood": "done", "text": tidy(reply ?? "All done!")]
    case "SessionEnd": info = ["mood": "sleep", "quiet": "1"]
    default: exit(0)
    }

    if !isRunning() {
        // Respect `petsay --quit`; otherwise wake the cat up.
        if prefs.bool(forKey: "stayQuit") { exit(0) }
        guard ensureRunning() else { exit(0) }
    }
    post(info)
    exit(0)
}

// MARK: - Arguments

var mood: String?
var seconds: String?
var theme: String?
var quit = false, hide = false, hook = false
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
    case "--hook": hook = true
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

if let m = mood, !moods.contains(m) { fail("Unknown mood '\(m)'. Try: \(moods.joined(separator: ", "))") }
if let t = theme, !themes.contains(t) { fail("Unknown theme '\(t)'. Try: \(themes.joined(separator: ", "))") }

var text = words.joined(separator: " ")
if text.isEmpty && mood == nil && theme == nil && !hide && isatty(STDIN_FILENO) == 0 {
    text = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}
if text.isEmpty && mood == nil && theme == nil && !hide { usage() }

guard ensureRunning() else { fail("Couldn't find or start Touch_Bar_Pet.app. Run install.sh first.") }

if let t = theme { post(["command": "theme", "theme": t]) }
if hide { post(["command": "hide"]) }
if !text.isEmpty || mood != nil {
    var info: [String: String] = [:]
    if !text.isEmpty { info["text"] = text }
    if let mood { info["mood"] = mood }
    if let seconds { info["seconds"] = seconds }
    post(info)
}
