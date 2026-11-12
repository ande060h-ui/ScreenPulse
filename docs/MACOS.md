# macOS notes: compatibility, permissions and limits

ScreenPulse targets macOS only. This document records how each part works on macOS,
what is known to be limited, and what still has to be verified on real hardware.

## How each part works

| Part | Mechanism | Notes |
| --- | --- | --- |
| Screen capture | `/usr/sbin/screencapture -x -C -R …`, downscaled with `sips` | Needs **Screen Recording** (TCC). Uses the system tool rather than ScreenCaptureKit; `CGWindowListCreateImage` is avoided because it is deprecated. macOS 15+ re-prompts for this permission periodically. |
| Global shortcut | Carbon `RegisterEventHotKey` | No permission needed. |
| ⌃⌥⌘-only trigger | `NSEvent` global monitors | Optional, off by default. Needs **Input Monitoring**. |
| Caps Lock LED | IOKit HID (`IOHIDDeviceSetValue` on the Caps Lock LED element) | Needs **Input Monitoring**. Works for keyboards that expose a standard HID Caps Lock LED element to macOS. |
| Keyboard backlight | Private `CoreBrightness.framework` (`BrightnessSystemClient`, key `KeyboardBacklightBrightness`) | No public API exists. All calls are guarded and ignored when unavailable. May break with any macOS update. |
| API key | Keychain generic password | Stored only in the Keychain, never in a preferences file. |
| Launch at login | `SMAppService.mainApp` | macOS 13+. The app should be in `/Applications`. |
| Menu bar app | `LSUIElement` + accessory activation policy | No Dock icon. |

## Known limits

- **Hardware support is not uniform.** Whether the internal Caps Lock LED and the backlight can be driven depends on the MacBook model, keyboard controller and macOS version. Settings shows *Detected* / *Not found* for each light. The answer window does not depend on either.
- **MacBook Air/Pro without backlight control or with automatic brightness**: macOS may fight manual brightness changes when "Adjust keyboard brightness in low light" is on.
- **RGB lighting is not implemented.** MacBook keyboards have a single-colour backlight. Colour signals would need an external RGB keyboard and a vendor-specific integration (for example through each maker's SDK or a tool such as OpenRGB). No such integration exists in this repository.
- **Mac App Store**: not possible in the current design. The app uses a private framework, drives HID LEDs and runs `screencapture`, none of which pass App Sandbox / App Review. Distribution is direct download with Developer ID + notarization (see [DISTRIBUTION.md](DISTRIBUTION.md)).
- **Permissions and ad-hoc builds**: `build.sh` pins the designated requirement so permissions survive rebuilds. A build signed with a different identity is a different app to macOS and must be granted again.
- **Prompts**: the Focus Mode prompt was translated from Danish to English during the move to ScreenPulse and now tells the model not to pick a letter for content that is not multiple choice. The Normal Mode prompt is new. The stored benchmark results in `benchmark/results/` were produced with the Danish prompt (`benchmark/prompt-da.txt`); neither English prompt has been benchmarked yet.

## Finding out what a specific Mac supports

```bash
./build/capsled probe
```

The probe prints the Mac model, macOS version, Input Monitoring state, every keyboard macOS
exposes and whether it has a controllable Caps Lock LED (with the result code of an actual
write), whether the backlight can be read and written, and then blinks both lights so you can
see whether blinks at 0.5 s and 0.2 s stay separate or blur together. Collect these reports to
build the compatibility list.

| Mac | macOS | Caps Lock light | Backlight | Reported |
| --- | --- | --- | --- | --- |
| MacBook (model not recorded yet) | not recorded yet | Blinks | Blinks | 2026-11-12, project owner |

## Verification status

Verified in CI on a macOS runner (which has no keyboard lights and no screen permissions):

- The app and `capsled` compile for arm64 and x86_64; the bundle passes `codesign --verify`; `Info.plist` lints
- Unit tests (`./app/test.sh`): answer parsing for both modes, the streaming filter, every light pattern, the mode settings, the update check and the prompts
- `capsled --help` and `capsled probe` run without crashing

First test on a real MacBook (2026-11-12, by the project owner, model not recorded yet). Reported
working: building with `./app/build.sh`, `capsled probe` with both the Caps Lock light and the
backlight blinking, saving and checking the API key, granting the permissions, an explanatory answer
in Normal Mode, and a blinked letter in Focus Mode. The items below are ticked only where that test
covered them.

Not verifiable in CI — check on a real MacBook before release:

**General**
- [ ] First launch: Settings opens, menu bar icon visible in light and dark mode
- [x] Screen Recording prompt; capture on the built-in display
- [ ] Capture on an external display
- [x] Keychain save/load
- [ ] ⌃⌥⌘ Space and ⌃⌥⌘ 0 in other apps and above full-screen apps
- [ ] ⌃⌥⌘-only trigger with Input Monitoring granted; launch at login
- [x] Run `capsled probe` (both lights blink)
- [ ] Record the Mac model and macOS version from the probe in the table above

**Normal Mode**
- [x] Explanatory answer in the window
- [ ] Answers for an error message and a chart; the "Signal:" line never shows in the window
- [ ] Follow-up question about the same screenshot
- [ ] With lights on: letter, number, yes, no and "answer ready" each play the right pattern
- [ ] Window hidden: nothing appears; ⌃⌥⌘ 0 shows the answer

**Focus Mode**
- [x] Multiple choice → only `Answer: X`; lights blink the letter
- [ ] Several correct options → letters with a pause between
- [ ] Not multiple choice → short sentence, lights play "answer ready", never a letter
- [ ] Window on: the letter / sentence shows in the window
- [ ] Error (e.g. network off) → three quick blinks
- [ ] Re-run the benchmark with the English prompt (`node benchmark/run-benchmark.mjs hel app 2`)

**Lights**
- [ ] Caps Lock state and backlight brightness restored after every pattern
- [ ] Each output switch works on its own (Caps Lock only, backlight only)
