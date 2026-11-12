// Signals: what an answer means on the keyboard lights, independent of any hardware.
//
// This file is pure logic (Foundation only) so it can be unit-tested without a Mac keyboard:
// parsing AI answers into a Signal, and turning a Signal into a timeline of light steps.

import Foundation

/// A piece of information that can be shown on the keyboard lights.
enum Signal: Equatable {
    /// One or more letters, e.g. "B" or "A C". Each letter is blinked as its position in the alphabet.
    case letters(String)
    /// A whole number, e.g. "42". Each digit is blinked as a count (0 = ten blinks).
    case number(String)
    case yes
    case no
    /// An answer is ready but has no short form. Read it in the answer window.
    case ready
    case error

    /// Short text for status lines and logs.
    var label: String {
        switch self {
        case .letters(let s): return s
        case .number(let s): return s
        case .yes: return "yes"
        case .no: return "no"
        case .ready: return "answer ready"
        case .error: return "error"
        }
    }
}

/// One step of a light pattern: lights on or off for a duration.
struct SignalStep: Equatable {
    var on: Bool
    var seconds: Double
}

enum SignalPattern {
    /// Blink count for a letter: a = 1 … z = 26, æ = 27, ø = 28, å = 29. 0 for anything else.
    static func blinkCount(_ c: Character) -> Int {
        guard let a = c.lowercased().unicodeScalars.first else { return 0 }
        switch a {
        case "a"..."z": return Int(a.value) - 96
        case "æ": return 27
        case "ø": return 28
        case "å": return 29
        default: return 0
        }
    }

    /// The light timeline for a signal. `unit` is the blink time in seconds (Settings → Blink speed).
    ///
    /// - letters / digits: `count` blinks of `unit` on, `unit` off; 3.5 × unit between symbols; 6 × unit for a space
    /// - yes: one long light (3 × unit).  no: two long lights
    /// - ready: two short blinks (0.2 s), clearly shorter than a counted blink
    /// - error: three micro-blinks (0.08 s)
    static func steps(for signal: Signal, unit: Double) -> [SignalStep] {
        var out: [SignalStep] = []
        func blink(_ n: Int, on: Double, off: Double) {
            for _ in 0..<n { out.append(.init(on: true, seconds: on)); out.append(.init(on: false, seconds: off)) }
        }
        switch signal {
        case .letters(let text):
            for c in text {
                if c == " " || c == "\n" { out.append(.init(on: false, seconds: unit * 6)); continue }
                let n = blinkCount(c)
                guard n > 0 else { continue }
                blink(n, on: unit, off: unit)
                out.append(.init(on: false, seconds: unit * 3.5))
            }
        case .number(let digits):
            for c in digits {
                guard let d = c.wholeNumberValue else { continue }
                blink(d == 0 ? 10 : d, on: unit, off: unit)
                out.append(.init(on: false, seconds: unit * 3.5))
            }
        case .yes:
            blink(1, on: unit * 3, off: unit)
        case .no:
            blink(2, on: unit * 3, off: unit)
        case .ready:
            blink(2, on: 0.2, off: 0.2)
        case .error:
            blink(3, on: 0.08, off: 0.08)
        }
        return out
    }
}

// MARK: - Parsing answers

enum AnswerParser {
    private static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (0..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: text).map { String(text[$0]) } ?? ""
        }
    }

    /// "A, c" → "A C". Nil unless the text is only single letters separated by commas / "and" / spaces.
    private static func letterList(_ text: String, maxLetters: Int) -> String? {
        let parts = text.uppercased()
            .replacingOccurrences(of: " AND ", with: ",")
            .split(whereSeparator: { $0 == "," || $0 == " " })
            .map(String.init)
        guard !parts.isEmpty, parts.count <= maxLetters,
              parts.allSatisfy({ $0.count == 1 && ("A"..."Z").contains($0) }) else { return nil }
        return parts.joined(separator: " ")
    }

    /// Focus mode. Returns `.letters` only when the answer is unambiguously a multiple-choice
    /// result ("Answer: B", "Answer: A, C", "B", "(B)"). Anything else — a short sentence,
    /// "no clear question" — is `.ready`: a letter is never invented.
    /// The legacy Danish prefix "Svar:" is still recognised.
    static func focusSignal(_ raw: String) -> Signal {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .error }
        // The letter form is read from the first line, so "Answer: B" stays B even when the
        // user asked for an explanation and more text follows.
        let firstLine = text.components(separatedBy: "\n")[0].trimmingCharacters(in: .whitespaces)
        if let m = firstMatch(#"^(?:answer|svar):\s*([A-Za-z](?:\s*(?:,|\band\b)?\s*[A-Za-z]\b)*)\s*\.?$"#, in: firstLine),
           let letters = letterList(m[1], maxLetters: 8) {
            return .letters(letters)
        }
        if let m = firstMatch(#"^[\(\[]?([A-Za-z])[\.\)\]:]?$"#, in: text) {
            return .letters(m[1].uppercased())
        }
        return .ready
    }

    /// Normal mode. The model is asked to start with a line "Signal: <value>".
    /// Returns the text to display (without that line) and the signal it describes.
    static func normalAnswer(_ raw: String) -> (display: String, signal: Signal) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return ("", .error) }
        var lines = text.components(separatedBy: "\n")
        guard let m = firstMatch(#"^\s*signal:\s*(.*?)\s*$"#, in: lines[0]) else { return (text, .ready) }
        lines.removeFirst()
        let display = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return (display, signalValue(m[1]))
    }

    /// The value after "Signal:". Unknown or over-long values become `.ready`.
    static func signalValue(_ value: String) -> Signal {
        let v = value.trimmingCharacters(in: CharacterSet(charactersIn: " \t\"'`.*"))
        switch v.lowercased() {
        case "yes", "true": return .yes
        case "no", "false": return .no
        case "", "none", "-", "n/a": return .ready
        default: break
        }
        if v.count <= 4, v.allSatisfy({ $0.isASCII && $0.isNumber }) { return .number(v) }
        if let letters = letterList(v, maxLetters: 4) { return .letters(letters) }
        return .ready
    }
}

/// Removes a leading "Signal: …" line from a streamed answer, so it never flashes in the window.
/// Feed chunks in order; each call returns the text that may be displayed.
struct SignalLineFilter {
    private var pending = ""
    private var decided = false
    private var stripLeadingNewlines = false

    mutating func feed(_ chunk: String) -> String {
        if decided { return afterSignal(chunk) }
        pending += chunk
        let trimmed = String(pending.drop(while: { $0 == " " || $0 == "\n" }))
        if let nl = trimmed.firstIndex(of: "\n") {
            decided = true
            if trimmed.lowercased().hasPrefix("signal:") {
                stripLeadingNewlines = true
                return afterSignal(String(trimmed[trimmed.index(after: nl)...]))
            }
            return trimmed
        }
        // No newline yet: keep holding while it can still be a signal line.
        let head = trimmed.lowercased()
        let couldBeSignal = "signal:".hasPrefix(head) || (head.hasPrefix("signal:") && head.count <= 60)
        if couldBeSignal { return "" }
        decided = true
        return trimmed
    }

    /// Drops the blank lines that follow the signal line, even when they arrive in a later chunk.
    private mutating func afterSignal(_ text: String) -> String {
        guard stripLeadingNewlines else { return text }
        let rest = String(text.drop(while: { $0 == "\n" || $0 == "\r" }))
        if !rest.isEmpty { stripLeadingNewlines = false }
        return rest
    }

    /// Call at the end of the stream: returns anything still held back.
    mutating func finish() -> String {
        guard !decided else { return "" }
        decided = true
        let trimmed = pending.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.lowercased().hasPrefix("signal:") ? "" : trimmed
    }
}
