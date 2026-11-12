// Unit tests for the hardware-independent logic in app/Sources/Core.
// Run: ./app/test.sh

import Foundation
import CryptoKit

var failures = 0
var checks = 0
func expect<T: Equatable>(_ got: T, _ want: T, _ name: String, line: Int = #line) {
    checks += 1
    if got != want { failures += 1; print("FAIL (line \(line)) \(name)\n   got:  \(got)\n   want: \(want)") }
}
func ons(_ s: Signal, unit: Double = 0.5) -> [Double] { SignalPattern.steps(for: s, unit: unit).filter { $0.on }.map { $0.seconds } }

// MARK: Focus mode parsing — a letter is signalled only for a clear multiple-choice answer
expect(AnswerParser.focusSignal("Answer: B"), .letters("B"), "plain letter")
expect(AnswerParser.focusSignal("answer: b."), .letters("B"), "lower case, trailing dot")
expect(AnswerParser.focusSignal("Answer: A, C"), .letters("A C"), "two letters")
expect(AnswerParser.focusSignal("Answer: A and D"), .letters("A D"), "letters joined by and")
expect(AnswerParser.focusSignal("Svar: D"), .letters("D"), "legacy Danish prefix")
expect(AnswerParser.focusSignal("  (B)  "), .letters("B"), "bare letter in brackets")
expect(AnswerParser.focusSignal("C."), .letters("C"), "bare letter with dot")
expect(AnswerParser.focusSignal("The capital of France is Paris."), .ready, "sentence is never blinked")
expect(AnswerParser.focusSignal("Answer: Paris is the capital."), .ready, "word after Answer: is not a letter")
expect(AnswerParser.focusSignal("Answer: A good choice is B"), .ready, "sentence starting with A")
expect(AnswerParser.focusSignal("There is no clear question in the image."), .ready, "no question")
expect(AnswerParser.focusSignal("I"), .letters("I"), "single letter reply")
expect(AnswerParser.focusSignal("Answer: B\n\nBecause Jupiter rotates fastest."), .letters("B"), "letter on the first line, explanation after")
expect(AnswerParser.focusSignal("It is not multiple choice.\nAnswer: B"), .ready, "letter must be on the first line")
expect(AnswerParser.focusSignal("   "), .error, "empty answer")

// MARK: Normal mode parsing
do {
    let r = AnswerParser.normalAnswer("Signal: B\n\nJupiter. A day lasts under ten hours.")
    expect(r.signal, .letters("B"), "normal: letter")
    expect(r.display, "Jupiter. A day lasts under ten hours.", "normal: signal line removed")
}
expect(AnswerParser.normalAnswer("Signal: none\n\nThis error means…").signal, .ready, "normal: none")
expect(AnswerParser.normalAnswer("Signal: yes\n\nYes, it is valid.").signal, .yes, "normal: yes")
expect(AnswerParser.normalAnswer("signal: No\n\nNo.").signal, .no, "normal: no, case-insensitive")
expect(AnswerParser.normalAnswer("Signal: 42\n\nThe total is 42.").signal, .number("42"), "normal: number")
expect(AnswerParser.normalAnswer("Signal: 12345\n\nBig.").signal, .ready, "normal: number too long")
expect(AnswerParser.normalAnswer("Signal: 3.5\n\nAbout 3.5.").signal, .ready, "normal: decimals are not signalled")
expect(AnswerParser.normalAnswer("Signal: A, C\n\nBoth.").signal, .letters("A C"), "normal: two letters")
expect(AnswerParser.normalAnswer("Signal: Paris\n\nParis.").signal, .ready, "normal: a word is not signalled")
do {
    let r = AnswerParser.normalAnswer("The model forgot the signal line.")
    expect(r.signal, .ready, "normal: missing signal line")
    expect(r.display, "The model forgot the signal line.", "normal: text kept when no signal line")
}
expect(AnswerParser.normalAnswer("").signal, .error, "normal: empty")

// MARK: Streaming filter
func stream(_ chunks: [String]) -> String {
    var f = SignalLineFilter(); var out = ""
    for c in chunks { out += f.feed(c) }
    return out + f.finish()
}
expect(stream(["Signal: B\n\nJupiter."]), "Jupiter.", "filter: one chunk")
expect(stream(["Sig", "nal: no", "ne\n", "\nAn error ", "message."]), "An error message.", "filter: split across chunks")
expect(stream(["No signal line here.\nSecond line."]), "No signal line here.\nSecond line.", "filter: passes other text")
expect(stream(["Hello", " world"]), "Hello world", "filter: no newline, not a signal")
expect(stream(["Signal: yes"]), "", "filter: only a signal line")
expect(stream(["Signature required\nmore"]), "Signature required\nmore", "filter: similar word is kept")

// MARK: Patterns
expect(ons(.letters("A")), [0.5], "A = 1 blink")
expect(ons(.letters("D")).count, 4, "D = 4 blinks")
expect(ons(.letters("A C")).count, 4, "A C = 1 + 3 blinks")
expect(SignalPattern.steps(for: .letters("A C"), unit: 0.5).contains(SignalStep(on: false, seconds: 3.0)), true, "word gap between letters")
expect(ons(.number("42")).count, 6, "42 = 4 + 2 blinks")
expect(ons(.number("0")).count, 10, "0 = ten blinks")
expect(ons(.yes), [1.5], "yes = one long")
expect(ons(.no), [1.5, 1.5], "no = two long")
expect(ons(.ready), [0.2, 0.2], "ready = two short")
expect(ons(.error), [0.08, 0.08, 0.08], "error = three micro")
expect(SignalPattern.blinkCount("z"), 26, "z")
expect(SignalPattern.blinkCount("å"), 29, "å")
expect(SignalPattern.blinkCount("1"), 0, "digit is not a letter")

// MARK: Mode settings
func freshDefaults() -> UserDefaults {
    let name = "screenpulse.tests.\(UUID().uuidString)"
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return d
}
do { // a fresh install
    let s = ModeSettings(freshDefaults())
    expect(s.mode, .normal, "new install starts in Normal Mode")
    expect(s.outputs(for: .normal), OutputOptions(window: true, capsLock: false, backlight: false), "normal defaults: window only")
    expect(s.outputs(for: .focus), OutputOptions(window: false, capsLock: true, backlight: true), "focus defaults: lights only")
}
do { // a chosen mode is remembered, and outputs are independent per mode
    let s = ModeSettings(freshDefaults())
    s.mode = .focus
    expect(s.mode, .focus, "a chosen mode is remembered")
    s.setOutputs(OutputOptions(window: false, capsLock: true, backlight: false), for: .normal)
    expect(s.outputs(for: .normal).window, false, "normal window can be hidden")
    expect(s.outputs(for: .focus), OutputOptions.defaults(for: .focus), "focus outputs unaffected by normal outputs")
}

// MARK: Prompts
expect(Prompts.system(for: .normal).contains("Signal: <value>"), true, "normal prompt asks for the signal line")
expect(Prompts.system(for: .focus).contains("\"Answer: B\""), true, "focus prompt keeps the letter format")
expect(Prompts.system(for: .focus).contains("do NOT pick a letter"), true, "focus prompt never forces a letter")
expect(Prompts.system(for: .normal) != Prompts.system(for: .focus), true, "prompts differ")

// MARK: Key check messages
expect(KeyCheck.result(status: 200), KeyCheckResult(ok: true, message: "The key works."), "key check: 200 works")
expect(KeyCheck.result(status: 400).ok, false, "key check: 400 = key rejected")
expect(KeyCheck.result(status: 403).message.contains("Copy it again"), true, "key check: 403 tells the user what to do")
expect(KeyCheck.result(status: 402).message.contains("billing"), true, "key check: 402 points to billing")
expect(KeyCheck.result(status: 429).ok, true, "key check: 429 means the key itself is valid")
expect(KeyCheck.result(status: 0).message.contains("internet"), true, "key check: no connection")
expect(KeyCheck.result(status: 503).message.contains("trouble"), true, "key check: Google outage")
expect(KeyCheck.result(status: 200, hasKey: false).ok, false, "key check: empty field")
expect(KeyCheck.cleaned("  \"AIzaSyABC123\"\n"), "AIzaSyABC123", "key check: quotes and spaces removed")
expect(KeyCheck.cleaned("AIza SyABC"), "AIza SyABC", "key check: inner characters untouched")

// MARK: Update check
func v(_ s: String) -> AppVersion { AppVersion(s)! }
expect(v("1.0.10") > v("1.0.9"), true, "update: 1.0.10 is newer than 1.0.9")
expect(v("v1.2.0") == v("1.2"), true, "update: v prefix and missing zeros are ignored")
expect(v("1.0.0") < v("1.0.1"), true, "update: patch version")
expect(v("2.0") > v("1.9.9"), true, "update: major version")
expect(v("1.4.0-beta.2") == v("1.4.0"), true, "update: suffix is ignored")
expect(AppVersion("") == nil, true, "update: empty version")
expect(AppVersion("abc") == nil, true, "update: not a version")
expect(AppVersion("1.2.3.4.5") == nil, true, "update: too many parts")
expect(AppVersion("1.-2") == nil, true, "update: negative part")
expect(UpdateCheck.isUpdate(remote: v("1.0.1"), over: v("1.0.1")), false, "update: same version is not an update")
expect(UpdateCheck.isUpdate(remote: v("1.0.0"), over: v("1.0.1")), false, "update: older release is not an update")
let trusted = "https://github.com/o/r/"
func rel(_ tag: String, url: String = "https://github.com/o/r/releases/tag/v1.0.2", draft: Bool = false, pre: Bool = false) -> Data {
    let obj: [String: Any] = ["tag_name": tag, "html_url": url, "draft": draft, "prerelease": pre]
    return try! JSONSerialization.data(withJSONObject: obj)
}
expect(UpdateCheck.parseRelease(rel("v1.0.2"), trustedPrefix: trusted)?.version.text, "1.0.2", "update: reads a release")
expect(UpdateCheck.parseRelease(rel("v1.0.2", pre: true), trustedPrefix: trusted) == nil, true, "update: pre-release ignored")
expect(UpdateCheck.parseRelease(rel("v1.0.2", draft: true), trustedPrefix: trusted) == nil, true, "update: draft ignored")
expect(UpdateCheck.parseRelease(rel("v1.0.2", url: "https://evil.example/x"), trustedPrefix: trusted) == nil, true, "update: foreign address refused")
expect(UpdateCheck.parseRelease(rel("v1.0.2", url: "http://github.com/o/r/releases"), trustedPrefix: trusted) == nil, true, "update: plain http refused")
expect(UpdateCheck.parseRelease(rel("nightly"), trustedPrefix: trusted) == nil, true, "update: tag without a version")
expect(UpdateCheck.parseRelease(Data("not json".utf8), trustedPrefix: trusted) == nil, true, "update: unreadable answer")
// Release assets: the disk image and its signature, only from the trusted repository
func relAssets(_ assets: [(String, String)]) -> Data {
    let obj: [String: Any] = ["tag_name": "v1.0.3", "html_url": "https://github.com/o/r/releases/tag/v1.0.3",
                              "assets": assets.map { ["name": $0.0, "browser_download_url": $0.1] }]
    return try! JSONSerialization.data(withJSONObject: obj)
}
let dl = "https://github.com/o/r/releases/download/v1.0.3/"
let both = UpdateCheck.parseRelease(relAssets([("ScreenPulse.dmg", dl + "ScreenPulse.dmg"), ("ScreenPulse.dmg.sig", dl + "ScreenPulse.dmg.sig")]), trustedPrefix: trusted)
expect(both?.canInstall, true, "update: release with disk image and signature can be installed")
expect(UpdateCheck.parseRelease(relAssets([("ScreenPulse.dmg", dl + "ScreenPulse.dmg")]), trustedPrefix: trusted)?.canInstall, false, "update: no signature, no install")
expect(UpdateCheck.parseRelease(relAssets([("ScreenPulse.dmg", "https://evil.example/ScreenPulse.dmg"), ("ScreenPulse.dmg.sig", dl + "ScreenPulse.dmg.sig")]), trustedPrefix: trusted)?.canInstall, false, "update: disk image from a foreign address is ignored")
expect(UpdateCheck.parseRelease(rel("v1.0.2"), trustedPrefix: trusted)?.canInstall, false, "update: release without assets is not installable")

// Signature check (Ed25519)
let signKey = Curve25519.Signing.PrivateKey()
let pub = signKey.publicKey.rawRepresentation.base64EncodedString()
let payload = Data("disk image bytes".utf8)
let sig = try! signKey.signature(for: payload).base64EncodedString()
expect(UpdateCheck.verifySignature(of: payload, signature: sig, publicKey: pub), true, "signature: valid")
expect(UpdateCheck.verifySignature(of: Data("changed".utf8), signature: sig, publicKey: pub), false, "signature: changed file is refused")
expect(UpdateCheck.verifySignature(of: payload, signature: sig, publicKey: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()), false, "signature: other key is refused")
expect(UpdateCheck.verifySignature(of: payload, signature: "not base64!", publicKey: pub), false, "signature: unreadable signature is refused")
expect(UpdateCheck.verifySignature(of: payload, signature: sig + "\n", publicKey: pub + "\n"), true, "signature: trailing newline is fine")

let now = Date(timeIntervalSince1970: 1_800_000_000)
expect(UpdateCheck.isDue(last: nil, now: now), true, "update: never checked is due")
expect(UpdateCheck.isDue(last: now.addingTimeInterval(-3600), now: now), false, "update: an hour ago is not due")
expect(UpdateCheck.isDue(last: now.addingTimeInterval(-90_000), now: now), true, "update: over a day ago is due")
expect(UpdateCheck.isDue(last: now.addingTimeInterval(600), now: now), true, "update: a clock set backwards does not block checks")

print(failures == 0 ? "OK: \(checks) checks passed" : "FAILED: \(failures) of \(checks) checks")
exit(failures == 0 ? 0 : 1)
