# ScreenPulse

ScreenPulse is a macOS menu bar app that helps with whatever you point at on screen.
Press a shortcut, and it captures the screen under your pointer, asks a multimodal
AI model (Google Gemini) and answers in the mode and on the outputs you chose.

**Two modes**

- **Normal Mode** – a general screen assistant. Point at text, an error message, a chart, a
  form or a question and get an explanatory answer.
- **Focus Mode** – minimal and fast. For multiple-choice questions it returns only the letter.
  Anything that is not multiple choice gets one short sentence and is never turned into a letter.

**Three outputs, chosen per mode**

- **Answer window** – a small floating panel with a follow-up field and a copy button. Can be hidden.
- **Caps Lock light** and **keyboard backlight** – optical signals: counted blinks for a letter or
  a number, long lights for yes / no, "answer ready" and error patterns. Your own light settings
  are restored after every signal.

ScreenPulse is built for MacBooks only (macOS 13 Ventura or later, Apple silicon and Intel).

ScreenPulse is free and open source (Apache-2.0). It is a spare-time project made to learn
and to build something satisfying.

> **Responsible use.** ScreenPulse is not made for exams, graded tests, certifications or any
> other setting where AI assistance is not allowed, and it has no features for avoiding
> monitoring. Hiding the answer window is an ordinary display setting. Follow the rules of
> your school, employer and country. This is a request to users, not a licence condition.

## Repository layout

| Path | What it is |
| --- | --- |
| `app/` | The macOS app (Swift, AppKit + SwiftUI) and the `capsled` command-line tool |
| `website/` | The project website (Astro, static) |
| `benchmark/`, `tests/` | Accuracy benchmark and stress-test tooling |
| `scripts/` | Packaging, signing and notarization (optional) |
| `docs/` | User guide, macOS notes, distribution, brand, setup-guide screenshots |

## Install

Download `ScreenPulse.dmg` from the [latest release](https://github.com/ande060h-ui/ScreenPulse/releases/latest), open it and drag
ScreenPulse onto Applications. A build that is not signed by an Apple Developer ID needs one extra
step: see "Opening a build that is not signed" below. The first release is not published yet.

## Quick start (build it yourself)

Requirements: a Mac with macOS 13+, the Xcode Command Line Tools (`xcode-select --install`)
and a Gemini API key from <https://aistudio.google.com/apikey>.

```bash
./app/build.sh
```

```bash
open build/ScreenPulse.app
```

1. Paste your API key under **Settings → Gemini**. It is stored in the macOS Keychain.
2. Grant **Screen Recording** and **Input Monitoring** when asked (System Settings → Privacy & Security), then restart the app.
3. Point at something and press **⌃⌥⌘ Space**.

See [docs/USER_GUIDE.md](docs/USER_GUIDE.md) for everything else.

### Opening a build that is not signed
Apps you build yourself open without a warning. A downloaded, unsigned build is stopped by macOS
Gatekeeper. To open it anyway: try to open it once and click **Done** (or **OK**), not **Move to Trash**.
Then go to **System Settings → Privacy & Security**, scroll down to Security, click **Open Anyway** next to
the message about ScreenPulse and confirm with your password or Touch ID.

## Features

- Captures the whole display the pointer is on, with the pointer drawn in, so the model knows what is meant
- Normal Mode and Focus Mode with separate prompts and answer handling (`app/Sources/Core`)
- Streaming answers from Gemini with automatic fallback to other models
- Floating answer window above full-screen apps and on all Spaces; follow-up questions about the same screenshot
- Optical signals on the Caps Lock LED and the keyboard backlight, each switchable per mode; adjustable blink speed
- Background knowledge: Markdown files in `~/Library/Application Support/ScreenPulse/Knowledge` are given to the model
- Global shortcuts **⌃⌥⌘ Space** (ask) and **⌃⌥⌘ 0** (show/hide answer window); optional trigger on ⌃⌥⌘ alone
- Optional launch at login
- Optional update check that tells you when a new release is available (opt-in, asks on first start)
- `capsled` CLI for scripting the keyboard signals, and `capsled probe` to report what a Mac's lights support

Hardware limits are documented in [docs/MACOS.md](docs/MACOS.md). RGB keyboard lighting is **not** implemented.

## Website

```bash
cd website && npm install && npm run dev
```

See [website/README.md](website/README.md).

## Privacy and security

- There are no accounts, no telemetry, no analytics and no ScreenPulse servers. The project does not collect any data about you.
- **Update check (optional).** The first time you start the app it asks whether it may look for new versions. If you agree, it asks GitHub once a day for this project's latest release; GitHub then sees your IP address and the app name and version. Nothing is downloaded or installed by itself. You can turn it off in Settings.
- Nothing is captured until you press the shortcut. One PNG of the display under the pointer is then sent from your Mac directly to Google's Gemini API, using **your own** API key. Everything visible on that display is part of the image. Google's terms decide how it handles the data, and that can depend on whether your key has billing turned on.
- The temporary screenshot file is deleted after the request.
- The API key is stored in the macOS Keychain. Development builds and the benchmark can also read it from `.env`, which is git-ignored. Never commit keys. See [SECURITY.md](SECURITY.md).

## Status

The app is compiled, its bundle verified and the unit tests for the mode and signal logic
(`./app/test.sh`) are run on macOS in CI (`.github/workflows/macos-app.yml`).
Behaviour on real hardware (permissions, Caps Lock LED, backlight) must be verified on a Mac
before release; see the checklist in [docs/MACOS.md](docs/MACOS.md).

## Contributing and support

Issues and pull requests are welcome. This is a spare-time project: there is no support
obligation and no guaranteed response time. Keyboard-light support depends on the MacBook model,
so a `capsled probe` report from your Mac is very useful (see [docs/MACOS.md](docs/MACOS.md)).

## License

Licensed under the [Apache License, Version 2.0](LICENSE). The software is provided "as is",
without warranties of any kind.

The name "ScreenPulse", the logo and the icon are not covered by the licence (see [NOTICE](NOTICE)).
If you distribute a modified version, please give it a different name and logo.
