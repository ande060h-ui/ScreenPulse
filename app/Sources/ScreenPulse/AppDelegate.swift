// Application lifecycle, menu bar item, hotkeys and the capture → ask → present flow.

import AppKit
import Carbon.HIToolbox
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let panel = AnswerPanel()
    var lastImage: String?
    var busy = false
    var comboHeld = false     // ⌃⌥⌘ is held down right now
    var comboSpoiled = false  // another key was pressed meanwhile (e.g. ⌃⌥⌘+K in another app)
    var hotKeyRefs: [EventHotKeyRef?] = []
    var modifierMonitors: [Any] = []
    let settings = ModeSettings()
    /// Set by --silent and friends: this session runs in Focus Mode with the window hidden,
    /// without changing the saved settings.
    var launchedSilent = false

    var mode: AppMode { launchedSilent ? .focus : settings.mode }
    var outputs: OutputOptions {
        var o = settings.outputs(for: mode)
        if launchedSilent { o.window = false }
        return o
    }
    var statusItem: NSStatusItem?

    private enum HotKey: UInt32 { case capture = 1, togglePanel = 2 }

    // MARK: Launch

    /// --silent / --background / --no-overlay / -s, or SILENT_MODE=1 / BACKGROUND_MODE=1.
    func checkSilentLaunch() -> Bool {
        let args = CommandLine.arguments
        if args.contains("--silent") || args.contains("--background") || args.contains("--no-overlay") || args.contains("-s") {
            return true
        }
        let env = ProcessInfo.processInfo.environment
        if env["SILENT_MODE"] == "1" || env["BACKGROUND_MODE"] == "1" { return true }
        return projectEnvValue("SILENT_MODE") == "1" || projectEnvValue("BACKGROUND_MODE") == "1"
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        launchedSilent = checkSilentLaunch()

        // Menu bar app: no Dock icon, everything is opened from the menu bar icon.
        NSApp.setActivationPolicy(.accessory)
        setupStatusBarItem()
        buildMenu()

        panel.onAskAgain = { [weak self] q in self?.askAbout(image: self?.lastImage, question: q) }
        panel.setStatus("Point at something and press ⌃⌥⌘ + Space")
        panel.append("Point at anything on screen — a question, a piece of text, an error message — then press Control + Option + Command + Space.\n\nThe answer appears here.")

        registerHotKeys()
        applyModifierOnlyHotkey()
        Updater.shared.start(canAsk: !launchedSilent)

        // Opened from Finder: show Settings so it is obvious the app is running.
        if !launchedSilent { SettingsWindowController.shared.show() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ app: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ app: NSApplication, hasVisibleWindows: Bool) -> Bool {
        SettingsWindowController.shared.show() // opening the app again = open Settings
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        CapsLED.shared.stopThinking()
        CapsLED.shared.restore()
    }

    // MARK: Menu bar

    func setupStatusBarItem() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            if let button = statusItem?.button {
                button.image = BrandIcon.menuBarImage()
            }
        }
        statusItem?.button?.toolTip = "ScreenPulse · \(mode.title)"
        updateStatusBarMenu()
    }

    func updateStatusBarMenu() {
        guard let item = statusItem else { return }
        let menu = NSMenu()
        menu.addItem(withTitle: "Ask About Screen (⌃⌥⌘ Space)", action: #selector(triggerCapture), keyEquivalent: "")
        menu.addItem(withTitle: "Show Last Answer (⌃⌥⌘ 0)", action: #selector(showPanel), keyEquivalent: "")
        menu.addItem(.separator())

        for item in makeModeItems() { menu.addItem(item) }

        let signals = NSMenuItem(title: "Keyboard Signals", action: nil, keyEquivalent: "")
        signals.submenu = makeSignalsMenu()
        menu.addItem(signals)
        menu.addItem(.separator())

        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        menu.addItem(withTitle: "Open Knowledge Folder", action: #selector(openKnowledgeFolder), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit ScreenPulse", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
    }

    /// Mode choice and the answer-window switch for the current mode.
    private func makeModeItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        for (m, action) in [(AppMode.normal, #selector(chooseNormalMode)), (AppMode.focus, #selector(chooseFocusMode))] {
            let item = NSMenuItem(title: m.title, action: action, keyEquivalent: "")
            item.state = mode == m ? .on : .off
            items.append(item)
        }
        let window = NSMenuItem(title: "Show Answer Window in \(mode.title)", action: #selector(toggleWindowOutput), keyEquivalent: "")
        window.state = outputs.window ? .on : .off
        items.append(window)
        return items
    }

    private func makeSignalsMenu() -> NSMenu {
        let m = NSMenu()
        m.addItem(withTitle: "Test “Thinking” (3 Seconds)", action: #selector(testFade), keyEquivalent: "")
        m.addItem(withTitle: "Test “Answer: A” (1 Blink)", action: #selector(testBlinkA), keyEquivalent: "")
        m.addItem(withTitle: "Test “Answer: B” (2 Blinks)", action: #selector(testBlinkB), keyEquivalent: "")
        m.addItem(withTitle: "Test “Answer: C” (3 Blinks)", action: #selector(testBlinkC), keyEquivalent: "")
        m.addItem(withTitle: "Test “Answer: D” (4 Blinks)", action: #selector(testBlinkD), keyEquivalent: "")
        m.addItem(withTitle: "Test “Yes” (1 Long)", action: #selector(testYes), keyEquivalent: "")
        m.addItem(withTitle: "Test “No” (2 Long)", action: #selector(testNo), keyEquivalent: "")
        m.addItem(withTitle: "Test “Answer Ready” (2 Short)", action: #selector(testReady), keyEquivalent: "")
        m.addItem(withTitle: "Test “Error” (3 Quick)", action: #selector(testError), keyEquivalent: "")
        m.addItem(.separator())
        m.addItem(withTitle: "Restore Keyboard Lights", action: #selector(restoreLED), keyEquivalent: "")
        return m
    }

    /// Main menu (only visible while a ScreenPulse window is active).
    func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        appMenu.addItem(withTitle: "Ask About Screen (⌃⌥⌘ Space)", action: #selector(triggerCapture), keyEquivalent: "")
        appMenu.addItem(withTitle: "Show Answer Window", action: #selector(showPanel), keyEquivalent: "0")
        appMenu.addItem(withTitle: "Hide Answer Window", action: #selector(hidePanel), keyEquivalent: "h")

        for item in makeModeItems() { appMenu.addItem(item) }
        appMenu.addItem(.separator())

        let signals = NSMenuItem(title: "Keyboard Signals", action: nil, keyEquivalent: "")
        signals.submenu = makeSignalsMenu()
        appMenu.addItem(signals)
        appMenu.addItem(.separator())

        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        appMenu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        appMenu.addItem(withTitle: "Open Knowledge Folder", action: #selector(openKnowledgeFolder), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit ScreenPulse", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Edit menu, so ⌘C / ⌘V / ⌘A work in the question and API key fields.
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit"); editItem.submenu = edit
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        NSApp.mainMenu = main
    }

    // MARK: Modes

    @objc func openSettings() { SettingsWindowController.shared.show() }

    /// Called whenever the mode or its outputs change (Settings or menu).
    func modeSettingsChanged() {
        if !outputs.window { panel.orderOut(nil) }
        setupStatusBarItem()
        buildMenu()
    }

    private func choose(_ m: AppMode) {
        launchedSilent = false // an explicit choice ends the --silent session override
        settings.mode = m
        modeSettingsChanged()
        SettingsWindowController.shared.reloadIfVisible()
    }
    @objc func chooseNormalMode() { choose(.normal) }
    @objc func chooseFocusMode() { choose(.focus) }

    @objc func toggleWindowOutput() {
        launchedSilent = false
        var o = settings.outputs(for: mode)
        o.window.toggle()
        settings.setOutputs(o, for: mode)
        modeSettingsChanged()
        if o.window { panel.show() }
        SettingsWindowController.shared.reloadIfVisible()
    }

    // MARK: Hotkeys

    /// Global hotkeys that need no extra permission: ⌃⌥⌘ Space (ask) and ⌃⌥⌘ 0 (answer window).
    func registerHotKeys() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hk = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            guard status == noErr else { return status }
            let id = hk.id
            DispatchQueue.main.async {
                (NSApp.delegate as? AppDelegate)?.hotKeyFired(id)
            }
            return noErr
        }, 1, &spec, nil, nil)

        let signature = OSType(0x5343_5250) // "SCRP"
        let modifiers = UInt32(controlKey | optionKey | cmdKey)
        for (key, id) in [(kVK_Space, HotKey.capture), (kVK_ANSI_0, HotKey.togglePanel)] {
            var ref: EventHotKeyRef?
            RegisterEventHotKey(UInt32(key), modifiers, EventHotKeyID(signature: signature, id: id.rawValue),
                                GetApplicationEventTarget(), 0, &ref)
            hotKeyRefs.append(ref)
        }
    }

    func hotKeyFired(_ id: UInt32) {
        guard let key = HotKey(rawValue: id) else { return }
        switch key {
        case .capture: triggerCapture()
        case .togglePanel: if panel.isVisible { panel.orderOut(nil) } else { panel.show() }
        }
    }

    /// Optional trigger: ⌃⌥⌘ on their own (Settings). Needs the Input Monitoring permission,
    /// because it observes modifier keys while other apps are active.
    func applyModifierOnlyHotkey() {
        for m in modifierMonitors { NSEvent.removeMonitor(m) }
        modifierMonitors.removeAll()
        comboHeld = false
        guard UserDefaults.standard.bool(forKey: DefaultsKey.modifierOnlyHotkey) else { return }
        if !CGPreflightListenEventAccess() { _ = CGRequestListenEventAccess() }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] event in
            let flags = event.modifierFlags
            Task { @MainActor in self?.flagsChanged(flags) }
        }) { modifierMonitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] _ in
            Task { @MainActor in self?.otherKeyPressed() }
        }) { modifierMonitors.append(m) }
    }

    /// ⌃⌥⌘ alone: fires when the keys are released, but only if no other key was pressed meanwhile.
    func flagsChanged(_ flags: NSEvent.ModifierFlags) {
        let target: NSEvent.ModifierFlags = [.control, .option, .command]
        let f = flags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .function, .numericPad])
        if f == target {
            if !comboHeld { comboHeld = true; comboSpoiled = false }
        } else if f.isSuperset(of: target) {
            comboSpoiled = true // e.g. Shift as well: not our shortcut
        } else if comboHeld {
            comboHeld = false
            if !comboSpoiled { triggerCapture() }
        }
    }

    func otherKeyPressed() {
        if comboHeld { comboSpoiled = true }
    }

    // MARK: Capture and ask

    /// Shows a problem to the user on whatever outputs are enabled. If none is, the window is used.
    private func report(_ status: String, _ message: String, outputs o: OutputOptions) {
        CapsLED.shared.stopThinking()
        if o.anyLight { CapsLED.shared.blinkError(outputs: o) }
        panel.setStatus(status, .error)
        panel.clear()
        panel.append(message)
        if o.window || !o.anyLight { panel.show() }
    }

    @objc func triggerCapture() {
        guard !busy else { return }
        let o = outputs
        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            report("Screen Recording permission missing",
                   "Allow ScreenPulse under System Settings → Privacy & Security → Screen & System Audio Recording.\n\nThen quit ScreenPulse and open it again.", outputs: o)
            return
        }
        busy = true
        // The window is hidden during capture so it does not end up in the screenshot.
        let panelWasVisible = panel.isVisible
        panel.orderOut(nil)
        Task { @MainActor in
            if panelWasVisible { try? await Task.sleep(nanoseconds: 150_000_000) }
            let shot = await Screenshot.aroundCursor()
            if o.window || panelWasVisible { panel.show(); panel.setStatus("Capturing the screen…", .working) }
            guard let img = shot else {
                report("Screen capture failed",
                       "Could not capture the screen. Allow ScreenPulse under System Settings → Privacy & Security → Screen & System Audio Recording, then restart the app.", outputs: o)
                busy = false
                return
            }
            lastImage = img
            busy = false
            askAbout(image: img, question: panel.customQuestion)
        }
    }

    func askAbout(image: String?, question: String) {
        guard let image, !busy else { return }
        busy = true
        // Mode and outputs are fixed for the whole question, even if settings change meanwhile.
        let mode = self.mode
        let o = outputs
        panel.clear()
        panel.setStatus("Thinking… · \(mode.title)", .working)
        if o.anyLight { CapsLED.shared.startThinking(outputs: o) }

        let started = Date()
        let stream = AnswerStream(filterSignalLine: mode == .normal)
        Task { @MainActor in
            do {
                try await Gemini.ask(imageBase64: image, question: question, mode: mode,
                    onModel: { model in
                        Task { @MainActor in
                            self.panel.modelName = model
                            self.panel.setStatus("Thinking… · \(model)", .working)
                        }
                    },
                    onText: { text in
                        let (visible, isFirst) = stream.append(text)
                        guard !visible.isEmpty else { return }
                        Task { @MainActor in
                            if isFirst {
                                let secs = String(format: "%.1f", Date().timeIntervalSince(started))
                                self.panel.setStatus("Answer · \(self.panel.modelName) · \(secs) s", .done)
                            }
                            self.panel.append(visible)
                        }
                    })
                let rest = stream.finish()
                if !rest.isEmpty { self.panel.append(rest) }

                // Answer ready: work out what to signal for this mode.
                let signal: Signal
                switch mode {
                case .focus: signal = AnswerParser.focusSignal(stream.raw)
                case .normal: signal = AnswerParser.normalAnswer(stream.raw).signal
                }
                CapsLED.shared.stopThinking()
                if o.anyLight {
                    CapsLED.shared.play(signal, outputs: o)
                    self.panel.setStatus("Answer · signalled: \(signal.label) · \(self.panel.modelName)", .done)
                } else {
                    self.panel.setStatus("Answer · \(self.panel.modelName)", .done)
                }
            } catch let e as Gemini.Failure {
                self.fail(e.message, outputs: o)
            } catch {
                self.fail("Error: \(error.localizedDescription)", outputs: o)
            }
            self.busy = false
        }
    }

    private func fail(_ message: String, outputs o: OutputOptions) {
        CapsLED.shared.stopThinking()
        if o.anyLight { CapsLED.shared.blinkError(outputs: o) }
        panel.setStatus(panel.modelName.isEmpty ? "Error" : "Error · \(panel.modelName)", .error)
        panel.append(message)
        if !o.window && !o.anyLight { panel.show() }
    }

    // MARK: Signal tests

    private var showsTestStatus: Bool { panel.isVisible }

    @objc func testFade() {
        if showsTestStatus { panel.setStatus("Testing keyboard signal: thinking…", .working) }
        CapsLED.shared.startThinking()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            CapsLED.shared.stopThinking()
            CapsLED.shared.restore()
            if self.showsTestStatus { self.panel.setStatus("Thinking test finished.") }
        }
    }

    private func test(_ signal: Signal, _ description: String) {
        if showsTestStatus { panel.setStatus("Testing keyboard signal: \(description)", .working) }
        CapsLED.shared.play(signal)
    }
    @objc func testBlinkA() { test(.letters("A"), "Answer A (1 blink)") }
    @objc func testBlinkB() { test(.letters("B"), "Answer B (2 blinks)") }
    @objc func testBlinkC() { test(.letters("C"), "Answer C (3 blinks)") }
    @objc func testBlinkD() { test(.letters("D"), "Answer D (4 blinks)") }
    @objc func testYes() { test(.yes, "Yes (1 long)") }
    @objc func testNo() { test(.no, "No (2 long)") }
    @objc func testReady() { test(.ready, "Answer ready (2 short)") }
    @objc func testError() { test(.error, "Error (3 quick)") }

    @objc func restoreLED() {
        CapsLED.shared.stopThinking()
        CapsLED.shared.restore()
        if showsTestStatus { panel.setStatus("Keyboard lights restored.") }
    }

    // MARK: Misc actions

    @objc func openKnowledgeFolder() {
        let dir = AppPaths.knowledgeDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    @objc func checkForUpdates() { Updater.shared.checkNow() }
    @objc func showPanel() { panel.show() }
    @objc func hidePanel() { panel.orderOut(nil) }
}

/// Collects the streamed answer. Written from the network callback, read on the main actor.
/// In Normal Mode it also hides the leading "Signal: …" line from the text shown in the window.
final class AnswerStream: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""
    private var filter: SignalLineFilter?
    private var shownAny = false

    init(filterSignalLine: Bool) { filter = filterSignalLine ? SignalLineFilter() : nil }

    /// Appends a chunk. Returns the part to display and whether it is the first visible text.
    func append(_ chunk: String) -> (visible: String, isFirst: Bool) {
        lock.lock(); defer { lock.unlock() }
        buffer += chunk
        let visible = filter?.feed(chunk) ?? chunk
        let first = !shownAny && !visible.isEmpty
        if first { shownAny = true }
        return (visible, first)
    }

    /// Text still held back by the filter when the stream ends.
    func finish() -> String {
        lock.lock(); defer { lock.unlock() }
        return filter?.finish() ?? ""
    }

    /// Everything the model sent, including the signal line.
    var raw: String {
        lock.lock(); defer { lock.unlock() }
        return buffer
    }
}

// MARK: - Launch at login

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// Returns an error message on failure, nil on success.
    static func setEnabled(_ on: Bool) -> String? {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
