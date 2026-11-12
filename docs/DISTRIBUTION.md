# Packaging, signing and updates

ScreenPulse is free and open source. Building it yourself needs no Apple account. Everything
below about signing and notarization is **optional** and only needed if you want to hand out a
downloadable build that opens on other Macs without a Gatekeeper warning.

## The installer (.dmg)

```bash
./scripts/make-dmg.sh
```

Builds `build/ScreenPulse.dmg`: a disk image whose window shows the app next to an Applications
shortcut ("drag ScreenPulse to Applications"). It uses [dmgbuild](https://github.com/dmgbuild/dmgbuild), which writes the
window layout directly and therefore also works on a build server. Layout: `app/dmg/settings.py`;
background: `app/Tools/make-dmg-background.swift`. CI builds and checks an unsigned image on every
app change (`.github/workflows/macos-app.yml`).

## Publishing a new version

1. Raise `version` in `package.json` (for example `1.0.1`) and commit.
2. Publish a release on GitHub (Releases → Draft a new release, new tag `v1.0.1`), or tag and push from Terminal: `git tag v1.0.1 && git push origin v1.0.1`.
3. The **Release** workflow (`.github/workflows/release.yml`) tests, builds `ScreenPulse.dmg`, and attaches it to the release together with a SHA-256 file (it creates the release if you only pushed a tag). It refuses a tag that does not match `package.json`.
4. The website's download button points at
   `https://github.com/<owner>/ScreenPulse/releases/latest/download/ScreenPulse.dmg`, a stable address that GitHub always serves from the newest release. Nothing on the website needs to change for a new version.

Releases of a private repository are not downloadable by the public: the repository has to be public first.
Before the first release, set `releaseAvailable: true` in `website/src/site.ts`.
The app has an opt-in update check (`app/Sources/ScreenPulse/Updater.swift`, logic in `app/Sources/Core/UpdateCheck.swift`):
it asks GitHub's `releases/latest` for this repository once a day and offers to open the release page. It
never installs anything itself, so people download the new disk image. Fully automatic installation (for
example with the Sparkle framework) is not built: it needs an EdDSA key pair, an appcast in every release and a
signed app, and is best done once a Developer ID exists.

## Signing so the installer opens without a warning

Without a signature, macOS stops the app on other people's Macs until they click **Open Anyway** in
System Settings → Privacy & Security. The only way around that is an Apple Developer ID certificate
(Apple Developer Program, about 99 USD a year) and notarization. The release workflow does both when
these are set in the repository (Settings → Secrets and variables → Actions):

| Name | Kind | What |
| --- | --- | --- |
| `MACOS_CERTIFICATE_P12_BASE64` | secret | The "Developer ID Application" certificate exported as `.p12`, then base64-encoded |
| `MACOS_CERTIFICATE_PASSWORD` | secret | Password of that `.p12` file |
| `SIGN_IDENTITY` | variable | For example `Developer ID Application: Your Name (TEAMID)` |
| `NOTARY_APPLE_ID` | secret | Your Apple ID email |
| `NOTARY_TEAM_ID` | secret | Your team ID |
| `NOTARY_PASSWORD` | secret | An app-specific password from appleid.apple.com |

Then set `signedBuilds: true` in `website/src/site.ts` to remove the "Open Anyway" note. The signing and
notarization path has not been run yet, because it needs the certificate. Test it with the first signed release.

## Build types

```bash
./app/build.sh             # development: reads .env and knowledge/ from this checkout
```

```bash
./app/build.sh --release   # self-contained, universal (arm64 + x86_64)
```

Output: `build/ScreenPulse.app` and `build/capsled`. The version comes from `package.json`;
set `BUILD_NUMBER` for `CFBundleVersion`.

## Not in place yet

- **Automatic updates.** The usual choice for directly distributed Mac apps is the Sparkle framework with a signed appcast. Not integrated.
- **Bundle identifier.** Currently `com.screenpulse.ScreenPulse` (in `app/build.sh` and `Config.swift`). Change it to a domain you own before the first public release; changing it later resets users' permissions and settings.
