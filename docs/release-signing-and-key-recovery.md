# Android Release Signing Key Management, CI Secrets & Disaster Recovery

**Document Purpose:**
This document provides instructions for the human project owner and release managers on managing the Android release signing key for Brick VPN. It details keystore parameters, GitHub Actions CI secret configuration, offline backup custody, and the operational risks and consequences of key loss or compromise.

---

## 1. Release Keystore Generation & Cryptographic Parameters

The official Android release signing key was generated in accordance with current official Android security guidelines:

| Parameter | Specification | Purpose / Standard |
|:---|:---|:---|
| **Keystore Format** | `PKCS12` | Standard modern industry keystore format (replacing proprietary JKS). |
| **Key Algorithm** | `RSA` | Universal hardware and OS verification compatibility across all Android versions. |
| **Key Size** | `4096 bits` | High-security key length providing resistance well past 2030 (exceeding standard 2048-bit minimums). |
| **Signature Algorithm** | `SHA256withRSA` | Strong cryptographic digest algorithm accepted by Android APK Signature Schemes v2/v3. |
| **Validity Period** | `10,000 days` (~27.3 years) | Valid until **March 29, 2054**, comfortably exceeding Google Play's 25-year requirement (valid through October 22, 2033 minimum). |
| **Key Alias** | `brickvpn_release` | Canonical identifier for the primary application release signing key. |
| **Distinguished Name (DN)** | `CN=Brick VPN Release, OU=Security, O=Brick VPN Project, C=CA` | Official project identity metadata. |
| **Local Storage Path** | `/home/bellard/.brickvpn-keystore/brickvpn-release.jks` | Strictly outside repository working tree with `chmod 600` access permissions. |

### Public Certificate Fingerprints

These fingerprints are public and immutable. They are cross-referenced in [`docs/verifying-releases.md`](verifying-releases.md) for user and app store verification:

- **SHA-256 (colons):** `56:3D:AF:71:96:C5:65:AD:43:2B:F5:80:0E:2A:9E:AA:E0:A1:09:18:B0:48:9E:79:65:E6:3D:97:38:27:30:3B`
- **SHA-256 (lowercase hex, `apksigner` output):** `563daf7196c565ad432bf5800e2a9eaae0a10918b0489e7965e63d973827303b`
- **SHA-1:** `86:4A:75:50:9E:29:87:09:BD:8A:E8:A5:26:6C:71:EC:2A:4D:7B:B1`

---

## 2. GitHub Actions CI Secrets Provisioning Guide

To enable automated release signing during tagged release builds (`refs/tags/v*`), configure the following 4 encrypted repository secrets in GitHub:

### Navigation
Navigate to **GitHub Repository > Settings > Secrets and variables > Actions > New repository secret**.

### Secret Definitions

1. `ANDROID_KEYSTORE_BASE64`
   - **Value:** Base64-encoded string of the keystore file.
   - **Generation Command (run locally):**
     ```bash
     base64 -w 0 /home/bellard/.brickvpn-keystore/brickvpn-release.jks
     ```
   - Copy the entire output string (single continuous line) into the secret value.

2. `ANDROID_KEYSTORE_PASSWORD`
   - **Value:** The password protecting the keystore file (recorded in `/home/bellard/.brickvpn-keystore/keystore.env`).

3. `ANDROID_KEY_ALIAS`
   - **Value:** `brickvpn_release`

4. `ANDROID_KEY_PASSWORD`
   - **Value:** The password protecting the release key entry (recorded in `/home/bellard/.brickvpn-keystore/keystore.env`).

### CI Workflow Operation
When a release tag is pushed (e.g. `git tag v1.0.0 && git push origin v1.0.0`), `.github/workflows/ci.yml`:
1. Decodes `ANDROID_KEYSTORE_BASE64` into an ephemeral file located at `$RUNNER_TEMP/brickvpn-release.jks`.
2. Sets file permissions to `chmod 600`.
3. Exports environment variables (`BRICK_KEYSTORE_PATH`, `BRICK_KEYSTORE_PASSWORD`, `BRICK_KEY_ALIAS`, `BRICK_KEY_PASSWORD`).
4. Invokes `flutter build apk --release` and `flutter build appbundle --release`.
5. Verifies the APK signature with `apksigner verify --print-certs -v` and computes SHA-256 checksums.
6. Automatically and unconditionally wipes `$RUNNER_TEMP/brickvpn-release.jks` upon job completion via `always()`.

---

## 3. Key Backup & Offline Custody Protocol

> [!CAUTION]
> **Private Key Material Must NEVER Enter Source Control:**
> The keystore file (`*.jks`, `*.keystore`, `*.p12`) and credential environment files (`keystore.env`, `key.properties`) MUST NEVER be committed to Git. Both `.gitignore` and `apps/mobile/android/.gitignore` contain defensive rules blocking these patterns.

### Recommended Dual-Media Backup Protocol
The release manager must establish at least two separate, physically isolated backups:

1. **Primary Secure Vault (Password Manager / Secret Store):**
   - Attach `/home/bellard/.brickvpn-keystore/brickvpn-release.jks` as an encrypted binary attachment in an enterprise/personal password manager (e.g. 1Password, Bitwarden, or KeePassXC).
   - Store the associated passwords and alias as protected fields alongside the attachment.
2. **Cold Offline Hardware Storage (Encrypted USB / Hardware Storage):**
   - Copy the keystore directory to a dedicated, encrypted USB drive (e.g., LUKS-encrypted on Linux or BitLocker/FileVault):
     ```bash
     cp -r /home/bellard/.brickvpn-keystore /media/user/ENCRYPTED_USB/
     ```
   - Store this hardware medium in a physically secure location (e.g. fireproof safe or safety deposit box).

---

## 4. Operational Risks & Consequences of Key Loss or Compromise

### Consequence 1: Key Loss (Disaster Scenario)
Unlike web SSL/TLS certificates, Android code-signing certificates cannot simply be re-issued by a Certificate Authority if lost:

1. **Direct APK Distribution (GitHub Releases / Sideloading):**
   - The Android operating system enforces certificate pinning across application upgrades based on package name.
   - If an update APK is signed with a different key, Android package manager rejects installation with:
     ```text
     INSTALL_PARSE_FAILED_INCONSISTENT_CERTIFICATES: Update will not install because the signature is different
     ```
   - Existing users **CANNOT** upgrade in-place. Users would be forced to manually uninstall the existing app (permanently losing local server profiles, preferences, and encrypted keys) and install the newly-signed application from scratch.
2. **Google Play Store:**
   - If Play App Signing is utilized with an upload key, Google Play allows requesting an upload key reset through Google Play Console support (requiring human identity verification and introducing a 48-hour release delay).
   - If Play App Signing is NOT utilized or if the Google-managed app signing key is lost, the existing app listing is permanently dead. A new package name (e.g. `dev.brickvpn.mobile2`) must be registered, losing all user installations, reviews, and store ranking.

### Consequence 2: Key Compromise
If an adversary obtains the private release key:
- The adversary can construct a trojanized version of Brick VPN (e.g., disabling kill-switch protection, leaking user server credentials, or redirecting VPN traffic) and sign it with the legitimate key.
- Android OS will treat the trojanized APK as a legitimate update and install it silently over the user's authentic application without warning.
- **Mitigation upon compromise:** The project owner must immediately rotate the signing key, publish a security advisory across official channels, request key revocation/reset on Google Play, and instruct direct APK users to perform a clean reinstallation.

