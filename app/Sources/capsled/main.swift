// capsled — optical signalling through the Caps Lock LED and the MacBook keyboard backlight.
//
// Usage:
//   capsled on | off            turn the light on / off
//   capsled think [seconds]     "thinking" fade (software PWM) for N seconds (default 5)
//   <command> | capsled         fade while waiting for input, then blink each letter
//   capsled "text"              blink the text directly
//   capsled signal <value>      play a ScreenPulse signal: yes | no | ready | error | a number | letters
//   capsled probe               report what this Mac's keyboard lights support
//
// Code: a = 1 blink, b = 2 … z = 26 (æ = 27, ø = 28, å = 29). A space is a long pause.
// Other characters are ignored.

import Foundation
import IOKit.hid
import CoreGraphics

// The probe does its own device handling and must also run when nothing is found.
if CommandLine.arguments.dropFirst().first == "probe" {
    runProbe()
    exit(0)
}

// MARK: - LED access

let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
IOHIDManagerSetDeviceMatching(manager, [
    kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
    kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard,
] as CFDictionary)
let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
if openResult != kIOReturnSuccess && !KeyboardBacklight.shared.isSupported {
    FileHandle.standardError.write("Could not open the keyboard HID device (\(openResult)). Allow your terminal under System Settings › Privacy & Security › Input Monitoring.\n".data(using: .utf8)!)
    exit(1)
}

var leds: [(IOHIDDevice, IOHIDElement)] = []
if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
    for dev in devices {
        let match = [kIOHIDElementUsagePageKey: kHIDPage_LEDs,
                     kIOHIDElementUsageKey: kHIDUsage_LED_CapsLock] as CFDictionary
        if let els = IOHIDDeviceCopyMatchingElements(dev, match, IOOptionBits(kIOHIDOptionsTypeNone)) as? [IOHIDElement] {
            for el in els { leds.append((dev, el)) }
        }
    }
}
if leds.isEmpty && !KeyboardBacklight.shared.isSupported {
    FileHandle.standardError.write("Found neither a Caps Lock LED nor a keyboard backlight.\n".data(using: .utf8)!)
    exit(1)
}

/// Caps Lock LED only (used while "thinking").
func setCaps(_ on: Bool) {
    for (dev, el) in leds {
        let v = IOHIDValueCreateWithIntegerValue(kCFAllocatorDefault, el, mach_absolute_time(), on ? 1 : 0)
        IOHIDDeviceSetValue(dev, el, v)
    }
}

/// Caps Lock LED + keyboard backlight (used when the answer is blinked).
func setLED(_ on: Bool) {
    setCaps(on)
    KeyboardBacklight.shared.setOn(on)
}

// Remember the real Caps Lock state and backlight level, and restore them on exit.
let capsWasOn = CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift)
func restore() {
    setCaps(capsWasOn)
    KeyboardBacklight.shared.restore()
}
signal(SIGINT) { _ in
    setCaps(capsWasOn)
    KeyboardBacklight.shared.restore()
    exit(0)
}
signal(SIGTERM) { _ in
    setCaps(capsWasOn)
    KeyboardBacklight.shared.restore()
    exit(0)
}

// MARK: - Patterns

let dot = 0.18   // on-time per blink
let gap = 0.18   // pause between blinks
let letterGap = 0.9
let wordGap = 1.8

func sleep(_ s: Double) { usleep(useconds_t(s * 1_000_000)) }

/// Software PWM: the LED is on/off only, so a "fade" is fast toggling with a varying duty cycle.
func fadeCycle(period: Double = 1.6, shouldStop: () -> Bool) {
    let frame = 0.012           // ~83 Hz PWM frequency
    let frames = Int(period / frame)
    for i in 0..<frames {
        if shouldStop() { return }
        let phase = Double(i) / Double(frames)
        let duty = (1 - cos(phase * 2 * .pi)) / 2   // 0 → 1 → 0
        let on = frame * duty
        if on > 0.0005 { setCaps(true); sleep(on) }
        setCaps(false); sleep(frame - on)
    }
}

/// Plays a pattern from Core/Signal.swift on both lights.
func play(_ signal: Signal, unit: Double = dot) {
    for step in SignalPattern.steps(for: signal, unit: unit) {
        setLED(step.on)
        sleep(step.seconds)
    }
}

func blinkText<S: Sequence>(_ s: S) where S.Element == Character {
    for c in s {
        if c == " " || c == "\n" { sleep(wordGap); continue }
        print(c, terminator: ""); fflush(stdout)
        let n = SignalPattern.blinkCount(c)
        for _ in 0..<n { setLED(true); sleep(dot); setLED(false); sleep(gap) }
        if n > 0 { sleep(letterGap) }
    }
}

// MARK: - CLI

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "on":  setLED(true)
case "off": setLED(false)
case "-h", "--help":
    print("""
    capsled — optical signalling through the Caps Lock LED and keyboard backlight.

      capsled on | off          turn the light on / off
      capsled think [seconds]   "thinking" fade for N seconds (default 5)
      capsled "text"            blink the text (a = 1 blink, b = 2 …)
      capsled signal <value>    yes | no | ready | error | a number | letters
      capsled probe             report what this Mac's keyboard lights support
      <command> | capsled       fade while waiting for input, then blink it
    """)
case "think":
    let end = Date().addingTimeInterval(Double(args.dropFirst().first ?? "5") ?? 5)
    while Date() < end { fadeCycle { Date() >= end } }
    restore()
case "signal":
    let value = args.dropFirst().joined(separator: " ")
    let signal: Signal
    switch value.lowercased() {
    case "ready": signal = .ready
    case "error": signal = .error
    default: signal = AnswerParser.signalValue(value)
    }
    print("Signal: \(signal.label)")
    play(signal, unit: signal == .ready || signal == .error ? dot : 0.5)
    restore()
case .some:
    blinkText(args.joined(separator: " ")); print()
    restore()
case .none:
    // Read stdin in the background; fade until the first character arrives.
    let lock = NSLock()
    var buffer: [Character] = []
    var done = false
    Thread.detachNewThread {
        while let line = readLine(strippingNewline: false) {
            lock.lock(); buffer.append(contentsOf: line); lock.unlock()
        }
        lock.lock(); done = true; lock.unlock()
    }
    func hasData() -> Bool { lock.lock(); defer { lock.unlock() }; return !buffer.isEmpty || done }
    while !hasData() { fadeCycle(shouldStop: hasData) }
    while true {
        lock.lock()
        if buffer.isEmpty && done { lock.unlock(); break }
        let c = buffer.isEmpty ? nil : buffer.removeFirst()
        lock.unlock()
        if let c { blinkText([c]) } else { fadeCycle(period: 0.8, shouldStop: hasData) }
    }
    print()
    restore()
}
