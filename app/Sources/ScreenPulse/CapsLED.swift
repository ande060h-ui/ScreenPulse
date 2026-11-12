// Optical signalling: Caps Lock LED (IOKit HID) + keyboard backlight (CoreBrightness).
//
// Plays the patterns defined in Core/Signal.swift on the lights the user enabled.
// "Thinking" is a fast flicker in the Caps Lock LED only.
// The Caps Lock state and backlight level are snapshotted before every signal
// and restored afterwards.

import Foundation
import IOKit.hid
import CoreGraphics

final class CapsLED: @unchecked Sendable {
    static let shared = CapsLED()

    private var manager: IOHIDManager?
    private var leds: [(IOHIDDevice, IOHIDElement)] = []
    private var isInitialized = false
    private let queue = DispatchQueue(label: "com.screenpulse.capsled", qos: .userInteractive)
    private let stateLock = NSLock()
    private var thinking = false
    private var initialCapsLockState = false

    /// True when at least one Caps Lock LED element was found on a connected keyboard.
    var hasCapsLockLED: Bool { !leds.isEmpty }

    /// Blink time in seconds (Settings → Blink speed). Default is calm.
    var unit: Double {
        let v = UserDefaults.standard.double(forKey: DefaultsKey.blinkSeconds)
        return v > 0 ? v : 0.5
    }
    var dot: Double { unit }              // on-time per blink
    var gap: Double { unit }              // pause between blinks within a letter
    var letterGap: Double { unit * 3.5 }  // pause between letters
    var wordGap: Double { unit * 6 }      // pause between words

    init() { setup() }

    func setup() {
        guard !isInitialized else { return }
        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted {
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(mgr, [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard,
        ] as CFDictionary)
        let openResult = IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))
        guard openResult == kIOReturnSuccess || KeyboardBacklight.shared.isSupported else {
            NSLog("ScreenPulse: could not open the keyboard HID device (%d). Input Monitoring is required.", openResult)
            return
        }
        manager = mgr

        if let devices = IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice> {
            for dev in devices {
                let match = [kIOHIDElementUsagePageKey: kHIDPage_LEDs,
                             kIOHIDElementUsageKey: kHIDUsage_LED_CapsLock] as CFDictionary
                if let els = IOHIDDeviceCopyMatchingElements(dev, match, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement] {
                    for el in els { leds.append((dev, el)) }
                }
            }
        }
        initialCapsLockState = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
        isInitialized = !leds.isEmpty || KeyboardBacklight.shared.isSupported
    }

    private var isThinking: Bool {
        get { stateLock.lock(); defer { stateLock.unlock() }; return thinking }
        set { stateLock.lock(); thinking = newValue; stateLock.unlock() }
    }

    /// Caps Lock LED only (used while "thinking").
    func setCaps(_ on: Bool) {
        for (dev, el) in leds {
            let v = IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, el, mach_absolute_time(), on ? 1 : 0)
            IOHIDDeviceSetValue(dev, el, v)
        }
    }

    /// Caps Lock LED + keyboard backlight together (used when the answer is blinked).
    func setLED(_ on: Bool) {
        setCaps(on)
        KeyboardBacklight.shared.setOn(on)
    }

    /// Remember the Caps Lock state and backlight brightness as they are right before a signal.
    func snapshotState() {
        initialCapsLockState = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
        KeyboardBacklight.shared.snapshot()
    }

    /// Restore the Caps Lock LED and the keyboard backlight to the user's own settings.
    func restore() {
        setCaps(initialCapsLockState)
        KeyboardBacklight.shared.restore()
    }

    private func sleepSeconds(_ s: Double) {
        usleep(useconds_t(s * 1_000_000))
    }

    /// Turns the selected lights on or off.
    private func set(_ on: Bool, _ outputs: OutputOptions) {
        if outputs.capsLock { setCaps(on) }
        if outputs.backlight { KeyboardBacklight.shared.setOn(on) }
    }

    /// Starts the "thinking" signal in the background while waiting for the model.
    /// It only uses the Caps Lock light; the backlight is left alone.
    func startThinking(outputs: OutputOptions = .allLights) {
        guard outputs.capsLock else { return }
        isThinking = true
        queue.async { [weak self] in
            guard let self else { return }
            self.snapshotState()
            // Fast flicker (~12 blinks per second).
            while self.isThinking {
                self.setCaps(true);  self.sleepSeconds(0.04)
                self.setCaps(false); self.sleepSeconds(0.04)
            }
            self.setCaps(self.initialCapsLockState)
        }
    }

    func stopThinking() { isThinking = false }

    /// Plays a signal on the selected lights, then restores the user's own light settings.
    func play(_ signal: Signal, outputs: OutputOptions = .allLights) {
        stopThinking()
        guard outputs.anyLight else { return }
        let steps = SignalPattern.steps(for: signal, unit: unit)
        queue.async { [weak self] in
            guard let self else { return }
            self.snapshotState()
            self.set(false, outputs)
            // Dark lead-in, so the signal is clearly separate from "thinking".
            self.sleepSeconds(signal == .error ? 0.1 : 1.5)
            for step in steps {
                self.set(step.on, outputs)
                self.sleepSeconds(step.seconds)
            }
            self.restore()
        }
    }

    /// Blinks letters (used by the test buttons).
    func blinkText(_ s: String) { play(.letters(s)) }

    /// Three quick micro-blinks.
    func blinkError(outputs: OutputOptions = .allLights) { play(.error, outputs: outputs) }
}

extension OutputOptions {
    /// Both lights, for tests and the error signal.
    static let allLights = OutputOptions(window: false, capsLock: true, backlight: true)
}
