// Plain-language results for "Check key". Pure logic, unit-tested without any network.

import Foundation

struct KeyCheckResult: Equatable {
    var ok: Bool
    var message: String
}

enum KeyCheck {
    /// Maps the HTTP status of a tiny test request to a message a non-technical user can act on.
    /// `status` 0 means the request never got an answer (no internet, blocked, timed out).
    static func result(status: Int, hasKey: Bool = true) -> KeyCheckResult {
        guard hasKey else {
            return .init(ok: false, message: "There is no key yet. Paste your key above, then try again.")
        }
        switch status {
        case 200:
            return .init(ok: true, message: "The key works.")
        case 400, 401, 403:
            return .init(ok: false, message: "Google did not accept this key. Copy it again from Google AI Studio, and make sure you copied the whole line with no spaces before or after it.")
        case 402:
            return .init(ok: false, message: "The key is valid, but its credits are used up. Add funds or raise your limit in Google's billing page.")
        case 429:
            return .init(ok: true, message: "The key is valid, but Google says there have been too many requests right now. Wait a minute and try again. Turning on billing gives you more room.")
        case 404:
            return .init(ok: false, message: "Google could not find the chosen model. Open Model below and pick another one.")
        case 0:
            return .init(ok: false, message: "ScreenPulse could not reach Google. Check your internet connection and try again.")
        case 500...599:
            return .init(ok: false, message: "Google's service is having trouble. Try again in a few minutes.")
        default:
            return .init(ok: false, message: "Something unexpected happened (code \(status)). Try again, and write to support if it keeps happening.")
        }
    }

    /// Removes the spaces, line breaks and quotation marks that are easy to copy by accident.
    static func cleaned(_ key: String) -> String {
        key.trimmingCharacters(in: CharacterSet(charactersIn: " \t\r\n\"'“”‘’"))
    }
}
