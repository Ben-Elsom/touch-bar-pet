// The window: every open Claude chat, sorted by what it needs from you. Laid out the
// way System Settings and Reminders are: inset groups, semantic colours and text
// styles, SF Symbols, and standard controls, so it follows light and dark mode, the
// accent colour and accessibility settings by itself.
//
// Titles and summaries come from Claude's files and are only ever shown as plain
// text. Links are built from validated session IDs, never taken from that text.

import AppKit

struct ChatRow: Equatable {
    enum Section: CaseIterable {
        case needs, running, awaiting
        var heading: String {
            switch self {
            case .needs: return "Needs Your Input"
            case .running: return "Currently Running"
            case .awaiting: return "Awaiting Next Step"
            }
        }
        var empty: String {
            switch self {
            case .needs: return "Nothing needs you."
            case .running: return "Nothing is running."
            case .awaiting: return "Nothing is waiting on a next step."
            }
        }
    }

    let key: String
    let localID: String?   // nil for a session the Claude app doesn't list
    let title: String
    let section: Section
    let since: Date
    let detail: String?
    let cwd: String?
    let movedByHand: Bool  // sits in Awaiting because Ben moved it there
    let canMove: Bool
    let isBlocked: Bool    // a live permission or question
}

/// `claude://claude.ai/epitaxy/local_<uuid>`, or nil if the ID isn't well formed.
func chatLink(_ id: String?) -> URL? {
    guard let id, id.range(of: "^local_[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$", options: .regularExpression) != nil
    else { return nil }
    return URL(string: "claude://claude.ai/epitaxy/\(id)")
}

func shortAgo(_ date: Date) -> String {
    let minutes = Int(Date().timeIntervalSince(date) / 60)
    if minutes < 1 { return "Now" }
    if minutes < 60 { return "\(minutes) min" }
    if minutes < 48 * 60 { return "\(minutes / 60) hr" }
    return "\(minutes / (24 * 60)) days"
}

// MARK: - Small views

/// An SF Symbol button with no border, the way a list row's actions look. The symbol
/// alone can't say what it does, so it always has a tooltip and a VoiceOver label.
private final class IconButton: NSButton {
    private var run: (() -> Void)?

    convenience init(symbol: String, label: String, tint: NSColor = .secondaryLabelColor,
                     pointSize: CGFloat = 14, _ run: @escaping () -> Void) {
        self.init(frame: .zero)
        self.run = run
        title = ""
        isBordered = false
        imagePosition = .imageOnly
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: .regular))
        contentTintColor = tint
        toolTip = label
        setAccessibilityLabel(label)
        target = self
        action = #selector(fire)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 26).isActive = true
        heightAnchor.constraint(equalToConstant: 26).isActive = true
    }

    @objc private func fire() { run?() }
}

/// A row that highlights under the pointer and, if it leads somewhere, opens on click.
/// The controls inside it still get their own clicks.
private final class RowView: NSView {
    private let onPress: (() -> Void)?
    private var hovering = false { didSet { needsDisplay = true } }
    private var pressed = false { didSet { needsDisplay = true } }

    init(onPress: (() -> Void)?) {
        self.onPress = onPress
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        guard onPress != nil else { return }
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect, .assumeInside],
            owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func mouseDown(with event: NSEvent) { pressed = onPress != nil }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        if pressed && inside { onPress?() }
        pressed = false
    }

    override func draw(_ dirtyRect: NSRect) {
        guard onPress != nil, hovering || pressed else { return }
        NSColor.labelColor.withAlphaComponent(pressed ? 0.10 : 0.05).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 4, dy: 3), xRadius: 6, yRadius: 6).fill()
    }
}

/// The rounded background behind a group of rows.
private final class GroupView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 10, yRadius: 10)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }
}

/// A hairline between rows, starting where the row's text starts.
private final class SeparatorView: NSView {
    static let inset: CGFloat = 44

    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 1) }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        let scale = window?.backingScaleFactor ?? 2
        NSRect(x: Self.inset, y: 0, width: bounds.width - Self.inset, height: 1 / scale).fill()
    }
}

/// The cat, doing whatever it's doing on the Touch Bar, drawn with crisp pixels.
private final class CatView: NSView {
    private let pet: Pet
    private let sheet: SpriteSheet
    private let scale: CGFloat = 3
    private var drawn: (Anim, Int)?

    init(pet: Pet, sheet: SpriteSheet) {
        self.pet = pet
        self.sheet = sheet
        super.init(frame: .zero)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: NSSize { NSSize(width: artWidth * scale + 8, height: 66) }

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    func step() {
        let now = (pet.anim, reduceMotion ? 0 : pet.frame)
        if drawn?.0 != now.0 || drawn?.1 != now.1 { needsDisplay = true }
    }

    override func draw(_ dirtyRect: NSRect) {
        let frame = reduceMotion ? 0 : pet.frame
        drawn = (pet.anim, frame)
        guard let ctx = NSGraphicsContext.current?.cgContext, let image = sheet.image(pet.anim, frame) else { return }
        ctx.interpolationQuality = .none
        let size = CGFloat(frameSize) * scale
        ctx.draw(image, in: CGRect(x: 4 - artLeft * scale, y: 0, width: size, height: size))
    }
}

private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - The window

final class AppWindow: NSObject, NSWindowDelegate {
    private let sessions: Sessions
    private let catView: CatView
    private var window: NSWindow?
    private let stack = NSStackView()
    private let headline = NSTextField(labelWithString: "")
    private let subhead = NSTextField(labelWithString: "")
    private var header: NSView?
    private var shown: [ChatRow] = []
    private var shownArchived: [String] = []
    private var lastAgoRefresh = Date.distantPast
    private var showArchived = false

    init(sessions: Sessions, pet: Pet, sheet: SpriteSheet) {
        self.sessions = sessions
        catView = CatView(pet: pet, sheet: sheet)
    }

    var isOpen: Bool { window?.isVisible == true }

    func show() {
        if window == nil { build() }
        NSApp.setActivationPolicy(.regular)
        reload(force: true)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        // Back to living only on the Touch Bar, with no Dock icon.
        NSApp.setActivationPolicy(.accessory)
    }

    /// The menus every Mac app has. They only show while the window is open.
    static func installMenus() {
        let name = "Touch Bar Pet"
        let main = NSMenu()

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About \(name)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide \(name)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(name)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")

        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu

        for (title, menu) in [(name, appMenu), ("File", fileMenu), ("Window", windowMenu)] {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = menu
            main.addItem(item)
        }
        NSApp.mainMenu = main
    }

    private func build() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 680),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                         backing: .buffered, defer: false)
        w.title = "Touch Bar Pet"
        w.minSize = NSSize(width: 480, height: 360)
        w.isReleasedWhenClosed = false
        w.delegate = self
        w.center()
        w.setFrameAutosaveName("Touch Bar Pet")

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 20, bottom: 24, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let document = FlippedView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.documentView = document
        w.contentView = scroll

        NSLayoutConstraint.activate([
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: document.topAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor),
        ])

        headline.font = .systemFont(ofSize: 22, weight: .bold)
        headline.lineBreakMode = .byTruncatingTail
        subhead.font = .preferredFont(forTextStyle: .body)
        subhead.textColor = .secondaryLabelColor
        let words = NSStackView(views: [headline, subhead])
        words.orientation = .vertical
        words.alignment = .leading
        words.spacing = 2
        let top = NSStackView(views: [catView, words])
        top.spacing = 12
        top.alignment = .centerY
        header = top
        window = w
    }

    /// Keeps the cat in the header moving. Called on every animation tick.
    func stepCat() {
        if isOpen { catView.step() }
    }

    /// Called about once a second. Rebuilds only when something changed, or once a
    /// minute so "how long" stays true.
    func reload(force: Bool = false) {
        guard force || isOpen else { return }
        let rows = sessions.rows()
        let archived = sessions.recentlyArchived()
        let stale = Date().timeIntervalSince(lastAgoRefresh) > 60
        guard force || stale || rows != shown || archived.map(\.sessionId) != shownArchived else { return }
        shown = rows
        shownArchived = archived.map(\.sessionId)
        lastAgoRefresh = Date()

        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        updateHeader(rows)
        if let header { add(header, spaceAfter: 22) }
        for section in ChatRow.Section.allCases {
            let inSection = rows.filter { $0.section == section }
            add(sectionHeading(section.heading, count: inSection.count), spaceAfter: 6)
            add(group(inSection.isEmpty ? [emptyRow(section.empty)] : inSection.map(view(for:))), spaceAfter: 22)
        }
        add(archivedHeading(count: archived.count), spaceAfter: 6)
        if showArchived {
            add(group(archived.isEmpty ? [emptyRow("Nothing archived yet.")] : archived.map(view(forArchived:))))
        }
    }

    private func updateHeader(_ rows: [ChatRow]) {
        let count = { (s: ChatRow.Section) in rows.filter { $0.section == s }.count }
        let needs = count(.needs), running = count(.running), awaiting = count(.awaiting)
        if needs > 0 {
            headline.stringValue = needs == 1 ? "1 chat needs you" : "\(needs) chats need you"
        } else if running > 0 {
            headline.stringValue = running == 1 ? "A chat is working" : "\(running) chats are working"
        } else {
            headline.stringValue = "All caught up"
        }
        var parts: [String] = []
        if needs > 0 && running > 0 { parts.append("\(running) running") }
        if awaiting > 0 { parts.append("\(awaiting) awaiting a next step") }
        subhead.stringValue = parts.isEmpty ? "Nothing is waiting on you." : parts.joined(separator: " · ")
    }

    private func add(_ view: NSView, spaceAfter: CGFloat? = nil) {
        stack.addArrangedSubview(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40).isActive = true
        if let spaceAfter { stack.setCustomSpacing(spaceAfter, after: view) }
    }

    // MARK: Building blocks

    private func label(_ s: String, style: NSFont.TextStyle, color: NSColor = .labelColor) -> NSTextField {
        let t = NSTextField(labelWithString: s)
        t.font = .preferredFont(forTextStyle: style)
        t.textColor = color
        t.lineBreakMode = .byTruncatingTail
        t.cell?.usesSingleLineMode = true
        t.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        t.setContentHuggingPriority(.init(1), for: .horizontal)
        return t
    }

    private func sectionHeading(_ title: String, count: Int) -> NSView {
        let name = label(title, style: .headline)
        name.setContentHuggingPriority(.required, for: .horizontal)
        let number = label(String(count), style: .headline, color: .secondaryLabelColor)
        let line = NSStackView(views: [name, number])
        line.spacing = 6
        line.edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 0)
        return line
    }

    /// Past chats are rarely what you came for, so they start folded away.
    private func archivedHeading(count: Int) -> NSView {
        let toggle = NSButton(title: "", target: self, action: #selector(toggleArchived))
        toggle.bezelStyle = .disclosure
        toggle.setButtonType(.pushOnPushOff)
        toggle.state = showArchived ? .on : .off
        toggle.setAccessibilityLabel("Recently Archived")
        let name = label("Recently Archived", style: .headline)
        let line = NSStackView(views: [toggle, name])
        line.spacing = 4
        line.edgeInsets = NSEdgeInsets(top: 0, left: 2, bottom: 0, right: 0)
        return line
    }

    @objc private func toggleArchived() {
        showArchived.toggle()
        reload(force: true)
    }

    private func group(_ rows: [NSView]) -> NSView {
        let inner = NSStackView()
        inner.orientation = .vertical
        inner.spacing = 0
        inner.translatesAutoresizingMaskIntoConstraints = false
        for (i, row) in rows.enumerated() {
            if i > 0 {
                let line = SeparatorView()
                inner.addArrangedSubview(line)
                line.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true
            }
            inner.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: inner.widthAnchor).isActive = true
        }
        let box = GroupView()
        box.addSubview(inner)
        NSLayoutConstraint.activate([
            inner.topAnchor.constraint(equalTo: box.topAnchor, constant: 2),
            inner.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -2),
            inner.leadingAnchor.constraint(equalTo: box.leadingAnchor),
            inner.trailingAnchor.constraint(equalTo: box.trailingAnchor),
        ])
        return box
    }

    private func emptyRow(_ s: String) -> NSView {
        let line = NSStackView(views: [label(s, style: .body, color: .secondaryLabelColor)])
        line.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 14)
        return line
    }

    /// Status is said by the symbol's shape as well as its colour.
    private func statusView(for row: ChatRow) -> NSView {
        if row.section == .running {
            let spinner = NSProgressIndicator()
            spinner.style = .spinning
            spinner.controlSize = .small
            spinner.startAnimation(nil)
            spinner.setAccessibilityLabel("Running")
            return fixedWidth(spinner)
        }
        let symbol: String, tint: NSColor, description: String
        switch (row.section, row.isBlocked) {
        case (.needs, true): (symbol, tint, description) = ("hand.raised.fill", .systemOrange, "Blocked")
        case (.needs, false): (symbol, tint, description) = ("bubble.left.fill", .systemBlue, "Needs you")
        default: (symbol, tint, description) = ("checkmark.circle", .tertiaryLabelColor, "Finished")
        }
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: description) ?? NSImage())
        icon.symbolConfiguration = .init(pointSize: 15, weight: .regular)
        icon.contentTintColor = tint
        return fixedWidth(icon)
    }

    /// Every status takes the same width, so all the titles line up.
    private func fixedWidth(_ view: NSView) -> NSView {
        view.translatesAutoresizingMaskIntoConstraints = false
        let box = NSView()
        box.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(view)
        NSLayoutConstraint.activate([
            box.widthAnchor.constraint(equalToConstant: 22),
            box.heightAnchor.constraint(equalToConstant: 22),
            view.centerXAnchor.constraint(equalTo: box.centerXAnchor),
            view.centerYAnchor.constraint(equalTo: box.centerYAnchor),
        ])
        return box
    }

    private func rowFrame(_ content: [NSView], link: URL?, tooltip: String?) -> NSView {
        let row = RowView(onPress: link.map { url in { NSWorkspace.shared.open(url) } })
        let line = NSStackView(views: content)
        line.spacing = 8
        line.alignment = .centerY
        line.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(line)
        row.toolTip = tooltip
        NSLayoutConstraint.activate([
            line.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 14),
            line.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -8),
            line.topAnchor.constraint(equalTo: row.topAnchor, constant: 8),
            line.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -8),
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
        ])
        return row
    }

    private func openButton(_ link: URL) -> NSView {
        IconButton(symbol: "chevron.right", label: "Open Chat", tint: .tertiaryLabelColor, pointSize: 12) {
            NSWorkspace.shared.open(link)
        }
    }

    private func timeLabel(_ date: Date) -> NSTextField {
        let time = label(shortAgo(date), style: .subheadline, color: .secondaryLabelColor)
        time.setContentCompressionResistancePriority(.required, for: .horizontal)
        time.setContentHuggingPriority(.required, for: .horizontal)
        return time
    }

    private func view(for row: ChatRow) -> NSView {
        let words = NSStackView(views: [label(row.title, style: .body)])
        words.orientation = .vertical
        words.alignment = .leading
        words.spacing = 1
        if let detail = row.detail, !detail.isEmpty {
            words.addArrangedSubview(label(detail, style: .subheadline, color: .secondaryLabelColor))
        }
        words.setContentHuggingPriority(.init(1), for: .horizontal)
        words.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        var content: [NSView] = [statusView(for: row), words, timeLabel(row.since)]
        if row.canMove, let id = row.localID {
            if row.section == .needs {
                content.append(IconButton(symbol: "bell.slash", label: "Move to Awaiting Next Step") { [weak self] in
                    self?.sessions.move(chat: id, toAwaiting: true)
                    self?.reload(force: true)
                })
            } else if row.movedByHand {
                content.append(IconButton(symbol: "bell", label: "Move Back to Needs Your Input") { [weak self] in
                    self?.sessions.move(chat: id, toAwaiting: false)
                    self?.reload(force: true)
                })
            }
        }
        if row.localID != nil, row.section != .running {
            content.append(IconButton(symbol: "archivebox", label: "Archive…") { [weak self] in self?.archive(row) })
        }
        let link = chatLink(row.localID)
        if let link { content.append(openButton(link)) }
        return rowFrame(content, link: link, tooltip: row.detail)
    }

    private func view(forArchived chat: ClaudeChat) -> NSView {
        let icon = NSImageView(image: NSImage(systemSymbolName: "archivebox", accessibilityDescription: "Archived") ?? NSImage())
        icon.symbolConfiguration = .init(pointSize: 14, weight: .regular)
        icon.contentTintColor = .tertiaryLabelColor
        let title = label(ClaudeChats.displayTitle(chat.title, limit: 200) ?? "Untitled Chat", style: .body, color: .secondaryLabelColor)
        var content: [NSView] = [fixedWidth(icon), title, timeLabel(chat.lastActivity)]
        let link = chatLink(chat.sessionId)
        if let link { content.append(openButton(link)) }
        return rowFrame(content, link: link, tooltip: nil)
    }

    // MARK: Archiving

    /// Only a chat inside Claude can archive, so this warns about anything unfinished
    /// and then opens the chat for Ben to archive there.
    private func archive(_ row: ChatRow) {
        guard let window, let link = chatLink(row.localID) else { return }
        let changes = uncommittedFiles(in: row.cwd)
        let alert = NSAlert()
        alert.messageText = "Archive “\(row.title)” in Claude?"
        var body = "Touch Bar Pet can’t archive chats itself, so this opens the chat in Claude for you to archive there."
        if changes > 0 {
            alert.alertStyle = .warning
            body = "Its folder has \(changes) uncommitted file\(changes == 1 ? "" : "s").\n\n" + body
        }
        alert.informativeText = body
        alert.addButton(withTitle: "Open Chat")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { NSWorkspace.shared.open(link) }
        }
    }

    /// `git status`, run only at this moment. 0 if it isn't a repo or git can't say.
    private func uncommittedFiles(in folder: String?) -> Int {
        guard let folder, FileManager.default.fileExists(atPath: folder) else { return 0 }
        let git = Process()
        git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        git.arguments = ["-C", folder, "status", "--porcelain"]
        let out = Pipe()
        git.standardOutput = out
        git.standardError = Pipe()
        guard (try? git.run()) != nil else { return 0 }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        git.waitUntilExit()
        guard git.terminationStatus == 0 else { return 0 }
        return String(decoding: data, as: UTF8.self).split(separator: "\n").count
    }
}
