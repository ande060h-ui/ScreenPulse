# ScreenPulse user guide

## 1. Requirements

- A Mac with **macOS 13 Ventura or later** (Apple silicon or Intel).
- A **Gemini API key** from <https://aistudio.google.com/apikey>. Usage is billed by Google according to their pricing for your key.
- An internet connection.

## 2. Install

1. Open **ScreenPulse.dmg**, drag **ScreenPulse** onto **Applications**, and open it from there. (The first time, macOS says it could not verify the app. Click **Done** or **OK**, not **Move to Trash**. Then open System Settings → Privacy & Security, scroll down to Security, click **Open Anyway** and confirm with your password or Touch ID.) The Settings window opens and an icon (three rows of dots) appears in the menu bar. There is no Dock icon.
2. On the **Gemini** tab, paste your API key, press **Save**, then **Check key**. The key is stored in your macOS Keychain, and Check key tells you in plain words whether it works. If you do not have a key yet, press **How do I get a key?** for the step-by-step guide (also on the website under *Get started*).
3. Under **Permissions**, grant:
   - **Screen Recording** – needed to capture the screen. In System Settings this is listed under *Privacy & Security → Screen & System Audio Recording*.
   - **Input Monitoring** – needed to control the Caps Lock light (and for the optional ⌃⌥⌘-only trigger).
4. Quit ScreenPulse from the menu bar icon and open it again so the permissions take effect.

Recent macOS versions ask you to re-confirm Screen Recording periodically. That is a system behaviour.

## 3. Ask

1. Move the pointer to what you want help with.
2. Press **Control + Option + Command + Space** (⌃⌥⌘ Space).
3. The answer arrives on the outputs of the mode you are in. Press **⌃⌥⌘ 0** at any time to show or hide the answer window with the last answer.

Type in the window's field to ask a follow-up about the same screenshot. Esc hides the window. AI answers can be wrong; check the ones that matter.

## 4. Modes and outputs

Choose the mode in **Settings → Mode** or from the menu bar menu.

| | Normal Mode | Focus Mode |
| --- | --- | --- |
| For | Anything on screen: text, errors, charts, forms, questions | Multiple-choice questions |
| Answer | A direct answer followed by an explanation | Only the letter, e.g. `Answer: B` |
| Not multiple choice | – | One short sentence. No letter is signalled |
| Default outputs | Answer window | Caps Lock light + keyboard backlight, window hidden |

New installations start in Normal Mode. Each mode has its own three output switches:
**Answer window**, **Caps Lock light** and **Keyboard backlight**. Any combination is allowed.

### Light signals

| Signal | Meaning |
| --- | --- |
| Caps Lock light flickers quickly | The AI is thinking |
| Counted blinks | A letter (A = 1, B = 2, C = 3, D = 4 …) or a digit (3 = three blinks, 0 = ten) |
| Longer dark pause | Next letter or digit (`A, C` = 1 blink, pause, 3 blinks) |
| One long light | Yes |
| Two long lights | No |
| Two short blinks | An answer is ready but has no short form. Read it in the window (⌃⌥⌘ 0) |
| Three very quick blinks | Error (no network, missing key, missing permission). Press ⌃⌥⌘ 0 to read it |

In Focus Mode a letter is signalled only for a clear multiple-choice answer; everything else is "answer ready". In Normal Mode the AI marks a short form of its answer when there is one (a letter, a whole number up to 9999, yes or no); otherwise you get "answer ready".

After each signal, Caps Lock and the backlight brightness return to what they were. Set the **blink speed** in Settings and try every pattern with the test buttons or under *Keyboard Signals* in the menu. **Restore Keyboard Lights** resets the lights if a signal was interrupted.

Not every Mac or keyboard supports both lights. Settings shows what was detected. See [MACOS.md](MACOS.md).

## 5. Other settings

- **Model** – which Gemini model to use first. If it is unavailable, ScreenPulse falls back to the others.
- **Open ScreenPulse at login**.
- **Check for updates automatically** – on first start ScreenPulse asks whether it may do this. Once a day it asks GitHub whether a newer release exists (GitHub sees your IP address and the app name and version) and tells you if one does. It never installs anything itself: you download the new disk image and drag ScreenPulse onto Applications again. **Check for Updates…** in the menu does it on request.
- **Also trigger with ⌃⌥⌘ alone** – press and release the three modifier keys without another key. Requires Input Monitoring.
- **Knowledge folder** (menu bar → *Open Knowledge Folder*) – put `.md` files here and they are sent to the AI as background knowledge with every question.

## 6. Command line and focus-mode launcher

```bash
/Applications/ScreenPulse.app/Contents/MacOS/ScreenPulse --silent &
```

`--silent` starts this session in Focus Mode with the window hidden and without opening Settings (aliases: `--background`, `--no-overlay`, `-s`; or `SILENT_MODE=1`). Saved settings are not changed.

The `capsled` tool (built to `build/capsled`) drives the lights directly:

```bash
./build/capsled think 3    # thinking fade for 3 seconds
./build/capsled "b"        # two blinks
./build/capsled on         # lights on
./build/capsled off        # lights off
./build/capsled signal yes # also: no, ready, error, a number, letters
./build/capsled probe      # report what this Mac's keyboard lights support
```

## 7. Privacy

Nothing is captured until you trigger ScreenPulse. One image of the display under the pointer – everything visible on it – is sent directly to Google's Gemini API. ScreenPulse has no servers and collects no analytics. The answer window is a normal window and is visible in screen sharing and recordings. Hiding it is a workspace preference; ScreenPulse has no features for avoiding monitoring software.

## 8. Quit

Menu bar icon → **Quit ScreenPulse**.
