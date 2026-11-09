// Reads what the Claude app knows about each chat: its title and whether it's been
// archived. Read-only, and watched for changes rather than polled.
//
// These files are private to Claude and an update could change them. If they can't
// be read, every lookup finds nothing and the cat falls back to folder names and
// watching each Claude's process.

import Foundation

struct ClaudeChat: Decodable {
    let sessionId: String
    let cliSessionId: String?
    let cwd: String?
    let priorCliSessionIds: [String]?
    let title: String?
    let isArchived: Bool?
    let lastActivityAt: Double?
    let lastAssistantUuid: String?
    let postTurnSummaryFor: String?
    let postTurnSummary: Summary?
    let turnWrapUp: WrapUp?

    struct Summary: Decodable {
        let status_category: String?
        let status_detail: String?
        let needs_action: String?
    }

    struct WrapUp: Decodable {
        let description: String?
        let needsUser: String?
    }

    /// A summary describes one turn, so one left over from an earlier turn doesn't count.
    private var summary: Summary? {
        guard let id = lastAssistantUuid, id == postTurnSummaryFor else { return nil }
        return postTurnSummary
    }

    /// What this chat wants from you, if its last turn left you something to do.
    /// Finished chats with nothing to do answer nil, and never make the cat nag.
    var wants: String? {
        func text(_ s: String?) -> String? {
            let t = s?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return t.isEmpty ? nil : t
        }
        if let asked = text(turnWrapUp?.needsUser) { return asked }
        guard let summary else { return nil }
        if let action = text(summary.needs_action) { return action }
        return summary.status_category == "blocked" ? text(summary.status_detail) ?? "Needs you" : nil
    }

    var lastActivity: Date { Date(timeIntervalSince1970: (lastActivityAt ?? 0) / 1000) }
}

final class ClaudeChats {
    private let root: URL
    private var stream: FSEventStreamRef?
    private var cache: [String: (modified: Date, chat: ClaudeChat)] = [:]
    /// By the ID hooks report as `session_id`.
    private var current: [String: ClaudeChat] = [:]
    /// By an ID the chat used before it was resumed or rewound.
    private var prior: [String: ClaudeChat] = [:]

    init(root: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions", isDirectory: true)) {
        self.root = root
        rescan()
        watch()
    }

    deinit {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    func chat(forHookSession id: String) -> ClaudeChat? { current[id] }

    /// Every chat that hasn't been archived.
    var open: [ClaudeChat] { cache.values.map(\.chat).filter { $0.isArchived != true } }

    /// The most recently active archived chats.
    func archived(limit: Int) -> [ClaudeChat] {
        Array(cache.values.map(\.chat).filter { $0.isArchived == true }
            .sorted { $0.lastActivity > $1.lastActivity }.prefix(limit))
    }

    /// True when this ID has been replaced: the chat now runs under a newer one.
    func isSuperseded(hookSession id: String) -> Bool { current[id] == nil && prior[id] != nil }

    private func rescan() {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        var seen: [String: (modified: Date, chat: ClaudeChat)] = [:]
        let decoder = JSONDecoder()

        // The layout is <account>/<org>/local_<uuid>.json.
        for account in (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [] {
            for org in (try? fm.contentsOfDirectory(at: account, includingPropertiesForKeys: nil)) ?? [] {
                let files = (try? fm.contentsOfDirectory(at: org, includingPropertiesForKeys: Array(keys))) ?? []
                for file in files where file.lastPathComponent.hasPrefix("local_") && file.pathExtension == "json" {
                    guard let modified = try? file.resourceValues(forKeys: keys).contentModificationDate else { continue }
                    if let old = cache[file.path], old.modified == modified {
                        seen[file.path] = old
                    } else if let data = try? Data(contentsOf: file),
                              let chat = try? decoder.decode(ClaudeChat.self, from: data) {
                        seen[file.path] = (modified, chat)
                    } else if let old = cache[file.path] {
                        seen[file.path] = old // caught mid-write: keep what we knew
                    }
                }
            }
        }

        cache = seen
        current = [:]
        prior = [:]
        for (_, entry) in seen {
            if let id = entry.chat.cliSessionId { current[id] = entry.chat }
            for id in entry.chat.priorCliSessionIds ?? [] { prior[id] = entry.chat }
        }
    }

    private func watch() {
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<ClaudeChats>.fromOpaque(info).takeUnretainedValue().rescan()
        }
        guard let made = FSEventStreamCreate(
            nil, callback, &context, [root.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 1.0,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNone)) else { return }
        FSEventStreamSetDispatchQueue(made, .main)
        FSEventStreamStart(made)
        stream = made
    }

    /// A chat's title, ready for the cat's note: on one line, without the 🟩/🟥 status
    /// marker, and short enough that "needs access" still fits. Nil if there's nothing left.
    static func displayTitle(_ title: String?, limit: Int = 44) -> String? {
        guard let title else { return nil }
        let markers: Set<Character> = ["🟩", "🟥"]
        var clean = title.unicodeScalars
            .filter { !CharacterSet.controlCharacters.contains($0) }
            .reduce(into: "") { $0.unicodeScalars.append($1) }
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        while let first = clean.first, markers.contains(first) {
            clean = String(clean.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        if clean.isEmpty { return nil }
        guard clean.count > limit else { return clean }
        let cut = String(clean.prefix(limit))
        // End on a whole word unless that would throw away most of the title.
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) >= limit / 2 {
            return String(cut[..<space]) + "…"
        }
        return cut + "…"
    }
}
