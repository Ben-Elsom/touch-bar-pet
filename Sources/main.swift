// Touch Bar Pet: a little pixel cat that lives in the Touch Bar's Control Strip
// and pops up full-width with a speech bubble when someone (Claude, a script,
// you) sends it a message with the `petsay` command.
//
// Sprite: "2D Pixel Art Cat Sprites" by Elthen (elthen.itch.io).

import AppKit

// MARK: - Identity & shared names (keep in sync with petsay.swift)

let kBundleID = "com.benelsom.touchbarpet"
let kSayNote = Notification.Name("com.benelsom.touchbarpet.say")
let kStripID = NSTouchBarItem.Identifier("com.benelsom.touchbarpet.strip")
let kStageID = NSTouchBarItem.Identifier("com.benelsom.touchbarpet.stage")

/// Points per sprite pixel. The Touch Bar is a 2x display, so 2pt = 4×4 real pixels.
let artScale: CGFloat = 2
let frameSize = 32
/// The cat's art sits in columns 7–24 of each 32px frame.
let artLeft: CGFloat = 7
let artWidth: CGFloat = 18

// MARK: - Private DFRFoundation functions (looked up at runtime)

private let dfrHandle = dlopen("/System/Library/PrivateFrameworks/DFRFoundation.framework/DFRFoundation", RTLD_NOW)

func dfrSetControlStripPresence(_ id: NSTouchBarItem.Identifier, _ present: Bool) {
    typealias Fn = @convention(c) (CFString, Bool) -> Void
    guard let h = dfrHandle, let sym = dlsym(h, "DFRElementSetControlStripPresenceForIdentifier") else {
        NSLog("TouchBarPet: DFRElementSetControlStripPresenceForIdentifier not found")
        return
    }
    unsafeBitCast(sym, to: Fn.self)(id.rawValue as CFString, present)
}

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
}

enum Mood: String, CaseIterable {
    case idle, think, work, done, needs, alert, sleep

    /// Speech bubble colour for this mood.
    var bubble: NSColor {
        switch self {
        case .done: return NSColor(srgbRed: 0.80, green: 0.96, blue: 0.84, alpha: 1)
        case .needs: return NSColor(srgbRed: 1.00, green: 0.91, blue: 0.66, alpha: 1)
        case .alert: return NSColor(srgbRed: 1.00, green: 0.80, blue: 0.80, alpha: 1)
        default: return NSColor(white: 0.96, alpha: 1)
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
        let map = Palette.themes[name] ?? [:]
        let w = source.width, h = source.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
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
        guard let img = ctx.makeImage() else { return }
        frames = (0..<(img.height / frameSize)).map { r in
            (0..<(img.width / frameSize)).compactMap { c in
                img.cropping(to: CGRect(x: c * frameSize, y: r * frameSize, width: frameSize, height: frameSize))
            }
        }
        theme = Palette.themes[name] == nil ? "grey" : name
    }

    func image(_ anim: Anim, _ frame: Int) -> CGImage? {
        guard anim.row < frames.count, frame < frames[anim.row].count else { return nil }
        return frames[anim.row][frame]
    }
}

// MARK: - The pet's little brain

final class Pet {
    private(set) var mood: Mood = .idle
    private(set) var anim = Anims.sit
    private(set) var frame = 0
    private var acc = 0.0
    private var loopsLeft = 3
    private var lastActivity = Date()

    func set(mood: Mood) {
        self.mood = mood
        lastActivity = Date()
        start(nextAnim())
    }

    func playOnce(_ a: Anim) {
        lastActivity = Date()
        if mood == .sleep { mood = .idle }
        start((a, 1))
    }

    private func start(_ next: (Anim, Int)) {
        anim = next.0
        loopsLeft = next.1
        frame = 0
        acc = 0
    }

    private func nextAnim() -> (Anim, Int) {
        switch mood {
        case .idle:
            let roll = Int.random(in: 0..<10)
            if roll < 6 { return (Anims.sit, 3) }
            if roll < 8 { return (Anims.sitTwitch, 2) }
            return (Bool.random() ? Anims.clean : Anims.clean2, 2)
        case .think: return (Bool.random() ? Anims.clean : Anims.clean2, 2)
        case .work: return (Anims.walk, 4)
        case .done: return (Anims.jump, 1)
        case .needs: return (Anims.paw, 3)
        case .alert: return (Anims.scared, 2)
        case .sleep: return (Anims.sleep, 10)
        }
    }

    /// Advances the animation. Returns true if the frame changed.
    func tick(_ dt: Double) -> Bool {
        var changed = false
        let idleFor = Date().timeIntervalSince(lastActivity)
        // Moods wear off: busy → idle after 3 min, alerts after 10, idle → asleep after 10.
        let next: Mood?
        switch mood {
        case .think, .work: next = idleFor > 180 ? .idle : nil
        case .needs, .alert: next = idleFor > 600 ? .idle : nil
        case .idle: next = idleFor > 600 ? .sleep : nil
        default: next = nil
        }
        if let next {
            mood = next
            start(nextAnim())
            changed = true
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
                if loopsLeft <= 0 {
                    if mood == .done { mood = .idle }
                    start(nextAnim())
                }
            }
        }
        return changed
    }
}

// MARK: - Drawing helpers

func drawCat(_ ctx: CGContext, sheet: SpriteSheet, anim: Anim, frame: Int, x: CGFloat, y: CGFloat = 0) {
    guard let img = sheet.image(anim, frame) else { return }
    ctx.saveGState()
    ctx.interpolationQuality = .none
    let size = CGFloat(frameSize) * artScale
    ctx.draw(img, in: CGRect(x: x - artLeft * artScale, y: y, width: size, height: size))
    ctx.restoreGState()
}

func drawZzz(at x: CGFloat, baseY: CGFloat, time: Double) {
    for i in 0..<3 {
        let phase = (time * 0.45 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
        let alpha = sin(phase * .pi) * 0.85
        let size = 6 + phase * 4
        let font = roundedFont(size: size, weight: .heavy)
        let s = NSAttributedString(string: "z", attributes: [
            .font: font, .foregroundColor: NSColor(white: 0.85, alpha: alpha),
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

// MARK: - Views

class TouchView: NSView {
    var onTap: ((NSPoint) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        allowedTouchTypes = [.direct]
    }

    required init?(coder: NSCoder) { fatalError() }

    override func touchesBegan(with event: NSEvent) {}

    override func touchesEnded(with event: NSEvent) {
        guard let t = event.touches(matching: .ended, in: self).first else { return }
        onTap?(t.location(in: self))
    }
}

/// The small always-there cat in the Control Strip.
final class StripView: TouchView {
    let pet: Pet
    let sheet: SpriteSheet
    var time = 0.0
    static let width: CGFloat = 46

    init(pet: Pet, sheet: SpriteSheet) {
        self.pet = pet
        self.sheet = sheet
        super.init(frame: NSRect(x: 0, y: 0, width: StripView.width, height: 30))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: StripView.width, height: 30) }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        drawCat(ctx, sheet: sheet, anim: pet.anim, frame: pet.frame, x: 3)
        if pet.anim == Anims.sleep { drawZzz(at: 30, baseY: 10, time: time) }
    }
}

/// The full-width view: cat + speech bubble.
final class StageView: TouchView {
    let pet: Pet
    let sheet: SpriteSheet
    var desiredWidth: CGFloat

    private(set) var message = ""
    private var chars: [Character] = []
    private var mood: Mood = .idle
    private var t = 0.0               // time since message arrived
    private var entering = false
    private var entranceT = 0.0
    private var arrivedFired = false
    private var hearts: [Heart] = []
    var onArrived: (() -> Void)?

    let catRestX: CGFloat = 10
    var bubbleX: CGFloat { catRestX + artWidth * artScale + 4 }
    let bubbleH: CGFloat = 24
    let pad: CGFloat = 11
    let font = roundedFont(size: 14, weight: .semibold)
    let typeSpeed = 40.0               // characters per second

    init(pet: Pet, sheet: SpriteSheet, width: CGFloat) {
        self.pet = pet
        self.sheet = sheet
        self.desiredWidth = width
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 30))
    }

    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { NSSize(width: desiredWidth, height: 30) }

    func show(_ text: String, mood: Mood, walkIn: Bool) {
        message = text
        chars = Array(text)
        self.mood = mood
        t = 0
        entering = walkIn
        entranceT = 0
        arrivedFired = false
        if !walkIn { fireArrived() }
    }

    private func fireArrived() {
        guard !arrivedFired else { return }
        arrivedFired = true
        onArrived?()
    }

    func addHeart() {
        hearts.append(Heart(x: catRestX + 24 + CGFloat.random(in: -4...4), y: 18, age: 0))
    }

    var entranceDuration: Double { 0.7 }

    /// Seconds the bubble should stay up for the current message.
    var suggestedDuration: Double {
        let n = Double(chars.count)
        var d = entranceDuration + n / typeSpeed + 3.5 + min(n * 0.03, 5)
        let over = overflow
        if over > 0 { d += 1.2 + Double(over) / 45 + 2 }
        return min(d, 30)
    }

    private var innerMaxWidth: CGFloat { max(40, bounds.width - bubbleX - 6 - pad * 2) }

    private func attributed(_ s: String) -> NSAttributedString {
        NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: NSColor(white: 0.08, alpha: 1)])
    }

    private var fullTextWidth: CGFloat { ceil(attributed(message).size().width) }
    private var overflow: CGFloat { max(0, fullTextWidth - innerMaxWidth) }

    func update(_ dt: Double) {
        if entering {
            entranceT += dt
            if entranceT >= entranceDuration { entering = false; fireArrived() }
        } else {
            t += dt
        }
        hearts = hearts.compactMap { var h = $0; h.age += dt; h.y += CGFloat(dt * 9); return h.age < 1.4 ? h : nil }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }

        // Cat
        if entering {
            let p = min(1, entranceT / entranceDuration)
            let x = -artWidth * artScale + (catRestX + artWidth * artScale) * CGFloat(p)
            drawCat(ctx, sheet: sheet, anim: Anims.walk, frame: Int(entranceT * 12) % Anims.walk.count, x: x)
            return
        }
        drawCat(ctx, sheet: sheet, anim: pet.anim, frame: pet.frame, x: catRestX)
        if pet.anim == Anims.sleep { drawZzz(at: catRestX + 28, baseY: 10, time: t) }
        for h in hearts { drawHeart(ctx, x: h.x, y: h.y, alpha: CGFloat(1 - h.age / 1.4)) }

        guard !message.isEmpty else { return }

        // Bubble pops open
        let pop = min(1, t / 0.18)
        let eased = 1 - pow(1 - pop, 3)
        let textW = fullTextWidth
        let fullBubbleW = min(textW, innerMaxWidth) + pad * 2
        let bw = max(bubbleH, fullBubbleW * CGFloat(eased))
        let by = (bounds.height - bubbleH) / 2
        let rect = NSRect(x: bubbleX, y: by, width: bw, height: bubbleH)

        mood.bubble.setFill()
        NSBezierPath(roundedRect: rect, xRadius: bubbleH / 2, yRadius: bubbleH / 2).fill()
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: bubbleX + 4, y: by + 9))
        tail.line(to: NSPoint(x: bubbleX - 7, y: by + 15))
        tail.line(to: NSPoint(x: bubbleX + 6, y: by + 17))
        tail.close()
        tail.fill()

        guard pop >= 1 else { return }

        // Typewriter text, scrolling like a ticker if it's too long
        let typeT = t - 0.18
        let typed = min(chars.count, max(0, Int(typeT * typeSpeed)))
        let visible = String(chars.prefix(typed))
        let inner = NSRect(x: bubbleX + pad, y: by, width: bw - pad * 2, height: bubbleH)
        var offset: CGFloat = 0
        let over = overflow
        if over > 0 {
            if typed < chars.count {
                offset = max(0, attributed(visible).size().width - inner.width)
            } else {
                let doneT = Double(chars.count) / typeSpeed
                let cycle = 2.0 + 1.2 + Double(over) / 45
                let ct = (typeT - doneT).truncatingRemainder(dividingBy: cycle)
                if ct < 2.0 { offset = over }
                else if ct < 3.2 { offset = 0 }
                else { offset = min(over, CGFloat(ct - 3.2) * 45) }
            }
        }
        ctx.saveGState()
        ctx.clip(to: inner)
        let s = attributed(visible)
        let h = s.size().height
        s.draw(at: NSPoint(x: inner.minX - offset, y: by + (bubbleH - h) / 2))
        ctx.restoreGState()
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    var sheet: SpriteSheet!
    let pet = Pet()
    var stripItem: NSCustomTouchBarItem!
    var stripView: StripView!
    let stageBar = NSTouchBar()
    var stageView: StageView!
    var stageShowing = false
    var hideAt: Date?
    var pendingMood: Mood = .idle
    var lastMessage: (String, Mood)?
    var timer: Timer?
    var lastTick = CACurrentMediaTime()
    var activity: NSObjectProtocol?
    let defaults = UserDefaults.standard

    /// 1 = full width (hides the Control Strip while a message is up).
    var placement: Int64 { Int64(defaults.object(forKey: "placement") as? Int ?? 1) }

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

        stripView = StripView(pet: pet, sheet: sheet)
        stripView.onTap = { [weak self] _ in self?.stripTapped() }
        stripItem = NSCustomTouchBarItem(identifier: kStripID)
        stripItem.view = stripView
        NSTouchBarItem.tbpAddSystemTrayItem(stripItem)
        dfrSetControlStripPresence(kStripID, true)

        let width = CGFloat(defaults.object(forKey: "stageWidth") as? Double ?? 1000)
        stageView = StageView(pet: pet, sheet: sheet, width: width)
        stageView.onTap = { [weak self] p in self?.stageTapped(p) }
        stageView.onArrived = { [weak self] in
            guard let self else { return }
            self.pet.set(mood: self.pendingMood)
        }
        let stageItem = NSCustomTouchBarItem(identifier: kStageID)
        stageItem.view = stageView
        stageBar.templateItems = [stageItem]
        stageBar.defaultItemIdentifiers = [kStageID]
        dfrShowCloseBox(false)

        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(received(_:)), name: kSayNote, object: nil,
            suspensionBehavior: .deliverImmediately)

        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep], reason: "Animating the Touch Bar pet")
        let t = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        if !defaults.bool(forKey: "greeted") {
            defaults.set(true, forKey: "greeted")
            say("Hi! I'm your Touch Bar cat. Tap me any time 🐾", mood: .done, seconds: nil)
        }
        NSLog("TouchBarPet: ready")
    }

    @objc func received(_ note: Notification) {
        let info = note.userInfo as? [String: Any] ?? [:]
        func str(_ k: String) -> String? { info[k] as? String }

        switch str("command") {
        case "quit":
            NSApp.terminate(nil)
            return
        case "theme":
            let name = str("theme") ?? "grey"
            sheet.apply(theme: name)
            defaults.set(sheet.theme, forKey: "theme")
            pet.playOnce(Anims.sitTwitch)
            stripView.needsDisplay = true
            return
        case "hide":
            hideStage()
            return
        default: break
        }

        let mood = str("mood").flatMap(Mood.init(rawValue:))
        let text = (str("text") ?? "")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        let quiet = str("quiet") == "1"
        let seconds = str("seconds").flatMap(Double.init)

        if text.isEmpty || quiet {
            if let mood { pet.set(mood: mood) }
            stripView.needsDisplay = true
            return
        }
        say(text, mood: mood ?? .idle, seconds: seconds)
    }

    func say(_ text: String, mood: Mood, seconds: Double?) {
        lastMessage = (text, mood)
        pendingMood = mood
        let walkIn = !stageShowing
        stageView.show(text, mood: mood, walkIn: walkIn)
        if !stageShowing { showStage() }
        hideAt = Date().addingTimeInterval(seconds ?? stageView.suggestedDuration)
    }

    func showStage() {
        NSTouchBar.tbpPresentSystemModal(stageBar, placement: placement, systemTrayItemIdentifier: kStripID)
        stageShowing = true
        dfrSetControlStripPresence(kStripID, true)
    }

    func hideStage() {
        guard stageShowing else { return }
        NSTouchBar.tbpMinimizeSystemModal(stageBar)
        stageShowing = false
        hideAt = nil
        dfrSetControlStripPresence(kStripID, true)
    }

    func stripTapped() {
        if stageShowing { hideStage(); return }
        if pet.mood == .sleep { pet.set(mood: .idle) }
        if let (text, mood) = lastMessage {
            say(text, mood: mood == .done ? .idle : mood, seconds: nil)
        } else {
            let lines = ["Meow!", "Purr… no news yet.", "*stretches*", "Just vibing 🐾", "Feed me? 🐟"]
            say(lines.randomElement()!, mood: .idle, seconds: 3.5)
        }
        stageView.addHeart()
    }

    func stageTapped(_ p: NSPoint) {
        if p.x < stageView.bubbleX {
            stageView.addHeart()
            pet.playOnce(Anims.sitTwitch)
            if let h = hideAt { hideAt = max(h, Date().addingTimeInterval(2.5)) }
        } else {
            hideStage()
        }
    }

    func tick() {
        let now = CACurrentMediaTime()
        let dt = min(now - lastTick, 0.1)
        lastTick = now
        let changed = pet.tick(dt)
        stripView.time += dt
        if changed || pet.anim == Anims.sleep { stripView.needsDisplay = true }
        if stageShowing {
            stageView.update(dt)
            stageView.needsDisplay = true
            if let h = hideAt, Date() >= h { hideStage() }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
