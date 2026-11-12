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

## 2. Verifying Release Checksums & Dual-Distribution Artifact Guide

Alongside each GitHub Release, a canonical `SHA256SUMS.txt` file is published containing the SHA-256 hashes of all official release artifacts sorted alphabetically.

### Release Artifact Guide (Which File Should I Download?)

| Artifact File | Architecture / Target | Description & Recommendation | Typical Size |
|---|---|---|---|
| `app-arm64-v8a-release.apk` | 64-bit ARM (`arm64-v8a`) | **Recommended Default:** For modern Android phones and tablets (~95%+ of devices). Smallest download and fastest runtime. | ~47 MB (45 MiB) |
| `app-armeabi-v7a-release.apk` | 32-bit ARM (`armeabi-v7a`) | For older 32-bit Android phones and legacy devices. | ~42 MB (40 MiB) |
| `app-x86_64-release.apk` | 64-bit Intel/AMD (`x86_64`) | For Android on x86_64 Chromebooks, Windows Subsystem for Android (WSA), and Android emulators. | ~51 MB (48 MiB) |
| `app-release.apk` | Universal Multi-ABI ("Fat" APK) | **Universal Fallback:** Contains native binaries for all 3 architectures (`arm64-v8a`, `armeabi-v7a`, `x86_64`). Use if you do not know your device's CPU architecture (~81 MB larger than split APKs). | ~132 MB (126 MiB) |
| `app-release.aab` | Android App Bundle | Official distribution bundle format for Google Play Store (contains all 3 ABIs before Play dynamic delivery splits into ~40–45 MB device-specific installs). | ~108 MB (103 MiB) |

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
shasum -a 256 -c --ignore-missing SHA256SUMS.txt
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

### Method A: Using Android SDK `apksigner` (Primary & Required for APK Signature Scheme v2/v3)

`apksigner` is the official Android SDK tool for verifying APK integrity and certificate fingerprints. It inspects modern APK Signature Schemes (v2 and v3) embedded in the APK Signing Block.

Run `apksigner verify` with verbose and certificate printing flags:

```bash
apksigner verify --print-certs -v app-release.apk
```

Expected output for Brick VPN release APKs:

```text
Verifies
Verified using v1 scheme (JAR signing): false
Verified using v2 scheme (APK Signature Scheme v2): true
Verified using v3 scheme (APK Signature Scheme v3): true
Verified using v4 scheme (APK Signature Scheme v4): false
Verified for SourceStamp: false
Number of signers: 1
Signer #1 certificate DN: CN=Brick VPN Release, OU=Security, O=Brick VPN Project, C=CA
Signer #1 certificate SHA-256 digest: 563daf7196c565ad432bf5800e2a9eaae0a10918b0489e7965e63d973827303b
Signer #1 key algorithm: RSA
Signer #1 key size (bits): 4096
```

Verify that:
1. `Verified using v2 scheme (APK Signature Scheme v2)` is `true`.
2. `Verified using v3 scheme (APK Signature Scheme v3)` is `true`.
3. The `Signer #1 certificate SHA-256 digest` matches `563daf7196c565ad432bf5800e2a9eaae0a10918b0489e7965e63d973827303b`.

### Method B: Using JDK `keytool` (Limitation Note on APK Signature Scheme v2/v3)

The JDK `keytool` utility inspects legacy JAR v1 signatures located inside the `META-INF/` directory:

```bash
keytool -printcert -jarfile app-release.apk
```

> [!NOTE]
> **APK Signature Scheme v2/v3 vs. Legacy JAR v1 Signatures:**
> Because Brick VPN targets `minSdk = 24` (Android 7.0+), modern Android Gradle Plugin releases sign APKs exclusively using APK Signature Scheme v2/v3 and omit legacy v1 JAR signing signatures from `META-INF/`. As a result, running `keytool -printcert -jarfile` on modern release APKs will report:
> ```text
> Not a signed jar file
> ```
> This is expected behavior for modern Android APKs. Use **Method A (`apksigner`)** above to verify the APK Signature Scheme v2/v3 cryptographic signatures and certificate fingerprints.

---

## 4. Official Production Signing Certificate (Established in Phase 10 — P10-T1)

As of Phase 10 (`P10-T1`), Brick VPN production releases are signed with the project's official 4096-bit RSA release signing key. The release keystore is stored securely outside source control and injected during GitHub Actions CI tag builds.

### Official Production Signing Certificate Fingerprints

```text
Certificate Signer #1:
Subject: CN=Brick VPN Release, OU=Security, O=Brick VPN Project, C=CA
Issuer:  CN=Brick VPN Release, OU=Security, O=Brick VPN Project, C=CA
Signature Algorithm: SHA256withRSA
Key Algorithm: 4096-bit RSA
Validity: 10,000 days (until 2054)

Certificate Fingerprints:
SHA-256 (with colons):
56:3D:AF:71:96:C5:65:AD:43:2B:F5:80:0E:2A:9E:AA:E0:A1:09:18:B0:48:9E:79:65:E6:3D:97:38:27:30:3B

SHA-256 (lowercase hex, apksigner format):
563daf7196c565ad432bf5800e2a9eaae0a10918b0489e7965e63d973827303b

SHA-1:
86:4A:75:50:9E:29:87:09:BD:8A:E8:A5:26:6C:71:EC:2A:4D:7B:B1
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

