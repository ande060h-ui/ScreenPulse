// capsled probe — reports what the keyboard lights on this Mac support.
//
// The output is meant to be copied into a compatibility report. Nothing is sent anywhere.
// The probe switches the lights on and off briefly and then restores them.

import Foundation
import IOKit.hid
import CoreGraphics

private func sysctlString(_ name: String) -> String {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
    var buf = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return "unknown" }
    return String(cString: buf)
}

private func hex(_ r: IOReturn) -> String { r == kIOReturnSuccess ? "ok" : String(format: "failed (0x%08x)", UInt32(bitPattern: r)) }

private func pause(_ s: Double) { usleep(useconds_t(s * 1_000_000)) }

func runProbe() {
    print("ScreenPulse keyboard light probe")
    print("--------------------------------")
    print("Mac model:        \(sysctlString("hw.model"))")
    print("CPU:              \(sysctlString("machdep.cpu.brand_string"))")
    print("macOS:            \(ProcessInfo.processInfo.operatingSystemVersionString)")

    let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
    let accessText = access == kIOHIDAccessTypeGranted ? "granted" : access == kIOHIDAccessTypeDenied ? "denied" : "not decided yet"
    print("Input Monitoring: \(accessText) (for the program that runs this probe, e.g. Terminal)")
    if access != kIOHIDAccessTypeGranted { _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }

    // --- Caps Lock LED ---
    print("\nCaps Lock light")
    let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    IOHIDManagerSetDeviceMatching(mgr, [
        kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
        kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard,
    ] as CFDictionary)
    print("  Open HID manager: \(hex(IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone))))")

    let capsWasOn = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
    var leds: [(IOHIDDevice, IOHIDElement)] = []
    let devices = (IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>) ?? []
    if devices.isEmpty { print("  No keyboards visible. Input Monitoring is probably missing.") }
    for dev in devices {
        func prop(_ key: String) -> String {
            guard let v = IOHIDDeviceGetProperty(dev, key as CFString) else { return "?" }
            return "\(v)"
        }
        let match = [kIOHIDElementUsagePageKey: kHIDPage_LEDs, kIOHIDElementUsageKey: kHIDUsage_LED_CapsLock] as CFDictionary
        let els = (IOHIDDeviceCopyMatchingElements(dev, match, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement]) ?? []
        print("  Keyboard: \(prop(kIOHIDProductKey)) · transport \(prop(kIOHIDTransportKey)) · built-in \(prop(kIOHIDBuiltInKey)) · Caps Lock LED elements: \(els.count)")
        for el in els {
            let on = IOHIDDeviceSetValue(dev, el, IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, el, mach_absolute_time(), 1))
            pause(0.3)
            let off = IOHIDDeviceSetValue(dev, el, IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, el, mach_absolute_time(), 0))
            print("    set on: \(hex(on)) · set off: \(hex(off))")
            leds.append((dev, el))
        }
    }
    func setCaps(_ on: Bool) {
        for (dev, el) in leds {
            IOHIDDeviceSetValue(dev, el, IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, el, mach_absolute_time(), on ? 1 : 0))
        }
    }

    // --- Keyboard backlight ---
    print("\nKeyboard backlight (private CoreBrightness framework)")
    let bl = KeyboardBacklight.shared
    print("  BrightnessSystemClient class: \(bl.isSupported ? "found" : "not found")")
    print("  Responds to read / write:     \(bl.respondsToRead) / \(bl.respondsToWrite)")
    let original = bl.getBrightness()
    print("  Current brightness:           \(original.map { String(format: "%.2f", $0) } ?? "could not be read")")
    var backlightWritable = false
    if bl.isSupported, bl.respondsToWrite {
        bl.setBrightness(1.0); pause(0.6)
        let high = bl.getBrightness()
        bl.setBrightness(0.0); pause(0.6)
        let low = bl.getBrightness()
        func f(_ v: Float?) -> String { v.map { String(format: "%.2f", $0) } ?? "?" }
        print("  Read-back after set 1.0 / 0.0: \(f(high)) / \(f(low))")
        if let h = high, let l = low { backlightWritable = h - l > 0.3 }
        print("  Brightness follows writes:    \(backlightWritable ? "yes" : "no (or it cannot be read back)")")
        bl.restore()
    }

    // --- What you see ---
    print("\nVisual check — please watch the keyboard and note what you see:")
    if !leds.isEmpty {
        print("  1) Caps Lock light: 5 blinks, 0.2 s each …")
        pause(1.0)
        for _ in 0..<5 { setCaps(true); pause(0.2); setCaps(false); pause(0.2) }
        setCaps(capsWasOn)
    } else {
        print("  1) Caps Lock light: skipped (no controllable LED found)")
    }
    if bl.isSupported, bl.respondsToWrite {
        for (i, t) in [(2, 0.5), (3, 0.2)] {
            print("  \(i)) Keyboard backlight: 5 blinks, \(t) s each …")
            pause(1.0)
            for _ in 0..<5 { bl.setOn(true); pause(t); bl.setOn(false); pause(t) }
            bl.restore()
        }
    } else {
        print("  2) Keyboard backlight: skipped (not controllable)")
    }

    print("""

    Please report, together with everything above:
      - Did the Caps Lock light blink 5 clearly separate times?
      - Did the backlight blink 5 separate times at 0.5 s? At 0.2 s? Or did the blinks blur together?
      - Did the Caps Lock state and the backlight brightness return to what they were?
    """)
}
