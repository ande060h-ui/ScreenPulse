// ScreenPulse — screen-aware AI assistant for macOS.
//
// Point at something on screen and press ⌃⌥⌘ + Space. ScreenPulse captures the screen
// under the pointer, asks a multimodal AI model (Gemini) and presents the answer in a
// floating window and/or as an optical signal on the keyboard.

import AppKit

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.run()
