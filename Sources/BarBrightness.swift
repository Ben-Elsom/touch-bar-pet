// Keeps the Touch Bar visible while you're away. Left alone it dims after a minute
// and goes dark about 15 seconds later, even with Amphetamine holding the screen on.
// While something is holding the display awake, this puts it back whenever it dims
// past the level we want, so a glance still shows whether Claude needs you.
//
// Measured dimming steps on a MacBookPro16,3: 1 is normal, 2 is dimmed, 4 is dark.
//
// Uses Apple's private DFRBrightnessClient, looked up at runtime. If a macOS update
// removes it, this quietly does nothing and the bar dims as usual.
//
// Settings:
//   defaults write com.benelsom.touchbarpet keepBarLit -bool false     turn this off
//   defaults write com.benelsom.touchbarpet barAwayStep -int 1         stay at normal
//     brightness. The default is 2: the bar is OLED, and hours at full brightness
//     with a note in one place risks burn-in.

import AppKit
import IOKit.pwr_mgt

final class BarBrightness {
    private let client: NSObject?
    private let getStep = NSSelectorFromString("getDimmingStep")
    private let setStep = NSSelectorFromString("dimToStep:")

    init() {
        dlopen("/System/Library/PrivateFrameworks/DFRBrightness.framework/DFRBrightness", RTLD_NOW)
        let made = (NSClassFromString("DFRBrightnessClient") as? NSObject.Type)?.init()
        client = made?.responds(to: getStep) == true && made?.responds(to: setStep) == true ? made : nil
    }

    /// Call about once a second. Only ever brightens, and only down to the chosen level.
    func keepLit(defaults: UserDefaults = .standard) {
        guard let client,
              defaults.object(forKey: "keepBarLit") as? Bool ?? true,
              Self.displayIsHeldAwake,
              CGDisplayIsAsleep(CGMainDisplayID()) == 0 else { return }
        let saved = defaults.integer(forKey: "barAwayStep")
        let target = saved == 1 ? 1 : 2

        typealias Get = @convention(c) (AnyObject, Selector) -> Int
        typealias Set = @convention(c) (AnyObject, Selector, Int) -> Bool
        let current = unsafeBitCast(client.method(for: getStep), to: Get.self)(client, getStep)
        if current > target {
            _ = unsafeBitCast(client.method(for: setStep), to: Set.self)(client, setStep, target)
        }
    }

    /// True while Amphetamine or anything else is stopping the display from sleeping.
    private static var displayIsHeldAwake: Bool {
        var status: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsStatus(&status) == kIOReturnSuccess,
              let all = status?.takeRetainedValue() as? [String: Any] else { return false }
        return (all["PreventUserIdleDisplaySleep"] as? Int ?? 0) > 0
    }
}
