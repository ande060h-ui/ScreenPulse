// App-wide configuration: identifiers, preference keys, file locations, model choice and the system prompt.

import Foundation

enum AppInfo {
    static let name = "ScreenPulse"
    static let bundleID = "com.screenpulse.ScreenPulse"
    /// Where "How do I get a key?" opens: the setup guide on the website.
    static let setupGuideURL = "https://screenpulse.vercel.app/setup/"

    /// The project's public repository. The update check only ever talks to this one address.
    static let repoOwner = "ande060h-ui"
    static let repoName = "ScreenPulse"
    static let latestReleaseAPI = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"
    /// A release page must start with this, or the app will not open it.
    static let trustedReleasePrefix = "https://github.com/\(repoOwner)/\(repoName)/"
    /// The version of this build, from Info.plist.
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }
}

enum DefaultsKey {
    static let blinkSeconds = "BlinkSeconds"
    static let model = "Model"
    static let modifierOnlyHotkey = "ModifierOnlyHotkey"
    // Update check (opt-in; absent until the user has answered)
    static let updateChecks = "UpdateChecks"
    static let lastUpdateCheck = "LastUpdateCheck"
    static let notifiedUpdate = "NotifiedUpdateTag"
    static let skippedUpdate = "SkippedUpdateTag"
}

enum AppPaths {
    /// ~/Library/Application Support/ScreenPulse
    static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        return base.appendingPathComponent(AppInfo.name, isDirectory: true)
    }

    /// Markdown files placed here are given to the AI as background knowledge.
    static var knowledgeDir: URL { supportDir.appendingPathComponent("Knowledge", isDirectory: true) }

    /// Source checkout the app was built from. Only present in development builds
    /// (written to Info.plist by build.sh); release builds do not depend on it.
    static var projectDir: String? {
        guard let dir = Bundle.main.object(forInfoDictionaryKey: "SPProjectDir") as? String, !dir.isEmpty,
              FileManager.default.fileExists(atPath: dir) else { return nil }
        return dir
    }
}

/// Reads a value from `.env` in the project folder (development builds only).
func projectEnvValue(_ name: String) -> String? {
    guard let dir = AppPaths.projectDir,
          let text = try? String(contentsOfFile: dir + "/.env", encoding: .utf8) else { return nil }
    for line in text.split(separator: "\n") {
        let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        if parts.count == 2, parts[0] == name {
            let value = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            return value.isEmpty ? nil : value
        }
    }
    return nil
}

// MARK: - Models

let defaultModel = "gemini-3.8-flash"
let modelChoices = ["gemini-3.1-flash-lite", "gemini-3.5-flash", "gemini-3.8-flash", "gemini-flash-latest"]
let fallbackModels = ["gemini-3.5-flash", "gemini-3.1-flash-lite", "gemini-flash-latest"]

/// Main model: Settings → environment → .env → default.
func configuredModel() -> String {
    if let m = UserDefaults.standard.string(forKey: DefaultsKey.model), !m.isEmpty { return m }
    if let m = ProcessInfo.processInfo.environment["GEMINI_MODEL"], !m.isEmpty { return m }
    return projectEnvValue("GEMINI_MODEL") ?? defaultModel
}

// MARK: - Knowledge

/// Reads all `.md` files from the knowledge folders and hands them to the AI as background knowledge.
/// Folders: ~/Library/Application Support/ScreenPulse/Knowledge, plus `knowledge/` in the
/// project folder for development builds.
func loadKnowledge() -> String {
    var folders = [AppPaths.knowledgeDir.path]
    if let dir = AppPaths.projectDir { folders.append(dir + "/knowledge") }
    var out = ""
    for folder in folders {
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [])
            .filter { $0.hasSuffix(".md") }.sorted()
        for f in files {
            if let t = try? String(contentsOfFile: folder + "/" + f, encoding: .utf8) {
                out += "\n\n--- BACKGROUND KNOWLEDGE (" + f + ") ---\n" + t
            }
        }
    }
    return out.isEmpty ? "" : "\n\nUse the following knowledge as the reference when the question is about its subject. The format rules above still apply." + out
}
