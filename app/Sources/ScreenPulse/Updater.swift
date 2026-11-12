// Update check. Opt-in: ScreenPulse asks once whether it may look for a newer version.
//
// What it does: a single HTTPS request to GitHub's public "latest release" address for this project,
// at most once a day. GitHub sees the IP address and the app name and version (User-Agent).
// What it does not do: it never downloads or installs anything. It only offers to open the release page.

import AppKit

@MainActor
final class Updater {
    static let shared = Updater()

    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private var checking = false

    private enum Result { case newer(UpdateInfo), upToDate, noRelease, failed }

    /// Whether automatic checks are allowed. Not set until the user has answered.
    var hasAnswered: Bool { defaults.object(forKey: DefaultsKey.updateChecks) != nil }
    var enabled: Bool {
        get { defaults.bool(forKey: DefaultsKey.updateChecks) }
        set { defaults.set(newValue, forKey: DefaultsKey.updateChecks) }
    }

    /// Call once at launch. `canAsk` is false for silent launches, which never show a window.
    func start(canAsk: Bool) {
        if !hasAnswered && canAsk {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                self.askPermission()
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkIfDue() }
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            self.checkIfDue()
        }
    }

    private func askPermission() {
        guard !hasAnswered else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Check for updates automatically?"
        alert.informativeText = "ScreenPulse can ask GitHub once a day whether a newer version has been released. GitHub then sees your IP address and the name and version of the app, nothing else. ScreenPulse never installs anything by itself. You can change this in Settings."
        alert.addButton(withTitle: "Check Automatically")
        alert.addButton(withTitle: "No Thanks")
        enabled = alert.runModal() == .alertFirstButtonReturn
        if enabled { checkIfDue() }
    }

    func checkIfDue() {
        let last = defaults.object(forKey: DefaultsKey.lastUpdateCheck) as? Date
        guard enabled, UpdateCheck.isDue(last: last) else { return }
        Task { @MainActor in await self.check(manual: false) }
    }

    /// "Check for Updates…" in the menus and Settings. Always answers, even when automatic checks are off.
    func checkNow() {
        Task { @MainActor in await self.check(manual: true) }
    }

    private func check(manual: Bool) async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
        defaults.set(Date(), forKey: DefaultsKey.lastUpdateCheck)

        switch await fetch() {
        case .newer(let info):
            // Automatic checks mention a version once; a manual check always shows it.
            if !manual && (defaults.string(forKey: DefaultsKey.notifiedUpdate) == info.tag
                           || defaults.string(forKey: DefaultsKey.skippedUpdate) == info.tag) { return }
            defaults.set(info.tag, forKey: DefaultsKey.notifiedUpdate)
            present(info)
        case .upToDate:
            if manual { inform("ScreenPulse is up to date", "You have the latest version (\(AppInfo.version)).") }
        case .noRelease:
            if manual { inform("No release found", "No release has been published yet, or it is not public.") }
        case .failed:
            if manual { inform("Could not check for updates", "ScreenPulse could not reach GitHub. Check your internet connection and try again.") }
        }
    }

    private func fetch() async -> Result {
        guard let url = URL(string: AppInfo.latestReleaseAPI) else { return .failed }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("\(AppInfo.name)/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 404 { return .noRelease }
            guard status == 200,
                  let info = UpdateCheck.parseRelease(data, trustedPrefix: AppInfo.trustedReleasePrefix),
                  let local = AppVersion(AppInfo.version) else { return .failed }
            return UpdateCheck.isUpdate(remote: info.version, over: local) ? .newer(info) : .upToDate
        } catch {
            return .failed
        }
    }

    private func present(_ info: UpdateInfo) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "ScreenPulse \(info.version.text) is available"
        alert.informativeText = "You have version \(AppInfo.version). Download the new disk image from the release page, then drag ScreenPulse onto Applications again and replace the old one."
        alert.addButton(withTitle: "Open Release Page")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "Skip This Version")
        switch alert.runModal() {
        case .alertFirstButtonReturn: NSWorkspace.shared.open(info.pageURL)
        case .alertThirdButtonReturn: defaults.set(info.tag, forKey: DefaultsKey.skippedUpdate)
        default: break
        }
    }

    private func inform(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
