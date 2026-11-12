// Settings window (SwiftUI). Opened from the menu bar icon.

import SwiftUI
import AppKit
import IOKit.hid
import CoreGraphics

final class SettingsModel: ObservableObject {
    @Published var blink: Double = { let v = UserDefaults.standard.double(forKey: DefaultsKey.blinkSeconds); return v > 0 ? v : 0.5 }() {
        didSet { UserDefaults.standard.set(blink, forKey: DefaultsKey.blinkSeconds) }
    }
    private let modes = ModeSettings()
    @Published var mode: AppMode = ModeSettings().mode {
        didSet {
            guard mode != oldValue else { return }
            modes.mode = mode
            outputs = modes.outputs(for: mode)
        }
    }
    /// Outputs of the mode currently shown.
    @Published var outputs: OutputOptions = ModeSettings().outputs(for: ModeSettings().mode) {
        didSet { if outputs != oldValue { modes.setOutputs(outputs, for: mode) } }
    }
    @Published var model: String = UserDefaults.standard.string(forKey: DefaultsKey.model) ?? "" {
        didSet { UserDefaults.standard.set(model, forKey: DefaultsKey.model) }
    }
    @Published var modifierOnly: Bool = UserDefaults.standard.bool(forKey: DefaultsKey.modifierOnlyHotkey) {
        didSet { UserDefaults.standard.set(modifierOnly, forKey: DefaultsKey.modifierOnlyHotkey) }
    }
    @Published var updateChecks: Bool = UserDefaults.standard.bool(forKey: DefaultsKey.updateChecks) {
        didSet { UserDefaults.standard.set(updateChecks, forKey: DefaultsKey.updateChecks) }
    }
    @Published var launchAtLogin = LoginItem.isEnabled
    @Published var loginError: String?
    @Published var apiKey: String = KeyStore.loadStored() ?? ""
    @Published var showKey = false
    @Published var saved = false
    @Published var saveFailed = false
    @Published var checking = false
    @Published var keyResult: KeyCheckResult?
    @Published var screenOK = CGPreflightScreenCaptureAccess()
    @Published var inputOK = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted

    let hasCapsLED = CapsLED.shared.hasCapsLockLED
    let hasBacklight = KeyboardBacklight.shared.isSupported && KeyboardBacklight.shared.getBrightness() != nil
}

struct SettingsView: View {
    @StateObject private var m = SettingsModel()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                modeCard
                signalCard
                aiCard
                card("Permissions", icon: "lock.shield") {
                    VStack(alignment: .leading, spacing: 10) {
                        permRow("Screen Recording", ok: m.screenOK, hint: "Required to capture the screen.",
                                pane: "Privacy_ScreenCapture") { _ = CGRequestScreenCaptureAccess() }
                        permRow("Input Monitoring", ok: m.inputOK, hint: "Required to control the Caps Lock light.",
                                pane: "Privacy_ListenEvent") { _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }
                        Text("After granting a permission, quit ScreenPulse from the menu bar icon and open it again.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                generalCard
                card("How to Use", icon: "keyboard") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("1. Point at a question or a piece of text.")
                        Text("2. Press **Control + Option + Command + Space**.")
                        Text("3. The answer arrives on the outputs you chose above: in the window, on the keyboard lights, or both.")
                        Text("Press **Control + Option + Command + 0** to show or hide the answer window.")
                            .font(.footnote).foregroundStyle(.secondary).padding(.top, 2)
                    }
                }
            }
            .padding(24)
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 560)
        .onReceive(timer) { _ in
            m.screenOK = CGPreflightScreenCaptureAccess()
            m.inputOK = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        }
    }

    // MARK: Cards

    private var modeCard: some View {
        card("Mode", icon: "square.split.2x1") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("", selection: $m.mode) {
                    ForEach(AppMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                Text(m.mode == .normal
                     ? "A general screen assistant. Point at anything — a question, text, an error message, a chart — and get an explanatory answer."
                     : "Minimal and fast. For multiple-choice questions ScreenPulse returns only the letter. Anything else gets one short sentence and is never turned into a letter.")
                    .font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Divider()
                Text("Outputs in \(m.mode.title)").font(.subheadline.weight(.semibold))
                Toggle("Answer window", isOn: $m.outputs.window).toggleStyle(.switch)
                Toggle("Caps Lock light", isOn: $m.outputs.capsLock).toggleStyle(.switch)
                Toggle("Keyboard backlight", isOn: $m.outputs.backlight).toggleStyle(.switch)
                Text(outputHint).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .onChange(of: m.mode) { _ in (NSApp.delegate as? AppDelegate)?.modeSettingsChanged() }
            .onChange(of: m.outputs) { _ in (NSApp.delegate as? AppDelegate)?.modeSettingsChanged() }
        }
    }

    private var outputHint: String {
        if !m.outputs.window && !m.outputs.anyLight {
            return "All outputs are off. Press ⌃⌥⌘ 0 after asking to read the answer; errors still open the window."
        }
        if !m.outputs.window { return "The window stays hidden. Press ⌃⌥⌘ 0 to read the last answer as text." }
        if m.mode == .normal && m.outputs.anyLight {
            return "The lights signal a short form of the answer when there is one (a letter, a number, yes or no), otherwise “answer ready”."
        }
        return "Each mode remembers its own outputs."
    }

    private var signalCard: some View {
        card("Keyboard Signal", icon: "capslock.fill") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Blink speed")
                    Spacer()
                    Text(speedLabel).foregroundStyle(.secondary)
                }
                HStack {
                    Image(systemName: "hare.fill").foregroundStyle(.secondary)
                    Slider(value: $m.blink, in: 0.2...1.2, step: 0.05)
                    Image(systemName: "tortoise.fill").foregroundStyle(.secondary)
                }
                .environment(\.layoutDirection, .rightToLeft)
                Text("Drag left for calmer blinks and right for faster ones. Letters and digits are counted out (A = 1 blink, B = 2, 3 = three blinks). Yes is one long light, no is two. Two short blinks mean an answer is ready in the window; three quick ones mean an error.")
                    .font(.footnote).foregroundStyle(.secondary)
                HStack {
                    Button("Test A") { CapsLED.shared.blinkText("A") }
                    Button("Test B") { CapsLED.shared.blinkText("B") }
                    Button("Yes") { CapsLED.shared.play(.yes) }
                    Button("No") { CapsLED.shared.play(.no) }
                    Button("Ready") { CapsLED.shared.play(.ready) }
                    Button("Thinking") {
                        CapsLED.shared.startThinking()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            CapsLED.shared.stopThinking(); CapsLED.shared.restore()
                        }
                    }
                    Spacer()
                    Button("Restore lights") { CapsLED.shared.stopThinking(); CapsLED.shared.restore() }
                }
                Divider()
                hardwareRow("Caps Lock light", ok: m.hasCapsLED,
                            missing: "Not found. Grant Input Monitoring and restart, or connect a keyboard with a Caps Lock light.")
                hardwareRow("Keyboard backlight", ok: m.hasBacklight,
                            missing: "Not available on this Mac or keyboard.")
            }
        }
    }

    private var aiCard: some View {
        card("Gemini (AI)", icon: "sparkles") {
            VStack(alignment: .leading, spacing: 10) {
                Text("API key")
                HStack {
                    Group {
                        if m.showKey { TextField("Paste your key", text: $m.apiKey) }
                        else { SecureField("Paste your key", text: $m.apiKey) }
                    }.textFieldStyle(.roundedBorder)
                    Button(m.showKey ? "Hide" : "Show") { m.showKey.toggle() }
                    Button(m.saved ? "Saved ✓" : "Save") {
                        let ok = KeyStore.save(m.apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
                        m.saved = ok
                        m.saveFailed = !ok
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { m.saved = false }
                    }.buttonStyle(.borderedProminent)
                    Button(m.checking ? "Checking…" : "Check key") {
                        let key = m.apiKey
                        m.checking = true
                        m.keyResult = nil
                        Task { @MainActor in
                            let result = await Gemini.checkKey(key)
                            m.keyResult = result
                            m.checking = false
                        }
                    }.disabled(m.checking)
                }
                if let r = m.keyResult {
                    Label(r.message, systemImage: r.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(r.ok ? Color.green : Color.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if m.saveFailed {
                    Text("The key could not be saved to the Keychain.").font(.footnote).foregroundStyle(.red)
                }
                Text("Create a key at aistudio.google.com/apikey. It is stored in your macOS Keychain and only sent to Google's Gemini API.")
                    .font(.footnote).foregroundStyle(.secondary)
                Button("How do I get a key? Step-by-step guide") {
                    if let url = URL(string: AppInfo.setupGuideURL) { NSWorkspace.shared.open(url) }
                }.buttonStyle(.link).font(.footnote)
                Divider()
                HStack {
                    Text("Model")
                    Spacer()
                    Picker("", selection: $m.model) {
                        Text("Default (\(defaultModel))").tag("")
                        ForEach(modelChoices, id: \.self) { Text($0).tag($0) }
                    }.labelsHidden().frame(width: 240)
                }
            }
        }
    }

    private var generalCard: some View {
        card("General", icon: "gearshape") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $m.launchAtLogin) {
                    Text("Open ScreenPulse at login")
                }
                .toggleStyle(.switch)
                .onChange(of: m.launchAtLogin) { on in
                    guard on != LoginItem.isEnabled else { return }
                    m.loginError = LoginItem.setEnabled(on)
                    if m.loginError != nil { m.launchAtLogin = LoginItem.isEnabled }
                }
                if let err = m.loginError {
                    Text(err).font(.footnote).foregroundStyle(.red)
                }
                Toggle(isOn: $m.modifierOnly) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Also trigger with ⌃⌥⌘ alone")
                        Text("Press and release Control + Option + Command without any other key. Requires Input Monitoring.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: m.modifierOnly) { _ in (NSApp.delegate as? AppDelegate)?.applyModifierOnlyHotkey() }
                Toggle(isOn: $m.updateChecks) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Check for updates automatically")
                        Text("Once a day ScreenPulse asks GitHub whether a newer version exists. GitHub sees your IP address and the app name and version, nothing else. Nothing is installed by itself.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .onChange(of: m.updateChecks) { on in if on { Updater.shared.checkIfDue() } }
                HStack {
                    Button("Check now") { Updater.shared.checkNow() }
                    Text("Version \(AppInfo.version)").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: Pieces

    private var speedLabel: String {
        switch m.blink {
        case ..<0.35: return "Fast"
        case ..<0.7: return "Normal"
        case ..<1.0: return "Slow"
        default: return "Very slow"
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 56, height: 56)
            VStack(alignment: .leading) {
                Text(AppInfo.name).font(.title.bold())
                Text("Settings · Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func card<C: View>(_ title: String, icon: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }

    private func hardwareRow(_ name: String, ok: Bool, missing: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(ok ? Color.green : Color.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                Text(ok ? "Detected" : missing).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func permRow(_ name: String, ok: Bool, hint: String, pane: String, request: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? .green : .orange).font(.title3)
            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                Text(ok ? "Granted" : hint).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            if !ok {
                Button("Open System Settings") {
                    request()
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }
}

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    /// Re-reads settings after they were changed from the menu bar.
    func reloadIfVisible() {
        guard let w = window, w.isVisible else { return }
        w.contentView = NSHostingView(rootView: SettingsView())
    }

    func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 720),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable],
                             backing: .buffered, defer: false)
            w.title = "ScreenPulse Settings"
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        // A fresh view every time, so the key and the permissions are re-read.
        window?.contentView = NSHostingView(rootView: SettingsView())
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
