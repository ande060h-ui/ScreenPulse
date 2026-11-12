// Installs a new version after the user has said yes in the update dialog.
//
// 1. Downloads ScreenPulse.dmg and ScreenPulse.dmg.sig from the project's own GitHub release.
// 2. Refuses the disk image unless its Ed25519 signature matches the key built into the app.
// 3. Opens the disk image, checks that it holds ScreenPulse with the expected version and a valid
//    code signature, and copies it over this app (asking for an administrator password only if the
//    folder is not writable). The old copy is kept until the new one is in place.
// 4. Starts the new version and quits this one.

import AppKit

enum UpdateInstallError: LocalizedError {
    case notInstallable(String)
    case download
    case badSignature
    case badImage(String)
    case copy(String)

    var errorDescription: String? {
        switch self {
        case .notInstallable(let why): return why
        case .download: return "The update could not be downloaded. Check your internet connection and try again."
        case .badSignature: return "The downloaded update did not pass the signature check, so it was not installed. Nothing was changed."
        case .badImage(let why): return "The downloaded update looks wrong (\(why)), so it was not installed. Nothing was changed."
        case .copy(let why): return "ScreenPulse could not replace itself (\(why)). Your current version is unchanged."
        }
    }
}

@MainActor
final class UpdateInstaller {
    static let shared = UpdateInstaller()
    private var progress: NSPanel?

    /// Why this copy cannot update itself, or nil when it can.
    static var blocker: String? {
        let path = Bundle.main.bundleURL.path
        if Bundle.main.bundleIdentifier != AppInfo.releaseBundleID {
            return "This is a test build, which does not install updates."
        }
        if path.contains("/AppTranslocation/") || path.hasPrefix("/Volumes/") {
            return "ScreenPulse is running from the disk image or a temporary location. Drag it to Applications first, open it from there, and try again."
        }
        return nil
    }

    func install(_ info: UpdateInfo) async throws {
        if let why = Self.blocker { throw UpdateInstallError.notInstallable(why) }
        guard let dmgURL = info.dmgURL, let sigURL = info.signatureURL else {
            throw UpdateInstallError.notInstallable("This release cannot be installed automatically.")
        }
        showProgress("Downloading ScreenPulse \(info.version.text)…")
        defer { hideProgress() }

        let work = FileManager.default.temporaryDirectory.appendingPathComponent("ScreenPulse-update-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        // 1. Download
        let dmgData: Data, sigText: String
        do {
            dmgData = try await Self.download(dmgURL)
            sigText = String(decoding: try await Self.download(sigURL), as: UTF8.self)
        } catch { throw UpdateInstallError.download }

        // 2. Signature
        guard UpdateCheck.verifySignature(of: dmgData, signature: sigText, publicKey: AppInfo.updatePublicKey) else {
            throw UpdateInstallError.badSignature
        }
        let dmgFile = work.appendingPathComponent(UpdateCheck.dmgName)
        do { try dmgData.write(to: dmgFile) } catch { throw UpdateInstallError.download }

        showProgress("Installing ScreenPulse \(info.version.text)…")
        let target = Bundle.main.bundleURL
        let expected = info.version
        try await Task.detached(priority: .userInitiated) {
            // 3. Open the disk image and check what is inside
            let mount = work.appendingPathComponent("mnt")
            try? FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
            guard Self.run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly", "-noautoopen",
                                                "-mountpoint", mount.path, dmgFile.path]).status == 0 else {
                throw UpdateInstallError.badImage("the disk image could not be opened")
            }
            defer { _ = Self.run("/usr/bin/hdiutil", ["detach", mount.path, "-force"]) }

            let newApp = mount.appendingPathComponent("ScreenPulse.app")
            guard let plist = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist")) else {
                throw UpdateInstallError.badImage("no ScreenPulse app inside")
            }
            guard plist["CFBundleIdentifier"] as? String == AppInfo.releaseBundleID else {
                throw UpdateInstallError.badImage("a different app inside")
            }
            guard let v = AppVersion(plist["CFBundleShortVersionString"] as? String ?? ""), v == expected else {
                throw UpdateInstallError.badImage("an unexpected version inside")
            }
            guard Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path]).status == 0 else {
                throw UpdateInstallError.badImage("the app's code signature is broken")
            }

            // 4. Copy it over this app, keeping the old copy until the new one is in place
            let script = """
            set -e
            SRC="$1"; DST="$2"
            NEW="$DST.new-$$"; OLD="$DST.old-$$"
            rm -rf "$NEW"
            /usr/bin/ditto "$SRC" "$NEW"
            mv "$DST" "$OLD"
            if mv "$NEW" "$DST"; then rm -rf "$OLD"; else mv "$OLD" "$DST"; rm -rf "$NEW"; exit 1; fi
            """
            let plain = Self.run("/bin/sh", ["-c", script, "sh", newApp.path, target.path])
            if plain.status != 0 {
                // Not allowed to write there: ask macOS for an administrator password.
                let cmd = "/bin/sh -c \(Self.shQuote(script)) sh \(Self.shQuote(newApp.path)) \(Self.shQuote(target.path))"
                let apple = "do shell script \"\(Self.appleEscape(cmd))\" with administrator privileges"
                let admin = Self.run("/usr/bin/osascript", ["-e", apple])
                if admin.status != 0 {
                    let cancelled = admin.output.contains("-128")
                    throw UpdateInstallError.copy(cancelled ? "the password request was cancelled" : "permission denied")
                }
            }
        }.value

        // 5. Start the new version and quit
        let relaunch = Process()
        relaunch.executableURL = URL(fileURLWithPath: "/bin/sh")
        relaunch.arguments = ["-c", "sleep 1; /usr/bin/open \"$1\"", "sh", target.path]
        try? relaunch.run()
        NSApp.terminate(nil)
    }

    // MARK: Helpers

    /// Where a release download may come from (GitHub serves release files from its own storage hosts).
    nonisolated private static let allowedHosts = ["github.com", "githubusercontent.com"]
    /// A disk image is about 2 MB; anything far larger is refused.
    nonisolated private static let maxDownloadBytes = 200 * 1024 * 1024

    nonisolated private static func download(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.timeoutInterval = 60
        req.setValue("\(AppInfo.name)/\(AppInfo.version)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: req)
        // The signature is what makes a download trustworthy; these checks only refuse obvious nonsense early.
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty,
              data.count <= maxDownloadBytes,
              let host = http.url?.host?.lowercased(), allowedHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) })
        else { throw UpdateInstallError.download }
        return data
    }

    @discardableResult
    nonisolated private static func run(_ tool: String, _ args: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (-1, "") }
        let out = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: out, as: UTF8.self))
    }

    /// Single-quotes a string for /bin/sh.
    nonisolated private static func shQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Escapes a string for an AppleScript string literal.
    nonisolated private static func appleEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    private func showProgress(_ text: String) {
        if progress == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 92),
                                styleMask: [.titled], backing: .buffered, defer: false)
            panel.title = "ScreenPulse Update"
            panel.isReleasedWhenClosed = false
            panel.level = .floating
            panel.center()
            progress = panel
        }
        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.startAnimation(nil)
        let label = NSTextField(labelWithString: text)
        let stack = NSStackView(views: [spinner, label])
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 24, bottom: 24, right: 24)
        progress?.contentView = stack
        NSApp.activate(ignoringOtherApps: true)
        progress?.makeKeyAndOrderFront(nil)
    }

    private func hideProgress() {
        progress?.orderOut(nil)
    }
}
