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

enum SettingsTab: String, CaseIterable {
    case mode = "Mode", signal = "Signal", gemini = "Gemini", general = "General"
}

struct SettingsView: View {
    @StateObject private var m = SettingsModel()
    /// The tab that was open last; a new key opens on Gemini so first-time users start there.
    static var lastTab: SettingsTab?
    @State private var tab: SettingsTab = SettingsView.lastTab
        ?? ((KeyStore.loadStored() ?? "").isEmpty ? .gemini : .mode)
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 24).padding(.top, 6).padding(.bottom, 16)
            tabBar
                .padding(.horizontal, 24).padding(.bottom, 14)
            Rule()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch tab {
                    case .mode: modeTab
                    case .signal: signalTab
                    case .gemini: geminiTab
                    case .general: generalTab
                    }
                }
                .padding(24)
            }
        }
        .font(SPFont.font(14))
        .foregroundStyle(SP.ink)
        .tint(SP.link)
        .background(SP.window.ignoresSafeArea())
        .frame(minWidth: 560, idealWidth: 600, minHeight: 520, idealHeight: 700)
        .onChange(of: tab) { SettingsView.lastTab = $0 }
        .onReceive(timer) { _ in
            m.screenOK = CGPreflightScreenCaptureAccess()
            m.inputOK = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        }
    }

    // MARK: Frame

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 48, height: 48)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(AppInfo.name).font(SPFont.font(22, .semibold)).tracking(-0.4)
                Text("Version \(AppInfo.version)").font(SPFont.font(12.5)).foregroundStyle(SP.muted)
            }
            Spacer()
        }
    }

    private var tabBar: some View {
        HStack(spacing: 8) {
            ForEach(SettingsTab.allCases, id: \.self) { t in
                Button(t.rawValue) { tab = t }
                    .buttonStyle(KeyButtonStyle(small: true, led: tab == t, latched: tab == t))
                    .accessibilityAddTraits(tab == t ? .isSelected : [])
            }
            Spacer()
        }
    }

    // MARK: Mode

    @ViewBuilder private var modeTab: some View {
        Panel(title: "Mode") {
            HStack(spacing: 8) {
                ForEach(AppMode.allCases, id: \.self) { mode in
                    Button(mode.title) { m.mode = mode }
                        .buttonStyle(KeyButtonStyle(led: m.mode == mode, latched: m.mode == mode, minWidth: 150))
                        .accessibilityAddTraits(m.mode == mode ? .isSelected : [])
                }
            }
            Note(verbatim: m.mode == .normal
                 ? "A general screen assistant. Point at anything (a question, text, an error message, a chart) and get an explanatory answer."
                 : "Minimal and fast. For multiple-choice questions ScreenPulse returns only the letter. Anything else gets one short sentence and is never turned into a letter.")
                .padding(.top, 2)
        }
        Panel(title: "Outputs in \(m.mode.title)") {
            VStack(spacing: 0) {
                outputRow("Answer window", isOn: $m.outputs.window, first: true)
                outputRow("Caps Lock light", isOn: $m.outputs.capsLock)
                outputRow("Keyboard backlight", isOn: $m.outputs.backlight)
            }
            Note(verbatim: outputHint)
        }
        .onChange(of: m.mode) { _ in (NSApp.delegate as? AppDelegate)?.modeSettingsChanged() }
        .onChange(of: m.outputs) { _ in (NSApp.delegate as? AppDelegate)?.modeSettingsChanged() }
    }

    private func outputRow(_ title: String, isOn: Binding<Bool>, first: Bool = false) -> some View {
        VStack(spacing: 0) {
            if !first { Rule() }
            Toggle(isOn: isOn) { RowLabel(title: title) }
                .toggleStyle(LEDToggleStyle())
                .padding(.vertical, 9)
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

    // MARK: Signal

    @ViewBuilder private var signalTab: some View {
        Panel(title: "Keyboard signal") {
            HStack {
                Text("Blink speed").font(SPFont.font(14, .medium))
                Spacer()
                Text(speedLabel).foregroundStyle(SP.muted)
            }
            HStack(spacing: 12) {
                Text("Calmer").font(SPFont.font(12)).foregroundStyle(SP.muted)
                DotSlider(value: $m.blink, range: 0.2...1.2, step: 0.05, label: "Blink speed")
                Text("Faster").font(SPFont.font(12)).foregroundStyle(SP.muted)
            }
            .padding(.vertical, 4)
            Note("Letters and digits are counted out (A = 1 blink, B = 2, 3 = three blinks). Yes is one long light, no is two. Two short blinks mean an answer is ready in the window; three quick ones mean an error.")
            HStack(spacing: 8) {
                testKey("Test A") { CapsLED.shared.blinkText("A") }
                testKey("Test B") { CapsLED.shared.blinkText("B") }
                testKey("Yes") { CapsLED.shared.play(.yes) }
                testKey("No") { CapsLED.shared.play(.no) }
                testKey("Ready") { CapsLED.shared.play(.ready) }
                testKey("Thinking") {
                    CapsLED.shared.startThinking()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        CapsLED.shared.stopThinking(); CapsLED.shared.restore()
                    }
                }
                Spacer(minLength: 8)
                testKey("Restore lights") { CapsLED.shared.stopThinking(); CapsLED.shared.restore() }
            }
            .padding(.top, 4)
        }
        Panel(title: "Lights on this Mac") {
            VStack(spacing: 0) {
                hardwareRow("Caps Lock light", ok: m.hasCapsLED,
                            missing: "Not found. Grant Input Monitoring and restart, or connect a keyboard with a Caps Lock light.")
                Rule()
                hardwareRow("Keyboard backlight", ok: m.hasBacklight,
                            missing: "Not available on this Mac or keyboard.")
            }
        }
    }

    private func testKey(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action).buttonStyle(KeyButtonStyle(small: true))
    }

    private var speedLabel: String {
        switch m.blink {
        case ..<0.35: return "Fast"
        case ..<0.7: return "Normal"
        case ..<1.0: return "Slow"
        default: return "Very slow"
        }
    }

    private func hardwareRow(_ name: String, ok: Bool, missing: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            LED(on: ok).alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
            if ok {
                Text(name).font(SPFont.font(14, .medium))
                Spacer()
                Text("Detected").font(SPFont.font(12.5)).foregroundStyle(SP.muted)
            } else {
                RowLabel(title: name, detail: missing)
                Spacer()
            }
        }
        .padding(.vertical, 10)
    }

    // MARK: Gemini

    @ViewBuilder private var geminiTab: some View {
        Panel(title: "Gemini (AI)") {
            Text("API key").font(SPFont.font(14, .medium))
            HStack(spacing: 8) {
                Group {
                    if m.showKey { TextField("Paste your key", text: $m.apiKey) }
                    else { SecureField("Paste your key", text: $m.apiKey) }
                }
                .textFieldStyle(SPFieldStyle())
                .accessibilityLabel("API key")
                Button(m.showKey ? "Hide" : "Show") { m.showKey.toggle() }
                    .buttonStyle(KeyButtonStyle())
            }
            HStack(spacing: 8) {
                Button(m.saved ? "Saved" : "Save") {
                    let ok = KeyStore.save(m.apiKey.trimmingCharacters(in: .whitespacesAndNewlines))
                    m.saved = ok
                    m.saveFailed = !ok
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { m.saved = false }
                }
                .buttonStyle(KeyButtonStyle(main: true, minWidth: 96))
                Button(m.checking ? "Checking…" : "Check key") {
                    let key = m.apiKey
                    m.checking = true
                    m.keyResult = nil
                    Task { @MainActor in
                        let result = await Gemini.checkKey(key)
                        m.keyResult = result
                        m.checking = false
                    }
                }
                .buttonStyle(KeyButtonStyle())
                .disabled(m.checking)
            }
            .padding(.top, 2)
            if let r = m.keyResult {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Group {
                        if r.ok { LED(on: true) } else { StatusDot(color: SP.error) }
                    }
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 4 }
                    Text(r.message).font(SPFont.font(13, .medium))
                        .foregroundStyle(r.ok ? SP.ink : SP.error)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 2)
            }
            if m.saveFailed {
                Text("The key could not be saved to the Keychain.").font(SPFont.font(12.5)).foregroundStyle(SP.error)
            }
            Note("Create a key at aistudio.google.com/apikey. It is stored in your macOS Keychain and only sent to Google's Gemini API.")
                .padding(.top, 4)
            Button {
                if let url = URL(string: AppInfo.setupGuideURL) { NSWorkspace.shared.open(url) }
            } label: {
                Text("How do I get a key? Step-by-step guide").underline()
                    .font(SPFont.font(13, .medium)).foregroundStyle(SP.link)
            }
            .buttonStyle(.plain)
            .onHover { inside in if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
        }
        Panel(title: "Model") {
            HStack {
                Text("Model").font(SPFont.font(14, .medium))
                Spacer()
                Picker("Model", selection: $m.model) {
                    Text("Default (\(defaultModel))").tag("")
                    ForEach(modelChoices, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden().frame(width: 260)
            }
        }
    }

    // MARK: General

    @ViewBuilder private var generalTab: some View {
        Panel(title: "Permissions") {
            VStack(spacing: 0) {
                permRow("Screen Recording", ok: m.screenOK, hint: "Required to capture the screen.",
                        pane: "Privacy_ScreenCapture") { _ = CGRequestScreenCaptureAccess() }
                Rule()
                permRow("Input Monitoring", ok: m.inputOK, hint: "Required to control the Caps Lock light.",
                        pane: "Privacy_ListenEvent") { _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) }
            }
            Note("After granting a permission, quit ScreenPulse from the menu bar icon and open it again.")
        }
        Panel(title: "General") {
            VStack(spacing: 0) {
                Toggle(isOn: $m.launchAtLogin) { RowLabel(title: "Open ScreenPulse at login") }
                    .toggleStyle(LEDToggleStyle())
                    .padding(.vertical, 9)
                    .onChange(of: m.launchAtLogin) { on in
                        guard on != LoginItem.isEnabled else { return }
                        m.loginError = LoginItem.setEnabled(on)
                        if m.loginError != nil { m.launchAtLogin = LoginItem.isEnabled }
                    }
                if let err = m.loginError {
                    Text(err).font(SPFont.font(12.5)).foregroundStyle(SP.error)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 8)
                }
                Rule()
                Toggle(isOn: $m.modifierOnly) {
                    RowLabel(title: "Also trigger with ⌃⌥⌘ alone",
                             detail: "Press and release Control + Option + Command without any other key. Requires Input Monitoring.")
                }
                .toggleStyle(LEDToggleStyle())
                .padding(.vertical, 9)
                .onChange(of: m.modifierOnly) { _ in (NSApp.delegate as? AppDelegate)?.applyModifierOnlyHotkey() }
                Rule()
                Toggle(isOn: $m.updateChecks) {
                    RowLabel(title: "Check for updates automatically",
                             detail: "Once a day ScreenPulse asks GitHub whether a newer version exists. GitHub sees your IP address and the app name and version, nothing else. An update is installed only when you click Install.")
                }
                .toggleStyle(LEDToggleStyle())
                .padding(.vertical, 9)
                .onChange(of: m.updateChecks) { on in if on { Updater.shared.checkIfDue() } }
                Rule()
                HStack(spacing: 12) {
                    Button("Check now") { Updater.shared.checkNow() }
                        .buttonStyle(KeyButtonStyle(small: true))
                    Text("Version \(AppInfo.version)").font(SPFont.font(12.5)).foregroundStyle(SP.muted)
                    Spacer()
                }
                .padding(.top, 12)
            }
        }
        Panel(title: "How to use") {
            VStack(alignment: .leading, spacing: 6) {
                Text("1. Point at a question or a piece of text.")
                Text("2. Press **Control + Option + Command + Space**.")
                Text("3. The answer arrives on the outputs you chose under Mode: in the window, on the keyboard lights, or both.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(SPFont.font(13.5))
            Note("Press **Control + Option + Command + 0** to show or hide the answer window.")
                .padding(.top, 2)
        }
    }

    private func permRow(_ name: String, ok: Bool, hint: String, pane: String, request: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 12) {
            if ok { LED(on: true) } else { StatusDot(color: SP.attention) }
            if ok {
                Text(name).font(SPFont.font(14, .medium))
                Spacer()
                Text("Granted").font(SPFont.font(12.5)).foregroundStyle(SP.muted)
            } else {
                RowLabel(title: name, detail: hint)
                Spacer()
                Button("Open System Settings") {
                    request()
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .buttonStyle(KeyButtonStyle(small: true))
            }
        }
        .padding(.vertical, 10)
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
            SPFont.register()
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 700),
                             styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                             backing: .buffered, defer: false)
            w.title = "ScreenPulse Settings"
            w.titlebarAppearsTransparent = true
            w.backgroundColor = SP.windowNS
            w.minSize = NSSize(width: 560, height: 520)
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
