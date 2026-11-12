# Brick VPN

Brick VPN is a high-performance, open-source (GPL-3.0-or-later), privacy-first
Android VPN client powered by the Sing-box (`v1.10.7`) core engine. Operating on
a strict "Bring Your Own Server" (BYOS) self-hosted architecture, Brick VPN
provides zero ads, zero trackers, and zero telemetry.

## Current Status: Android MVP Release (v1.0.0)

Phase 10 (Android MVP Release Prep) is complete. The application is packaged,
cryptographically signed with an official 4096-bit RSA release key, R8-minified,
and available for direct APK download or Play Store testing.

Supported protocols include:
- **VLESS** (with XTLS-Reality, Vision, WebSocket, gRPC, HTTP, HttpUpgrade)
- **VMess**
- **Trojan**
- **Shadowsocks** (AEAD & 2022 ciphers)
- **WireGuard**
- **AmneziaWG** (with junk-packet obfuscation)
- **Hysteria2**
- **TUIC v5**

---

## Download & Installation (Android MVP Direct APK & Release Verification)

Pre-compiled, signed Android release packages are published on GitHub Releases:
👉 **[Download Brick VPN on GitHub Releases](https://github.com/Ajorvpn/brick/releases)**

### Direct-Distribution APK Selection Guide

| Package Artifact | Target Architecture / Device Type | File Size | Recommended Use Case |
| :--- | :--- | :--- | :--- |
| `app-arm64-v8a-release.apk` | 64-bit ARM (`arm64-v8a`) | ~47 MB | **Recommended Default:** Modern Android smartphones & tablets (Android 7.0+). |
| `app-armeabi-v7a-release.apk` | 32-bit ARM (`armeabi-v7a`) | ~42 MB | Legacy 32-bit Android smartphones. |
| `app-x86_64-release.apk` | 64-bit x86 (`x86_64`) | ~51 MB | Android emulators, ChromeOS devices, Chromebooks. |
| `app-release.apk` | Universal (all ABIs bundled) | ~132 MB | Fallback if device ABI architecture is unknown. |
| `app-release.aab` | Android App Bundle | ~108 MB | Official Google Play Console distribution format. |

For detailed release notes, changelog, and known limitations, refer to:
- [GitHub Release v1.0.0 Notes](docs/release/github-release-v1.0.0.md)
- [Official Release Verification Guide](docs/verifying-releases.md)
- [Privacy Policy](docs/privacy-policy.md)

---

### Step-by-Step Installation Instructions

1. **Download the Appropriate APK:**
   Download `app-arm64-v8a-release.apk` (or matching ABI) and `SHA256SUMS.txt` from
   [GitHub Releases](https://github.com/Ajorvpn/brick/releases).

2. **Verify Cryptographic Integrity & Official Signature:**
   Verify the SHA-256 checksum and official APK Signature Scheme v2/v3 certificate:
   ```bash
   # Check SHA-256 hash against published SHA256SUMS.txt
   sha256sum -c SHA256SUMS.txt --ignore-missing

   # Verify APK signature and production certificate fingerprint
   apksigner verify --print-certs -v app-arm64-v8a-release.apk
   ```
   *Official Production Certificate SHA-256 Fingerprint:*
   `56:3D:AF:71:96:C5:65:AD:43:2B:F5:80:0E:2A:9E:AA:E0:A1:09:18:B0:48:9E:79:65:E6:3D:97:38:27:30:3B`

3. **Enable "Install unknown apps" (Sideloading on Android 8.0+):**
   - Open Android **Settings** > **Apps** (or **Apps & notifications**).
   - Tap **Special app access** > **Install unknown apps**.
   - Select the browser or file manager used to download the APK.
   - Toggle **"Allow from this source"** to ON.
   *(Alternatively, developers can sideload directly via `adb install -r app-arm64-v8a-release.apk`).*

4. **Launch and Grant VPN Permission:**
   - Launch **Brick VPN**.
   - Add a server profile via URI paste, optical QR scanning, or HTTPS subscription.
   - Tap **Connect** and approve the one-time system Android OS VPN connection dialog (`VpnService.prepare`).

---

## Development Setup

Required versions are recorded in
[AI_ROLES/TOOLCHAIN_VERSIONS.md](AI_ROLES/TOOLCHAIN_VERSIONS.md). The currently
verified Flutter version is 3.47.4.

From the repository root:

```bash
melos bootstrap
melos run format --no-select
melos run analyze --no-select
melos run test --no-select
```

To run the mobile application locally:

```bash
cd apps/mobile
flutter run
```

This command was verified against a connected Android device (build succeeded,
APK installed, and app launched). It requires a connected Android device or
running emulator; iOS and desktop targets are scoped to Phase 12+.

The repository also contains a CI/CD workflow at
[.github/workflows/ci.yml](.github/workflows/ci.yml). It triggers on push to
`master` (the repository's default branch) and on all pull requests.

## Troubleshooting

If the Android build fails with an error like

```text
Build was configured to prefer settings repositories over project repositories
but repository 'maven' was added by settings file 'settings.gradle.kts'
```

the cause is a machine-wide Gradle init script under `~/.gradle/init.d/` that
injects extra Maven repositories into every Gradle build on the machine. This
is a local environment issue, not a defect in this repository. Disable or
remove that init script (for example, rename it so it no longer ends in
`.gradle`) and rebuild. Do not "fix" this by deleting the `allprojects`
repositories block from `apps/mobile/android/build.gradle.kts`; that block is
part of the standard Flutter template and should stay.

## Project Documentation

- Brick VPN is licensed under the GNU GPL v3. See the full text in
	[LICENSE](LICENSE).
- [AI-assisted development governance](AI_ROLES/AGENTS.md)
- [Architecture](AI_ROLES/ARCHITECTURE.md)
- [Roadmap](AI_ROLES/ROADMAP.md)
- [Current project state](AI_ROLES/PROJECT_STATE.md)
- [Privacy Policy](docs/privacy-policy.md)
- [Release Verification Guide](docs/verifying-releases.md)

## Privacy

Brick VPN is designed with a strict zero-data-collection and zero-telemetry policy.
No remote telemetry service or analytics tracker is included in the project.
All configurations are encrypted at rest with hardware-backed Android Keystore
AES-256-GCM encryption, and diagnostics are scrubbed by a 3-surface redaction pipeline.

## Issues

Report bugs, documentation problems, and development questions through the
[GitHub issue tracker](https://github.com/Ajorvpn/brick/issues). Please do not
include server credentials, subscription URLs, tokens, or other sensitive
connection data in an issue.
