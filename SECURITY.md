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
