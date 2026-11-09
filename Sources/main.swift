// Touch Bar Pet: a little pixel cat that lives on the far left of the Touch Bar
// and shows what Claude Code is up to. It nags until you've dealt with everything:
// pawing with a note (a Claude is blocked), sitting with a note (a Claude has
// finished and is waiting for you), walking (nothing needs you, Claude is working)
// or asleep (nothing to do). Apple's Control Strip stays on the right.
//
// Sprite: "2D Pixel Art Cat Sprites" by Elthen (elthen.itch.io).

import AppKit

// MARK: - Identity & shared names (keep in sync with petsay.swift and Shared/CatMirrorView.swift)

let kBundleID = "com.benelsom.touchbarpet"
let kSayNote = Notification.Name("com.benelsom.touchbarpet.say")
/// Sent whenever the cat's state changes, so another app can show a copy of it.
let kStateNote = Notification.Name("com.benelsom.touchbarpet.state")
let kStateRequestNote = Notification.Name("com.benelsom.touchbarpet.stateRequest")
let kBarID = NSTouchBarItem.Identifier("com.benelsom.touchbarpet.bar")
/// Required by the present call; never added to the Control Strip.
let kTrayID = NSTouchBarItem.Identifier("com.benelsom.touchbarpet.tray")

/// Points per sprite pixel. The Touch Bar is a 2x display, so 2pt = 4×4 real pixels.
let artScale: CGFloat = 2
let frameSize = 32
/// The cat's art sits in columns 7–24 of each 32px frame.
let artLeft: CGFloat = 7
let artWidth: CGFloat = 18

// MARK: - Private DFRFoundation functions (looked up at runtime)

private let dfrHandle = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_NOW)

func dfrShowCloseBox(_ show: Bool) {
    typealias Fn = @convention(c) (Bool) -> Void
    guard let h = dfrHandle, let sym = dlsym(h, "DFRSystemModalShowsCloseBoxWhenFrontMost") else { return }
    unsafeBitCast(sym, to: Fn.self)(show)
}

// MARK: - Animations

struct Anim: Equatable {
    let row: Int
    let count: Int
    let fps: Double
}

enum Anims {
    static let sit = Anim(row: 0, count: 4, fps: 5)
    static let sitTwitch = Anim(row: 1, count: 4, fps: 6)
    static let clean = Anim(row: 2, count: 4, fps: 6)
    static let clean2 = Anim(row: 3, count: 4, fps: 6)
    static let walk = Anim(row: 4, count: 8, fps: 10)
    static let run = Anim(row: 5, count: 8, fps: 12)
    static let sleep = Anim(row: 6, count: 4, fps: 2.5)
    static let paw = Anim(row: 7, count: 6, fps: 8)
    static let jump = Anim(row: 8, count: 7, fps: 10)
    static let scared = Anim(row: 9, count: 8, fps: 10)
    /// Not in the sprite pack: the sitting tail-swish with a happy face, made by SpriteSheet.
    static let purr = Anim(row: 10, count: 4, fps: 5)
}

/// What the cat is doing. The first four are Claude's states.
enum Mood: String, CaseIterable {
    case inactive, waiting, working, needs, done, alert

    var bubble: NSColor {
        switch self {
        case .needs: return NSColor(srgbRed: 1.00, green: 0.88, blue: 0.55, alpha: 1)
        case .alert: return NSColor(srgbRed: 1.00, green: 0.78, blue: 0.78, alpha: 1)
        case .done: return NSColor(srgbRed: 0.80, green: 0.96, blue: 0.84, alpha: 1)
        default: return NSColor(white: 0.94, alpha: 1)
        }
    }

    /// Accepts the older names too (`idle`, `think`, `work`, `sleep`).
    static func parse(_ s: String) -> Mood? {
        switch s {
        case "idle", "think": return .waiting
        case "work": return .working
        case "sleep": return .inactive
        default: return Mood(rawValue: s)
        }
    }
}

// MARK: - Sprite sheet with palette themes

struct RGB: Hashable {
    var r: UInt8, g: UInt8, b: UInt8
    init(_ r: UInt8, _ g: UInt8, _ b: UInt8) { self.r = r; self.g = g; self.b = b }
}

enum Palette {
    static let outline = RGB(47, 47, 46)
    static let fur = RGB(224, 224, 224)
    static let shade = RGB(181, 181, 181)

    static let themes: [String: [RGB: RGB]] = [
        "grey": [:],
        "ginger": [fur: RGB(247, 172, 98), shade: RGB(214, 122, 60), outline: RGB(66, 38, 26)],
        "cream": [fur: RGB(252, 238, 214), shade: RGB(226, 196, 152), outline: RGB(74, 58, 44)],
        "blue": [fur: RGB(170, 182, 204), shade: RGB(128, 140, 166), outline: RGB(38, 42, 58)],
        "calico": [fur: RGB(250, 246, 238), shade: RGB(222, 150, 84), outline: RGB(48, 40, 36)],
    ]
}

final class SpriteSheet {
    private let source: CGImage
    private(set) var frames: [[CGImage]] = []
    private(set) var theme = "grey"

    init?(url: URL) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        source = img
        apply(theme: "grey")
    }

    func apply(theme name: String) {
        frames = makeFrames(Palette.themes[name] ?? [:])
        theme = Palette.themes[name] == nil ? "grey" : name
    }

    private func makeFrames(_ map: [RGB: RGB]) -> [[CGImage]] {
        let w = source.width, h = source.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        ctx.draw(source, in: CGRect(x: 0, y: 0, width: w, height: h))
        if !map.isEmpty, let data = ctx.data {
            let p = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
            for i in stride(from: 0, to: w * h * 4, by: 4) where p[i + 3] == 255 {
                for (from, to) in map where abs(Int(p[i]) - Int(from.r)) <= 6
                    && abs(Int(p[i + 1]) - Int(from.g)) <= 6 && abs(Int(p[i + 2]) - Int(from.b)) <= 6 {
                    p[i] = to.r; p[i + 1] = to.g; p[i + 2] = to.b
                    break
                }
            }
        }
        guard let img = ctx.makeImage() else { return [] }
        var rows = (0..<(img.height / frameSize)).map { r in
            (0..<(img.width / frameSize)).compactMap { c in
                img.cropping(to: CGRect(x: c * frameSize, y: r * frameSize, width: frameSize, height: frameSize))
            }
        }
        // Row 10 (Anims.purr): the sitting frames with closed eyes and a blush.
        let outline = map[Palette.outline] ?? Palette.outline
        if let sitting = rows.first { rows.append(sitting.compactMap { happyFace($0, outline: outline) }) }
        return rows
    }

    private func happyFace(_ frame: CGImage, outline: RGB) -> CGImage? {
        guard let c = CGContext(data: nil, width: frameSize, height: frameSize, bitsPerComponent: 8,
                                bytesPerRow: frameSize * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = c.data else { return nil }
        c.draw(frame, in: CGRect(x: 0, y: 0, width: frameSize, height: frameSize))
        let p = data.bindMemory(to: UInt8.self, capacity: frameSize * frameSize * 4)
        func put(_ x: Int, _ y: Int, _ rgb: RGB) {
            let i = (y * frameSize + x) * 4
            p[i] = rgb.r; p[i + 1] = rgb.g; p[i + 2] = rgb.b; p[i + 3] = 255
        }
        let blush = RGB(222, 117, 134)
        put(15, 23, outline); put(16, 23, outline) // eyes closed
        put(15, 24, blush); put(19, 24, blush)
        return c.makeImage()
    }

    func image(_ anim: Anim, _ frame: Int) -> CGImage? {
        guard anim.row < frames.count, frame < frames[anim.row].count else { return nil }
        return frames[anim.row][frame]
    }
}

// MARK: - The pet's little brain

final class Pet {
    private(set) var mood: Mood = .inactive
    private(set) var anim = Anims.sleep
    private(set) var frame = 0
    private var acc = 0.0
    private var loopsLeft = 10
    private var purrLeft = 0.0

    var isPurring: Bool { purrLeft > 0 }

    func set(mood new: Mood) {
        guard new != mood else { return }
        // Clearing the last thing that needed you earns a little celebratory hop.
        let celebrate = (mood == .needs || mood == .waiting) && (new == .working || new == .inactive)
        mood = new
        if isPurring { return } // a cat being petted finishes enjoying it first
        start(celebrate ? (Anims.jump, 1) : nextAnim())
    }

    func playOnce(_ a: Anim) {
        if !isPurring { start((a, 1)) }
    }

    /// Being petted: purr for at least this long.
    func purr(for seconds: Double) {
        if !isPurring { start((Anims.purr, Int.max)) }
        purrLeft = max(purrLeft, seconds)
    }

    /// The hand has lifted: purr on for a moment, then go back to normal.
    func handLifted(tail: Double = 2.5) {
        if isPurring { purrLeft = min(purrLeft, tail) }
    }

    private func start(_ next: (Anim, Int)) {
        anim = next.0
        loopsLeft = next.1
        frame = 0
        acc = 0
    }

    private func nextAnim() -> (Anim, Int) {
        switch mood {
        case .waiting:
            let roll = Int.random(in: 0..<10)
            if roll < 6 { return (Anims.sit, 3) }
            if roll < 8 { return (Anims.sitTwitch, 2) }
            return (Bool.random() ? Anims.clean : Anims.clean2, 2)
        case .working: return (Anims.walk, 4)
        case .needs: return (Anims.paw, 3)
        case .done: return (Anims.jump, 1)
        case .alert: return (Anims.scared, 2)
        case .inactive: return (Anims.sleep, 10)
        }
    }

    /// Advances the animation. Returns true if the frame changed.
    func tick(_ dt: Double) -> Bool {
        var changed = false
        if isPurring {
            purrLeft -= dt
            if purrLeft <= 0 {
                purrLeft = 0
                start(nextAnim())
                changed = true
            }
        }
        acc += dt
        let spf = 1 / anim.fps
        while acc >= spf {
            acc -= spf
            frame += 1
            changed = true
            if frame >= anim.count {
                frame = 0
                loopsLeft -= 1
                if loopsLeft <= 0 { start(nextAnim()) }
            }
        }
        return changed
    }
}

// MARK: - Claude sessions → one state for the cat

/// Anything needing you outranks anything working, and it stays until that Claude
/// is answered or closed: walking is what you earn by clearing the list.
final class Sessions {
    enum State: String, Codable {
        case fresh      // opened, nothing asked of it yet
        case waiting    // finished its turn, waiting for you
        case working
        case needs      // blocked on a permission or a question
    }

    struct Session: Codable {
        var state: State
        var project: String
        var note: String?      // "needs access" / "needs help"
        var tool: String?      // the tool it's blocked on
        var pid: Int32         // the Claude process, so we notice when it's gone
        var updated: Date
    }

    /// A turn that's stopped sending events was probably interrupted (those never
    /// send Stop). Longer than the longest foreground command.
    private static let workingLimit: TimeInterval = 11 * 60
    /// Only for sessions whose process we couldn't identify.
    private static let unknownLimit: TimeInterval = 24 * 60 * 60

    private var all: [String: Session] = [:]

    private let file: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Touch_Bar_Pet", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("sessions.json")
    }()

    init() {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let data = try? Data(contentsOf: file), let saved = try? dec.decode([String: Session].self, from: data) {
            all = saved
        }
    }

    /// Kept on disk so a restart of the pet doesn't forget who's waiting on you.
    private func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(all) { try? data.write(to: file, options: .atomic) }
    }

    func clear() {
        all = [:]
        save()
    }

    func handle(hook: String, session id: String, project: String, kind: String?, tool: String?, pid: Int32) {
        let now = Date()
        let old = all[id]
        let pid = pid > 0 ? pid : old?.pid ?? 0
        func set(_ state: State, note: String? = nil, tool: String? = nil) {
            all[id] = Session(state: state, project: project, note: note, tool: tool, pid: pid, updated: now)
        }

        switch hook {
        case "SessionEnd":
            all[id] = nil
        case "SessionStart":
            // Also fires on resume and after compacting, which change nothing.
            if old == nil { set(.fresh) } else { all[id]?.pid = pid }
        case "Stop", "StopFailure":
            set(.waiting)
        case "UserPromptSubmit":
            set(.working)
        case "PreToolUse", "PostToolUse", "PostToolUseFailure":
            if let old, old.state == .needs {
                // Hooks are separate processes, so this tool's PreToolUse can land
                // just after its permission request.
                if hook == "PreToolUse" && now.timeIntervalSince(old.updated) < 1.5 { return }
                // Another tool running alongside doesn't unblock this one.
                if hook != "PreToolUse", let blockedOn = old.tool, blockedOn != tool { return }
            }
            set(.working)
        case "Notification":
            // The generic notification follows the specific request, which knows more.
            if old?.state == .needs && tool == nil { return }
            switch kind {
            case "idle":
                if old?.state != .needs { set(.waiting) }
            case "access":
                set(.needs, note: "needs access", tool: tool)
            default:
                set(.needs, note: "needs help", tool: tool)
            }
        default:
            return
        }
        save()
    }

    /// Forgets Claudes that have exited, and stops treating a silent turn as working.
    private func tidy() {
        let now = Date()
        var changed = false
        for (id, s) in all {
            let age = now.timeIntervalSince(s.updated)
            if s.pid > 0 ? (kill(s.pid, 0) != 0 && errno == ESRCH) : age > Self.unknownLimit {
                all[id] = nil
                changed = true
            } else if s.state == .working && age > Self.workingLimit {
                all[id]?.state = .waiting
                changed = true
            }
        }
        if changed { save() }
    }

    /// The most urgent state across every session, and the note to show with it.
    func summary() -> (Mood, String?) {
        tidy()
        // Oldest first, so the note doesn't jump around as others finish.
        let sessions = all.values.sorted { ($0.updated, $0.project) < ($1.updated, $1.project) }
        let blocked = sessions.filter { $0.state == .needs }
        let waiting = sessions.filter { $0.state == .waiting }
        let count = blocked.count + waiting.count
        let several = "\(count) Claudes need you"
        if let first = blocked.first {
            return (.needs, count == 1 ? "\(first.project) \(first.note ?? "needs help")" : several)
        }
        if let first = waiting.first {
            return (.waiting, count == 1 ? "\(first.project) needs you" : several)
        }
        return (sessions.contains { $0.state == .working } ? .working : .inactive, nil)
    }
}

// MARK: - Drawing helpers

func drawCat(_ ctx: CGContext, sheet: SpriteSheet, anim: Anim, frame: Int, x: CGFloat, flipped: Bool = false) {
    guard let img = sheet.image(anim, frame) else { return }
    ctx.saveGState()
    ctx.interpolationQuality = .none
    let size = CGFloat(frameSize) * artScale
    var rect = CGRect(x: x - artLeft * artScale, y: 0, width: size, height: size)
    if flipped {
        // Mirror around the art's centre so the cat turns on the spot.
        let mid = x + artWidth * artScale / 2
        ctx.translateBy(x: mid, y: 0)
        ctx.scaleBy(x: -1, y: 1)
        ctx.translateBy(x: -mid, y: 0)
        rect.origin.x = x - artLeft * artScale
    }
    ctx.draw(img, in: rect)
    ctx.restoreGState()
}

func drawZzz(at x: CGFloat, baseY: CGFloat, time: Double) {
    for i in 0..<3 {
        let phase = (time * 0.45 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
        let alpha = sin(phase * .pi) * 0.85
        let size = 6 + phase * 4
        let s = NSAttributedString(string: "z", attributes: [
            .font: roundedFont(size: size, weight: .heavy),
            .foregroundColor: NSColor(white: 0.85, alpha: alpha),
        ])
        s.draw(at: NSPoint(x: x + phase * 7, y: baseY + phase * 14))
    }
}

/// A tiny pixel heart, drawn with crisp square pixels.
private let heartRows = [".XX.XX.", "XXXXXXX", "XXXXXXX", ".XXXXX.", "..XXX..", "...X..."]

func drawHeart(_ ctx: CGContext, x: CGFloat, y: CGFloat, alpha: CGFloat, px: CGFloat = 1.5) {
    ctx.setFillColor(NSColor(srgbRed: 0.93, green: 0.42, blue: 0.53, alpha: alpha).cgColor)
    for (r, row) in heartRows.enumerated() {
        for (c, ch) in row.enumerated() where ch == "X" {
            ctx.fill(CGRect(x: x + CGFloat(c) * px, y: y + CGFloat(heartRows.count - 1 - r) * px, width: px, height: px))
        }
    }
}

func roundedFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    if let d = base.fontDescriptor.withDesign(.rounded), let f = NSFont(descriptor: d, size: size) { return f }
    return base
}

struct Heart { var x: CGFloat; var y: CGFloat; var age: Double }

// MARK: - The bar view: cat on the left, a short note beside it when needed

final class BarView: NSView {
    let pet: Pet
    let sheet: SpriteSheet
    var onTap: ((NSPoint) -> Void)?
    var onPetStart: (() -> Void)?
    var onPetEnd: (() -> Void)?
    private var petting = false
    var desiredWidth: CGFloat

    private(set) var note: String?
    private var noteMood: Mood = .needs
    private var noteT = 0.0
    private var time = 0.0
    private var hearts: [Heart] = []

    // Pacing while working.
    private let homeX: CGFloat = 6
    private let paceWidth: CGFloat = 70
    private var catX: CGFloat = 6
    private var facingLeft = false

    var bubbleX: CGFloat { homeX + artWidth * artScale + 4 }
    let bubbleH: CGFloat = 24
    let pad: CGFloat = 11
    let font = roundedFont(size: 14, weight: .semibold)

    init(pet: Pet, sheet: SpriteSheet, width: CGFloat) {
        self.pet = pet
        self.sheet = sheet
        self.desiredWidth = width
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 30))
        allowedTouchTypes = [.direct]
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: desiredWidth, height: 30) }

    /// A little generous, since a fingertip is bigger than the cat.
    private func isOnCat(_ p: NSPoint) -> Bool {
        var right = catX + artWidth * artScale + 8
        if note != nil { right = min(right, bubbleX) }
        return p.x >= catX - 8 && p.x <= right
    }

    override func touchesBegan(with event: NSEvent) {
        guard let t = event.touches(matching: .began, in: self).first else { return }
        if isOnCat(t.location(in: self)) {
            petting = true
            onPetStart?()
        }
    }

    override func touchesEnded(with event: NSEvent) {
        guard let t = event.touches(matching: .ended, in: self).first else { return }
        if petting {
            petting = false
            onPetEnd?()
        } else {
            onTap?(t.location(in: self))
        }
    }

    override func touchesCancelled(with event: NSEvent) {
        if petting {
            petting = false
            onPetEnd?()
        }
    }

    func setNote(_ text: String?, mood: Mood) {
        if text != note { noteT = 0 }
        note = text
        noteMood = mood
    }

    func addHeart() {
        hearts.append(Heart(x: catX + 24 + CGFloat.random(in: -4...4), y: 18, age: 0))
    }

    var catFrameX: CGFloat { catX }

    private var heartTimer = 0.0

    /// Advances everything. Returns true if something on screen moved besides
    /// the sprite's own frame, so idle moments don't redraw for nothing.
    func update(_ dt: Double) -> Bool {
        let startX = catX
        time += dt
        noteT += dt
        if pet.isPurring {
            // Stay put and enjoy it, with a heart now and then.
            heartTimer -= dt
            if heartTimer <= 0 {
                heartTimer = 0.55
                addHeart()
            }
        } else if pet.anim == Anims.walk && note == nil {
            let speed: CGFloat = 22 // points per second
            catX += (facingLeft ? -speed : speed) * CGFloat(dt)
            if catX > homeX + paceWidth { catX = homeX + paceWidth; facingLeft = true }
            if catX < homeX { catX = homeX; facingLeft = false }
        } else if catX != homeX {
            // Trot home, then face right again.
            let step = 40 * CGFloat(dt)
            if abs(catX - homeX) <= step { catX = homeX; facingLeft = false } else { catX -= step; facingLeft = true }
        }
        hearts = hearts.compactMap { var h = $0; h.age += dt; h.y += CGFloat(dt * 9); return h.age < 1.4 ? h : nil }
        let typing = note.map { noteT < 0.3 + Double($0.count) / 40 } ?? false
        return catX != startX || !hearts.isEmpty || typing || pet.isPurring || pet.anim == Anims.sleep
    }

    private func attributed(_ s: String) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: NSColor(white: 0.08, alpha: 1)])
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        let walkingHome = catX != homeX && pet.anim != Anims.walk && !pet.isPurring
        let anim = walkingHome ? Anims.walk : pet.anim
        let frame = walkingHome ? Int(time * 10) % Anims.walk.count : pet.frame
        // The purr itself: a shiver of one real pixel (the Touch Bar is 2x).
        let shiver: CGFloat = pet.isPurring && Int(time * 15) % 2 == 0 ? 0.5 : 0
        drawCat(ctx, sheet: sheet, anim: anim, frame: frame, x: catX + shiver, flipped: facingLeft)
        if pet.anim == Anims.sleep { drawZzz(at: catX + 30, baseY: 10, time: time) }
        for h in hearts { drawHeart(ctx, x: h.x, y: h.y, alpha: CGFloat(1 - h.age / 1.4)) }
        if pet.isPurring && note == nil {
            let phase = (time * 0.7).truncatingRemainder(dividingBy: 1)
            let s = NSAttributedString(string: "prr", attributes: [
                .font: roundedFont(size: 10, weight: .heavy),
                .foregroundColor: NSColor(white: 0.85, alpha: sin(phase * .pi) * 0.9),
            ])
            s.draw(at: NSPoint(x: catX + 40 + phase * 6, y: 8 + phase * 8))
        }

        guard let note, !note.isEmpty, catX == homeX else { return }

        // Bubble pops open, then the note types out.
        let pop = min(1, noteT / 0.18)
        let eased = 1 - pow(1 - pop, 3)
        let maxInner = max(40, bounds.width - bubbleX - 6 - pad * 2)
        let textW = min(ceil(attributed(note).size().width), maxInner)
        let bw = max(bubbleH, (textW + pad * 2) * CGFloat(eased))
        let by = (bounds.height - bubbleH) / 2
        let rect = NSRect(x: bubbleX, y: by, width: bw, height: bubbleH)

        noteMood.bubble.setFill()
        NSBezierPath(roundedRect: rect, xRadius: bubbleH / 2, yRadius: bubbleH / 2).fill()
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: bubbleX + 4, y: by + 9))
        tail.line(to: NSPoint(x: bubbleX - 7, y: by + 15))
        tail.line(to: NSPoint(x: bubbleX + 6, y: by + 17))
        tail.close()
        tail.fill()

        guard pop >= 1 else { return }
        let chars = Array(note)
        let typed = min(chars.count, max(0, Int((noteT - 0.18) * 40)))
        let inner = NSRect(x: bubbleX + pad, y: by, width: bw - pad * 2, height: bubbleH)
        ctx.saveGState()
        ctx.clip(to: inner)
        let s = attributed(String(chars.prefix(typed)))
        s.draw(at: NSPoint(x: inner.minX, y: by + (bubbleH - s.size().height) / 2))
        ctx.restoreGState()
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    var sheet: SpriteSheet!
    let pet = Pet()
    let sessions = Sessions()
    let bar = NSTouchBar()
    var barView: BarView!
    var timer: Timer?
    var lastTick = CACurrentMediaTime()
    var activity: NSObjectProtocol?
    let defaults = UserDefaults.standard
    var summaryCheck = 0.0
    var claude: (mood: Mood, note: String?) = (.inactive, nil)
    var lastPublished: [String: String] = [:]

    /// A message sent with `petsay "..."`, shown until it expires.
    var manual: (text: String, mood: Mood, until: Date)?

    /// 0 keeps Apple's Control Strip on the right; 1 would take the whole bar.
    var placement: Int64 { Int64(defaults.object(forKey: "placement") as? Int ?? 0) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: kBundleID)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if !others.isEmpty { NSLog("TouchBarPet: already running"); NSApp.terminate(nil); return }

        guard let url = Bundle.main.url(forResource: "Cat_Sprite_Sheet", withExtension: "png"),
              let s = SpriteSheet(url: url) else {
            NSLog("TouchBarPet: sprite sheet missing")
            NSApp.terminate(nil)
            return
        }
        sheet = s
        sheet.apply(theme: defaults.string(forKey: "theme") ?? "grey")

        let width = CGFloat(defaults.object(forKey: "barWidth") as? Double ?? 560)
        barView = BarView(pet: pet, sheet: sheet, width: width)
        barView.onTap = { [weak self] p in self?.tapped(p) }
        barView.onPetStart = { [weak self] in self?.pet.purr(for: 30) }
        barView.onPetEnd = { [weak self] in self?.pet.handLifted() }
        let item = NSCustomTouchBarItem(identifier: kBarID)
        item.view = barView
        bar.templateItems = [item]
        bar.defaultItemIdentifiers = [kBarID]
        dfrShowCloseBox(false)

        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(received(_:)), name: kSayNote, object: nil,
            suspensionBehavior: .deliverImmediately)
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(stateRequested), name: kStateRequestNote, object: nil,
            suspensionBehavior: .deliverImmediately)

        // The Touch Bar can drop our bar after sleep; put it back.
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(reshow), name: NSWorkspace.didWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(reshow), name: NSWorkspace.screensDidWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(reshow), name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)

        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep], reason: "Animating the Touch Bar pet")
        let t = Timer(timeInterval: 1.0 / 15, repeats: true) { [weak self] _ in self?.tick() }
        t.tolerance = 0.02
        RunLoop.main.add(t, forMode: .common)
        timer = t

        present()
        NSLog("TouchBarPet: ready")
    }

    var lastPresent = Date.distantPast
    var lastShown: (Mood, String?) = (.inactive, nil)

    /// Shows the cat's bar. macOS adds an ⓧ to its left that we can't remove;
    /// tapping it hides the cat, so we put the bar back whenever Claude's state
    /// changes, and at least once a minute. Our bar sits beside the Control Strip,
    /// so a full-width bar like Better Narrator's stays on top of it.
    func present() {
        NSTouchBar.tbpPresentSystemModal(bar, placement: placement, systemTrayItemIdentifier: kTrayID)
        lastPresent = Date()
    }

    @objc func reshow() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.present() }
    }

    @objc func received(_ note: Notification) {
        let info = note.userInfo as? [String: Any] ?? [:]
        func str(_ k: String) -> String? { info[k] as? String }

        switch str("command") {
        case "quit": NSApp.terminate(nil); return
        case "show": present(); return
        case "pet":
            pet.purr(for: str("seconds").flatMap(Double.init) ?? 3)
            return
        case "petEnd":
            pet.handLifted()
            return
        case "clear":
            sessions.clear()
            summaryCheck = 0
            return
        case "theme":
            sheet.apply(theme: str("theme") ?? "grey")
            defaults.set(sheet.theme, forKey: "theme")
            pet.playOnce(Anims.sitTwitch)
            return
        case "hide":
            manual = nil
            return
        default: break
        }

        if let hook = str("hook") {
            sessions.handle(hook: hook, session: str("session") ?? "?", project: str("project") ?? "Claude",
                            kind: str("kind"), tool: str("tool"), pid: str("pid").flatMap(Int32.init) ?? 0)
            summaryCheck = 0 // look again on the next tick
            return
        }

        // Manual message from petsay.
        let text = (str("text") ?? "")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        let mood = str("mood").flatMap(Mood.parse)
        let seconds = str("seconds").flatMap(Double.init) ?? max(5, Double(text.count) * 0.12 + 3)
        if !text.isEmpty || mood != nil {
            manual = (text, mood ?? .done, Date().addingTimeInterval(seconds))
        }
    }

    /// Touching anywhere but the cat: a note from `petsay` can be tapped away.
    /// Notes about Claude stay until Claude moves on.
    func tapped(_ p: NSPoint) {
        manual = nil
    }

    /// Tells any other app showing a copy of the cat what it's doing now.
    func publish(_ shown: (Mood, String?)) {
        var info = ["mood": shown.0.rawValue, "theme": sheet.theme, "purring": pet.isPurring ? "1" : "0"]
        if let note = shown.1 { info["note"] = note }
        guard info != lastPublished else { return }
        lastPublished = info
        DistributedNotificationCenter.default().postNotificationName(
            kStateNote, object: nil, userInfo: info, deliverImmediately: true)
    }

    @objc func stateRequested() {
        lastPublished = [:] // the next tick sends the current state again
    }

    func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().postNotificationName(
            kStateNote, object: nil, userInfo: ["mood": "gone"], deliverImmediately: true)
    }

    func tick() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastTick, 0.2)
        lastTick = now

        // Claude's state only needs a fresh look once a second, or right after an event.
        summaryCheck -= dt
        if summaryCheck <= 0 {
            summaryCheck = 1
            claude = sessions.summary()
        }

        // Work out what to show: a manual note wins while it lasts, otherwise Claude's state.
        if let m = manual, Date() > m.until { manual = nil }
        let shown: (Mood, String?)
        if let m = manual {
            shown = (m.mood, m.text.isEmpty ? nil : m.text)
        } else {
            shown = (claude.mood, claude.note)
        }
        pet.set(mood: shown.0)
        barView.setNote(shown.1, mood: shown.0)
        if shown.0 != lastShown.0 || shown.1 != lastShown.1 || Date().timeIntervalSince(lastPresent) > 60 {
            present()
        }
        lastShown = shown

        let frameChanged = pet.tick(dt)
        let somethingMoved = barView.update(dt)
        if frameChanged || somethingMoved { barView.needsDisplay = true }
        publish(shown)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
