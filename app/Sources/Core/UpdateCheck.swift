// Update check: version comparison and reading GitHub's "latest release" answer.
// Pure logic (Foundation only), unit-tested without any network.

import Foundation

/// A dotted version such as 1.0.2. A leading "v" and any "-beta" / "+build" suffix are ignored.
struct AppVersion: Comparable, Equatable {
    let parts: [Int]

    init?(_ raw: String) {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        if let i = s.firstIndex(where: { $0 == "-" || $0 == "+" }) { s = String(s[..<i]) }
        let comps = s.split(separator: ".", omittingEmptySubsequences: false)
        guard !comps.isEmpty, comps.count <= 4 else { return nil }
        var out: [Int] = []
        for c in comps {
            guard let n = Int(c), n >= 0 else { return nil }
            out.append(n)
        }
        parts = out
    }

    private func padded(to n: Int) -> [Int] { parts + Array(repeating: 0, count: max(0, n - parts.count)) }

    static func == (a: AppVersion, b: AppVersion) -> Bool {
        let n = max(a.parts.count, b.parts.count)
        return a.padded(to: n) == b.padded(to: n)
    }

    static func < (a: AppVersion, b: AppVersion) -> Bool {
        let n = max(a.parts.count, b.parts.count)
        return a.padded(to: n).lexicographicallyPrecedes(b.padded(to: n))
    }

    var text: String { parts.map(String.init).joined(separator: ".") }
}

struct UpdateInfo: Equatable {
    let version: AppVersion
    let tag: String
    /// The release page to open. Always under the project's own repository.
    let pageURL: URL
}

enum UpdateCheck {
    /// How often an automatic check may run.
    static let interval: TimeInterval = 24 * 60 * 60

    /// Reads GitHub's `releases/latest` answer. Returns nil for drafts, pre-releases, an unreadable
    /// version, or a release page outside `trustedPrefix`, so the app never opens a foreign address.
    static func parseRelease(_ data: Data, trustedPrefix: String) -> UpdateInfo? {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              (obj["draft"] as? Bool) != true,
              (obj["prerelease"] as? Bool) != true,
              let tag = obj["tag_name"] as? String,
              let version = AppVersion(tag),
              let page = obj["html_url"] as? String,
              page.hasPrefix(trustedPrefix),
              let url = URL(string: page), url.scheme == "https" else { return nil }
        return UpdateInfo(version: version, tag: tag, pageURL: url)
    }

    static func isUpdate(remote: AppVersion, over local: AppVersion) -> Bool { remote > local }

    /// True when no check has run yet or the last one is older than `interval`.
    static func isDue(last: Date?, now: Date = Date()) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= interval || last > now
    }
}
