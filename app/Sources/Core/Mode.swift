// The two interaction modes and their output settings.
//
// Mode decides WHAT the AI answers (prompt + answer handling).
// Outputs decide HOW the answer reaches the user (window, Caps Lock light, backlight).
// The two are independent: each mode has its own set of outputs.

import Foundation

enum AppMode: String, CaseIterable {
    /// General screen assistant: explanatory answers.
    case normal
    /// Minimal multiple-choice mode: only the chosen letter.
    case focus

    var title: String { self == .normal ? "Normal Mode" : "Focus Mode" }
}

struct OutputOptions: Equatable {
    /// Show the floating answer window.
    var window: Bool
    /// Signal on the Caps Lock light.
    var capsLock: Bool
    /// Signal on the keyboard backlight.
    var backlight: Bool

    var anyLight: Bool { capsLock || backlight }

    static func defaults(for mode: AppMode) -> OutputOptions {
        switch mode {
        case .normal: return OutputOptions(window: true, capsLock: false, backlight: false)
        case .focus: return OutputOptions(window: false, capsLock: true, backlight: true)
        }
    }
}

/// Reads and writes mode settings in UserDefaults. The store is injectable for tests.
struct ModeSettings {
    let defaults: UserDefaults
    init(_ defaults: UserDefaults = .standard) { self.defaults = defaults }

    static let modeKey = "Mode"

    private func key(_ mode: AppMode, _ output: String) -> String { "Output.\(mode.rawValue).\(output)" }

    var mode: AppMode {
        get { defaults.string(forKey: Self.modeKey).flatMap(AppMode.init(rawValue:)) ?? .normal }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.modeKey) }
    }

    func outputs(for mode: AppMode) -> OutputOptions {
        let d = OutputOptions.defaults(for: mode)
        func value(_ name: String, _ fallback: Bool) -> Bool {
            defaults.object(forKey: key(mode, name)) as? Bool ?? fallback
        }
        return OutputOptions(window: value("window", d.window), capsLock: value("capsLock", d.capsLock),
                             backlight: value("backlight", d.backlight))
    }

    func setOutputs(_ o: OutputOptions, for mode: AppMode) {
        defaults.set(o.window, forKey: key(mode, "window"))
        defaults.set(o.capsLock, forKey: key(mode, "capsLock"))
        defaults.set(o.backlight, forKey: key(mode, "backlight"))
    }
}
