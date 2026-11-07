# Verifying Brick VPN Releases

This document provides step-by-step instructions for verifying the authenticity and integrity of Brick VPN application releases, especially when downloaded outside of official app stores (such as direct APK downloads from GitHub Releases).

---

## 1. Threat Model & Overview

As a censorship-circumvention and privacy tool, Brick VPN must provide users with transparent, tamper-evident verification mechanisms. Users operating in adversarial network environments frequently encounter:

- **Compromised mirrors and malicious third-party distributors** hosting backdoored APKs.
- **Active network-level MITM adversaries** attempting to inject modified binaries during transit.
- **Supply-chain tampering** targeting hosted distribution endpoints or CDNs.

To mitigate these threats, every official release provides:
1. Cryptographic **SHA-256 Checksums** (`SHA256SUMS.txt`) to confirm binary integrity.
2. Cryptographic **Android APK Signatures** (v2/v3) verified against the project's signing certificate fingerprint.

---

## 2. Verifying Release Checksums

Alongside each GitHub Release, a canonical `SHA256SUMS.txt` file is published containing the SHA-256 hashes of all official release artifacts sorted alphabetically.

### Linux

Download the APK and `SHA256SUMS.txt` into the same directory, then run:

```bash
sha256sum -c SHA256SUMS.txt --ignore-missing
```

Expected output:
```text
app-arm64-v8a-release.apk: OK
```

### macOS

Using macOS built-in `shasum`:

```bash
shasum -a 256 -c SHA256SUMS.txt
```

Alternatively, compute the hash manually and compare:
```bash
shasum -a 256 app-arm64-v8a-release.apk
```

### Windows (PowerShell)

Compute the SHA-256 hash using PowerShell:

```powershell
Get-FileHash .\app-arm64-v8a-release.apk -Algorithm SHA256
```

Or using Windows `certutil`:

```cmd
certutil -hashfile app-arm64-v8a-release.apk SHA256
```

Compare the resulting 64-character hexadecimal output against the hash listed in `SHA256SUMS.txt`.

---

## 3. Verifying Android APK Signing Certificate Fingerprint

Checksum verification proves the downloaded file matches the published artifact, but does not prove who built the artifact. Android APK signatures ensure that the binary was signed by the legitimate project release key and has not been repackaged.

### Method A: Using Android SDK `apksigner` (Recommended)

If you have the Android SDK Build-Tools installed:

```bash
apksigner verify --print-certs app-release.apk
```

### Method B: Using JDK `keytool`

If you have the Java Development Kit (JDK) installed:

```bash
keytool -printcert -jarfile app-release.apk
```

---

## 4. Current Signing Key Status & Phase 10 Transition

> [!IMPORTANT]
> **Pre-Release Milestone Notice (Phase 8):**
> At the current development milestone, the release build type in `apps/mobile/android/app/build.gradle.kts` uses debug signing keys (`signingConfigs.getByName("debug")`) for local and CI validation builds:
> ```kotlin
> buildTypes {
>     release {
>         // TODO: Add your own signing config for the release build.
>         // Signing with the debug keys for now, so `flutter run --release` works.
>         signingConfig = signingConfigs.getByName("debug")
>     }
> }
> ```
> Production release keystore generation, hardware-security-module / offline key custody, and GitHub Actions secret provisioning are explicitly scoped to **Phase 10 (Release Preparation)** per roadmap task `P8-T4` (Scope 1 & Criterion 1).
>
> Once Phase 10 is executed, the official production certificate details below will be populated.

### Official Production Signing Certificate (Target Placeholder for Phase 10)

```text
Certificate Signer #1:
Subject: CN=Brick VPN Release, OU=Security, O=Brick VPN Project
Issuer:  CN=Brick VPN Release, OU=Security, O=Brick VPN Project
Signature Algorithm: SHA256withRSA (or Ed25519)
SHA-256 Certificate Fingerprint:
[PENDING_PHASE10_PRODUCTION_KEY_FINGERPRINT]
```

---

## 5. Feasibility Investigation: Reproducible Builds

Reproducible builds allow independent parties to recompile the source code and achieve byte-for-byte identical binaries, guaranteeing that no unauthorized code or backdoor was introduced during compilation or CI.

### Technical Analysis of Brick VPN Stack

Brick VPN combines three distinct compilation toolchains:
1. **Dart / Flutter AOT Engine (`gen_snapshot`):** Compiles Dart code into machine code (`libapp.so`). Historically, Flutter AOT snapshots embed host-dependent absolute paths, timestamps, and memory layout non-determinism unless specialized flags are used.
2. **Go Engine (`libbox.aar` / gomobile):** Compiles the sing-box core into native shared libraries (`.so`) packaged within an Android Archive (`.aar`). Gomobile requires `-trimpath`, static GOROOT paths, and pinned CGO cross-compilers to avoid host path leakage.
3. **Android Gradle Plugin (AGP) / D8 / AAPT2:** Assembles DEX bytecode, compiled resources, and APK packaging. Zip archive entry timestamps and file ordering introduce non-determinism unless normalized with `SOURCE_DATE_EPOCH`.

### Industry Precedents

- **Signal Android:** Uses a dedicated Docker container (`build-environment`) with pinned toolchains, a deterministic build script, and APK zip normalization to allow users to reproduce official release APKs.
- **Tor Browser:** Uses `rBM` (Reproducible Build Manager) containerized builds with strict timestamp zeroing.
- **F-Droid:** Rebuilds open-source apps in controlled virtual machines using deterministic metadata recipes.

### Feasibility Assessment & Conclusion

Full byte-for-byte reproducible builds are **not yet achievable** at Phase 8 due to:
- gomobile AAR archive metadata embedding build timestamps.
- Flutter 3.47.4 AOT compilation lacking upstream default deterministic snapshot guarantees outside pinned Google container environments.
- Gradle/AAPT2 resource table ordering across different developer host platforms.

### Concrete Path to Reproducibility (Phase 10+)

To achieve reproducible builds in Phase 10+, the following steps are planned:
1. **Hermetic Docker Build Environment:** Pin base image (`ubuntu:24.04`), Flutter SDK (3.47.4), Dart SDK (3.13.3), Go toolchain (1.23.x), and Android NDK (r27b).
2. **Deterministic Build Flags:** Pass `-trimpath` and `-ldflags="-buildid="` to Go compilation, and set `SOURCE_DATE_EPOCH` to the git commit timestamp.
3. **APK Post-Processing:** Normalize APK zip entry timestamps and file ordering prior to APK Signature Scheme v2/v3 signing.
4. **Automated Reproduction CI Job:** Add a GitHub Actions workflow that independently rebuilds tagged releases in Docker and asserts `sha256sum(reproduced.apk) == sha256sum(release.apk)`.

