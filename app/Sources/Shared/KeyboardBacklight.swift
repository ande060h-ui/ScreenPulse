// MacBook keyboard backlight control.
//
// Uses the private CoreBrightness framework (BrightnessSystemClient). There is no
// public macOS API for the keyboard backlight, so every call is guarded: on Macs
// where the class or selectors are missing, the calls are silently ignored.

import Foundation

final class KeyboardBacklight: @unchecked Sendable {
    static let shared = KeyboardBacklight()

    private var client: AnyObject?
    private var originalBrightness: Float = 0.5
    private var hasOriginal = false
    private(set) var isSupported = false

    private static let brightnessKey = "KeyboardBacklightBrightness" as NSString

    init() {
        dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY)
        guard let cls = NSClassFromString("BrightnessSystemClient") as? NSObject.Type else { return }
        client = cls.init()
        isSupported = true
        snapshot()
    }

    /// Diagnostics for `capsled probe`.
    var respondsToRead: Bool { (client as? NSObject)?.responds(to: Selector(("copyPropertyForKey:"))) ?? false }
    var respondsToWrite: Bool { (client as? NSObject)?.responds(to: Selector(("setProperty:forKey:"))) ?? false }

    func getBrightness() -> Float? {
        guard let client = client as? NSObject else { return nil }
        let sel = Selector(("copyPropertyForKey:"))
        guard client.responds(to: sel),
              let value = client.perform(sel, with: Self.brightnessKey)?.takeRetainedValue() as? NSNumber else { return nil }
        return value.floatValue
    }

    func setBrightness(_ value: Float) {
        guard let client = client as? NSObject else { return }
        let sel = Selector(("setProperty:forKey:"))
        guard client.responds(to: sel) else { return }
        _ = client.perform(sel, with: NSNumber(value: max(0.0, min(1.0, value))), with: Self.brightnessKey)
    }

    func setOn(_ on: Bool) { setBrightness(on ? 1.0 : 0.0) }

    /// Remembers the current brightness so it can be restored after a signal
    /// (the user may have changed it since launch).
    func snapshot() {
        if let current = getBrightness() {
            originalBrightness = current
            hasOriginal = true
        }
    }

    /// Puts the backlight back to the brightness captured by the last `snapshot()`.
    func restore() {
        if hasOriginal { setBrightness(originalBrightness) }
    }
}
