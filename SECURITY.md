# Security

## Reporting a problem
If you find a security problem in ScreenPulse, please do not post it publicly.
Use GitHub's private vulnerability reporting on this repository
(Security → Report a vulnerability). Describe what you found and how to reproduce it.
This is a spare-time project, so there is no guaranteed response time.

## Keys and secrets
- ScreenPulse stores your Gemini API key in the macOS Keychain.
- Never commit an API key. `.env` is git-ignored; use `.env.example` as the template.
- If you accidentally published a key, delete it in Google AI Studio and create a new one.

## How the app protects you
- **Updates are signed.** Every released disk image is signed with an Ed25519 key that only the release
  workflow can use. The app checks that signature against the public key built into it, and also checks
  the bundle ID, the version and the code signature of the app inside, before it replaces itself. An
  update is only installed after you click Install. Downloads are only accepted from GitHub.
- **Hardened runtime.** The app is built with macOS's hardened runtime, which stops other programs from
  injecting code into it.
- **Screenshots** are written to your private temporary folder, sent to Google's Gemini API over HTTPS
  and deleted straight away. Nothing is uploaded anywhere else.
- **Answers** are shown as plain text. They cannot run code or open links by themselves.
- **No servers, accounts or tracking.** The only addresses the app talks to are Google's Gemini API (with
  your own key) and, if you allow it, GitHub's release address for this project.
