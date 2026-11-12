# Google Play Console Submission Guide (Closed/Internal Testing Track)

**Document Reference:** `docs/release/play-store-submission-guide.md`  
**Target Milestone:** Phase 10 — Android MVP Release (`P10-T7`)  
**Package Identifier:** `dev.brickvpn.mobile`  
**Distribution Channel:** Google Play Store (Internal / Closed Testing Track)  
**Dual-Distribution Channel:** GitHub Releases (Direct APK)

---

## 1. Play App Signing vs. Self-Managed Signing Decision & Dual-Distribution

### The Architectural Problem: Dual-Channel Certificate Uniformity
Brick VPN is distributed simultaneously through two independent release channels:
1. **Direct GitHub Releases:** Pre-compiled standalone APKs (`app-arm64-v8a-release.apk`, etc.) signed with our official 4096-bit RSA release key.
2. **Google Play Store:** Android App Bundle (`app-release.aab`) distributed via Google Play Console.

On modern Google Play Console, **Play App Signing** is mandatory for all new applications published via Android App Bundles (AAB). Under standard Play App Signing, Google generates a cloud-managed app signing key that differs from the developer's local upload key. If Google signs Play Store APKs with an isolated Google-generated key while GitHub direct APKs are signed with the developer's key, **users attempting to switch between channels or sideload updates would encounter the fatal Android OS error:**
```text
INSTALL_PARSE_FAILED_INCONSISTENT_CERTIFICATES
```
This would force users to uninstall the app and wipe their local configurations and hardware Keystore keys.

### Selected Strategy: Play App Signing with Existing Keystore Upload (PEPK)
To ensure **100% cross-channel certificate uniformity** while gaining Play App Signing's cloud HSM security and upload-key reset benefits, we select:

- **Play Console Setting:** **"Export and upload a key from Java keystore"** using Google's Play Encrypt Private Key (PEPK) tool.
- **Signing Key Used:** Our existing official 4096-bit RSA production release key (`/home/bellard/.brickvpn-keystore/brickvpn-release.jks`, alias: `brickvpn_release`).
- **Production Certificate SHA-256 Fingerprint:**
  `563daf7196c565ad432bf5800e2a9eaae0a10918b0489e7965e63d973827303b`  
  (`56:3D:AF:71:96:C5:65:AD:43:2B:F5:80:0E:2A:9E:AA:E0:A1:09:18:B0:48:9E:79:65:E6:3D:97:38:27:30:3B`).
- **Upload Command (Run by Human Release Manager):**
  ```bash
  java -jar pepk.jar \
    --keystore=/home/bellard/.brickvpn-keystore/brickvpn-release.jks \
    --alias=brickvpn_release \
    --output=/tmp/brickvpn_encrypted_private_key.pepk \
    --encryptionkey=<GOOGLE_PLAY_PEPK_ENCRYPTION_KEY>
  ```
- **Result:** Google Play signs all app-bundle-delivered APKs with the exact same 4096-bit RSA certificate used for direct GitHub releases. Users can switch between GitHub Releases and Google Play seamlessly without signature mismatch errors.

---

## 2. Closed / Internal Testing Track Submission Package & Console Runbook

### Why Internal / Closed Testing First?
Brick VPN deliberately targets Google Play's **Internal Testing Track** (and subsequent **Closed Testing Track**) prior to any open production release:
1. **Review Risk Isolation:** VPN applications undergo rigorous automated and human review for `VpnService` declarations and background network routing. An initial submission to an internal/closed track allows resolving reviewer inquiries or documentation requests without risking a public-facing listing suspension.
2. **Deterministic Verification:** Closed testing validates Play Store download, Play Feature Delivery, dynamic ABI delivery, and licensing telemetry on end-user hardware in a controlled group before public exposure.

### Play Console Submission Manifest

| Play Console Section | Required Value / Artifact | In-Repository Reference | Verification Proof |
| :--- | :--- | :--- | :--- |
| **App Bundle (AAB)** | `app-release.aab` (`versionCode: 1 (AAB / universal base) & 2001 (arm64-v8a split APK)`, `versionName: 1.0.0`) | `apps/mobile/build/app/outputs/bundle/release/app-release.aab` | SHA-256: `5d289eb288226471c3b09f489c62dbc91149f717539a8ed12bf5c9ef6bf99e5d` |
| **App Title** | `Brick VPN` (9 chars <= 30) | `docs/release/store-listing.md` §1.1 | Verified by `store_listing_assets_test.dart` Test 3 |
| **Short Description** | `Open-source, ad-free VPN client supporting VLESS, Reality, WireGuard, and HY2.` (78 chars <= 80) | `docs/release/store-listing.md` §1.2 | Verified by `store_listing_assets_test.dart` Test 3 |
| **Full Description** | BYOS model, 8 protocols, Sing-box engine, Keystore encryption, 3-surface log redaction, GPLv3 (2411 chars <= 4000) | `docs/release/store-listing.md` §1.3 | Verified by `store_listing_assets_test.dart` Test 3 |
| **App Icon** | 512 x 512 px, 32-bit RGBA PNG, `< 1024 KB` | `docs/release/store-assets/icon-512x512.png` (3.8 KB) | Verified by `store_listing_assets_test.dart` Test 1 |
| **Feature Graphic** | 1024 x 500 px, 24-bit RGB PNG, `< 15 MB` | `docs/release/store-assets/feature-graphic-1024x500.png` (12 KB) | Verified by `store_listing_assets_test.dart` Test 1 |
| **Phone Screenshots** | 4 genuine Flutter UI screenshots (1080 x 1920 px, 32-bit RGBA PNG) | `docs/release/store-assets/screenshots/01..04.png` | Verified by `store_listing_assets_test.dart` Test 2 |
| **Privacy Policy URL** | `https://github.com/Ajorvpn/brick/blob/master/docs/privacy-policy.md` | `docs/privacy-policy.md` | Verified by `store_listing_assets_test.dart` Test 4 |
| **Data Safety Questionnaire** | Zero data collected; zero third-party tracking; zero account registration | `docs/release/play-store-vpn-compliance.md` §3 | Verified by `play_store_vpn_policy_compliance_test.dart` |
| **VpnService Declaration** | Core functionality: Encrypted proxy tunnel for censorship circumvention | `docs/release/play-store-vpn-compliance.md` §2 | Verified by `play_store_vpn_policy_compliance_test.dart` |
| **FGS Special Use** | Android 14+ `FOREGROUND_SERVICE_SPECIAL_USE` with `vpn` subtype | `docs/release/play-store-vpn-compliance.md` §2 Q4 | Verified by `play_store_vpn_policy_compliance_test.dart` |
| **Ads Declaration** | No ("My app does not contain ads") | `docs/release/play-store-vpn-compliance.md` §4 | Verified by `play_store_vpn_policy_compliance_test.dart` |
| **Target Audience** | 18 and older (or All ages / No special child-directed content) | `docs/release/store-listing.md` §2.2 | In-tree policy declaration |

---

## 3. Submission Status & Play Console Review-Iteration Playbook

### Current Status
- **Submission Package:** `100% Complete, Verified, and Staged In-Repository`. All assets, compliance texts, policies, and binaries are built, signed, and tested.
- **Play Console Upload & Review Status:** `Pending Human Play Console Account Upload & Google Review`. Performing web uploads and submitting the AAB to Google Play requires interactive developer account login and 2FA credentials held exclusively by the human release manager.

### Google Play Review Feedback & Rejection Response Playbook

#### Scenario A: Google Reviewer Requests a Video Demonstration of VpnService / FGS
- **Context:** Google Play review guidelines require VPN apps declaring `FOREGROUND_SERVICE_SPECIAL_USE` to provide a video demonstrating the user-visible connection flow.
- **Action:** Record or submit the 6-step video demonstration documented in `docs/release/play-store-vpn-compliance.md` Section 2 Question 4:
  1. Open Brick VPN to `HomeScreen` (disconnected state).
  2. Tap "Connect" on an active profile.
  3. Show the standard Android OS `VpnService.prepare()` permission dialog and tap "OK".
  4. Show the UI transition to "Connected", live duration counter, and throughput graph.
  5. Pull down the Android system notification shade to display the persistent notification:
     - Header: `"Brick VPN"`
     - Body: `"Tunnel active"`
  6. Return to the app and tap "Disconnect", demonstrating clean tunnel teardown and notification dismissal.

#### Scenario B: Google Reviewer Inquires About App Access / Login Credentials
- **Context:** Play Console requires developers to declare if parts of the app are restricted by login credentials (**App Access** section).
- **Action:** In Play Console **App Content > App Access**, select **"All or some functionality is restricted"** and add testing instructions:
  - *Title:* `"BYOS Server Profile Import Instructions"`
  - *Instructions:* `"Brick VPN does not require a user account, login, or password. It is a Bring Your Own Server (BYOS) client. To test VPN connectivity, reviewers can import the following test server URI via the 'Add Server' screen: vless://test-uuid@127.0.0.1:443?security=reality&sni=example.com&pbk=1234567890abcdef&sid=1234#ReviewerTestServer. Alternatively, test with any public VLESS or WireGuard endpoint."*

#### Scenario C: Google Reviewer Requests Details on Encryption or Traffic Inspection
- **Context:** Play Store VPN policy mandates that all traffic routed through `VpnService` must be encrypted from the device to the target server.
- **Action:** Point the reviewer to `docs/release/play-store-vpn-compliance.md` Section 1:
  - Explain that the Sing-box core implements authenticated encryption across all protocols: TLS 1.3 / Reality AEAD for VLESS/VMess/Trojan, Noise protocol for WireGuard/AmneziaWG, and QUIC TLS 1.3 for Hysteria2 and TUIC. Cleartext unencrypted proxy routing is architecturally blocked by Invariant 29.

---

## 4. Google MASA (Mobile App Security Assessment) Badge Status

### Policy & Evaluation
The **Mobile App Security Assessment (MASA)** program, established by the App Defense Alliance (ADA) and Google Play, allows applications to earn an **"Independent Security Review"** badge in their Google Play Store Data Safety section, verifying compliance with the OWASP Mobile Application Security Verification Standard (MASVS) Level 1.

### Decision: Explicitly Deferred for MVP Release
Pursuing the MASA "Verified" badge is **deliberately deferred and out-of-scope for the Phase 10 Android MVP release**.

### Objective Threshold Requirements for Future Eligibility
The project will evaluate MASA certification once the following standard requirements are met:
1. **Install Threshold:** Minimum **10,000+ active installs** on Google Play.
2. **Review Threshold:** Minimum **250+ user reviews** on Google Play.
3. **Maturity Period:** Minimum **90+ days** of public availability on Google Play.
4. **Third-Party Lab Assessment:** Engagement with an authorized App Defense Alliance third-party security lab (e.g., Bishop Fox, DEKRA, NCC Group) for an independent code and binary audit (annual cost approximately $3,000–$6,000 USD).

For the initial MVP release, Brick VPN provides complete public transparency through 100% open-source licensing ([GPL-3.0-or-later](https://github.com/Ajorvpn/brick/blob/master/LICENSE)), reproducible release checksums (`SHA256SUMS.txt`), and hardware-backed Keystore encryption.

