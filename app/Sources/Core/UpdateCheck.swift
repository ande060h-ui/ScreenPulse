// Update check: version comparison and reading GitHub's "latest release" answer.
// Pure logic (Foundation only), unit-tested without any network.

import Foundation
import CryptoKit

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
    /// The disk image and its signature, when the release has both. Also under the project's repository.
    var dmgURL: URL? = nil
    var signatureURL: URL? = nil
    /// True when the app can download and install this release itself.
    var canInstall: Bool { dmgURL != nil && signatureURL != nil }
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
        var info = UpdateInfo(version: version, tag: tag, pageURL: url)
        for asset in (obj["assets"] as? [[String: Any]]) ?? [] {
            guard let name = asset["name"] as? String,
                  let link = asset["browser_download_url"] as? String,
                  link.hasPrefix(trustedPrefix),
                  let u = URL(string: link), u.scheme == "https" else { continue }
            if name == dmgName { info.dmgURL = u }
            if name == dmgName + ".sig" { info.signatureURL = u }
        }
        return info
    }

    /// The disk image a release must carry for the app to install it.
    static let dmgName = "ScreenPulse.dmg"

    /// Checks a downloaded file against its Ed25519 signature (base64, as written by
    /// app/Tools/sign-update.swift) and the public key built into the app (base64, raw 32 bytes).
    static func verifySignature(of data: Data, signature: String, publicKey: String) -> Bool {
        guard let keyData = Data(base64Encoded: publicKey.trimmingCharacters(in: .whitespacesAndNewlines)),
              let sigData = Data(base64Encoded: signature.trimmingCharacters(in: .whitespacesAndNewlines)),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else { return false }
        return key.isValidSignature(sigData, for: data)
    }

    static func isUpdate(remote: AppVersion, over local: AppVersion) -> Bool { remote > local }

    /// True when no check has run yet or the last one is older than `interval`.
    static func isDue(last: Date?, now: Date = Date()) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= interval || last > now
    }
}
