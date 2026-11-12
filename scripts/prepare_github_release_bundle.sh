#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Brick VPN - Automated Release Bundle Staging & Verification Script (P10-T6)
#
# Verifies all 5 release artifacts, SHA256SUMS.txt integrity, 4096-bit RSA
# v2/v3 signatures, certificate fingerprint matching, and compiled manifest
# metadata before publication to GitHub Releases.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

# Ensure Android SDK tools (apksigner, apkanalyzer) are discovered
if [ -n "${ANDROID_HOME:-}" ]; then
  export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/build-tools/36.0.0:$PATH"
elif [ -d "/home/bellard/Android/Sdk" ]; then
  export ANDROID_HOME="/home/bellard/Android/Sdk"
  export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/build-tools/36.0.0:$PATH"
fi

APK_DIR="apps/mobile/build/app/outputs/flutter-apk"
AAB_DIR="apps/mobile/build/app/outputs/bundle/release"
RELEASE_NOTES="docs/release/github-release-v1.0.0.md"
EXPECTED_CERT_FINGERPRINT="563daf7196c565ad432bf5800e2a9eaae0a10918b0489e7965e63d973827303b"

echo "=== BRICK VPN RELEASE BUNDLE STAGING & VERIFICATION ==="

# Step 1: Verify presence and non-emptiness of all 5 release artifacts and docs
REQUIRED_ARTIFACTS=(
  "$APK_DIR/app-arm64-v8a-release.apk"
  "$APK_DIR/app-armeabi-v7a-release.apk"
  "$APK_DIR/app-x86_64-release.apk"
  "$APK_DIR/app-release.apk"
  "$APK_DIR/app-release.aab"
  "$APK_DIR/SHA256SUMS.txt"
  "$RELEASE_NOTES"
)

echo "[1/5] Verifying release artifact presence and sizes..."
for artifact in "${REQUIRED_ARTIFACTS[@]}"; do
  if [ ! -f "$artifact" ]; then
    echo "ERROR: Missing required artifact: $artifact" >&2
    exit 1
  fi
  size=$(stat -c%s "$artifact")
  if [ "$size" -le 0 ]; then
    echo "ERROR: Artifact is empty (0 bytes): $artifact" >&2
    exit 1
  fi
  printf "  [OK] %-60s (%'d bytes)\n" "$artifact" "$size"
done

# Step 2: Verify SHA256 checksums
echo "[2/5] Verifying SHA256SUMS.txt checksum integrity..."
(
  cd "$APK_DIR"
  sha256sum -c SHA256SUMS.txt
)

# Step 3: Verify APK and AAB signatures and certificate fingerprints
echo "[3/5] Verifying APK v2/v3 signatures and production certificate fingerprints..."
APKS=(
  "$APK_DIR/app-arm64-v8a-release.apk"
  "$APK_DIR/app-armeabi-v7a-release.apk"
  "$APK_DIR/app-x86_64-release.apk"
  "$APK_DIR/app-release.apk"
)

for apk in "${APKS[@]}"; do
  echo "  Verifying $apk..."
  cert_out=$(apksigner verify --print-certs -v "$apk")
  if ! echo "$cert_out" | grep -qi "Verified using v2 scheme (APK Signature Scheme v2): true"; then
    echo "ERROR: $apk was not signed with APK Signature Scheme v2!" >&2
    exit 1
  fi
  if ! echo "$cert_out" | grep -qi "Verified using v3 scheme (APK Signature Scheme v3): true"; then
    echo "ERROR: $apk was not signed with APK Signature Scheme v3!" >&2
    exit 1
  fi
  actual_fingerprint=$(echo "$cert_out" | grep -i "Signer #1 certificate SHA-256 digest:" | awk '{print $NF}' | tr -d ':' | tr '[:upper:]' '[:lower:]')
  if [ "$actual_fingerprint" != "$EXPECTED_CERT_FINGERPRINT" ]; then
    echo "ERROR: Signature certificate mismatch on $apk!" >&2
    echo "  Expected: $EXPECTED_CERT_FINGERPRINT" >&2
    echo "  Actual:   $actual_fingerprint" >&2
    exit 1
  fi
  echo "    -> Verified v2/v3 signing and certificate SHA-256: $actual_fingerprint"
done

echo "  Verifying AAB JAR signature on $APK_DIR/app-release.aab..."
aab_cert_out=$(keytool -printcert -jarfile "$APK_DIR/app-release.aab")
aab_fingerprint=$(echo "$aab_cert_out" | grep -i "SHA256:" | head -n 1 | awk '{print $2}' | tr -d ':' | tr '[:upper:]' '[:lower:]')
if [ "$aab_fingerprint" != "$EXPECTED_CERT_FINGERPRINT" ]; then
  echo "ERROR: AAB signature certificate mismatch!" >&2
  echo "  Expected: $EXPECTED_CERT_FINGERPRINT" >&2
  echo "  Actual:   $aab_fingerprint" >&2
  exit 1
fi
echo "    -> Verified AAB certificate SHA-256: $aab_fingerprint"

# Step 4: Verify compiled binary AndroidManifest.xml metadata
echo "[4/5] Verifying compiled binary AndroidManifest.xml metadata in app-arm64-v8a-release.apk..."
manifest_out=$(apkanalyzer manifest print "$APK_DIR/app-arm64-v8a-release.apk")

if ! echo "$manifest_out" | grep -q 'android:label="Brick VPN"'; then
  echo "ERROR: Compiled manifest does not contain android:label=\"Brick VPN\"!" >&2
  echo "$manifest_out" | grep 'android:label' >&2 || true
  exit 1
fi

if echo "$manifest_out" | grep -q 'android:label="mobile"'; then
  echo "ERROR: Compiled manifest still contains legacy android:label=\"mobile\"!" >&2
  exit 1
fi

if ! echo "$manifest_out" | grep -q 'android:versionName="1.0.0"'; then
  echo "ERROR: Compiled manifest does not contain android:versionName=\"1.0.0\"!" >&2
  exit 1
fi

if ! echo "$manifest_out" | grep -q 'android:versionCode="2001"'; then
  echo "ERROR: Compiled manifest does not contain android:versionCode=\"2001\"!" >&2
  exit 1
fi
echo "    -> Verified android:label=\"Brick VPN\", versionName=\"1.0.0\", versionCode=\"2001\""

# Step 5: Print commands for human release manager
echo "[5/5] Release bundle successfully verified! Ready for publication."
echo ""
echo "================================================================================"
echo "HUMAN ACTION: Commands to create Git tag and publish GitHub Release v1.0.0:"
echo "--------------------------------------------------------------------------------"
echo "git tag -a v1.0.0 -m \"Release v1.0.0 - Android MVP Release\""
echo "git push origin v1.0.0"
echo ""
echo "gh release create v1.0.0 \\"
echo "  --title \"Brick VPN v1.0.0 - Android MVP Release\" \\"
echo "  --notes-file \"$RELEASE_NOTES\" \\"
echo "  \"$APK_DIR/app-arm64-v8a-release.apk#app-arm64-v8a-release.apk (arm64-v8a, Recommended)\" \\"
echo "  \"$APK_DIR/app-armeabi-v7a-release.apk#app-armeabi-v7a-release.apk (armeabi-v7a)\" \\"
echo "  \"$APK_DIR/app-x86_64-release.apk#app-x86_64-release.apk (x86_64)\" \\"
echo "  \"$APK_DIR/app-release.apk#app-release.apk (Universal Multi-ABI)\" \\"
echo "  \"$APK_DIR/app-release.aab#app-release.aab (Android App Bundle)\" \\"
echo "  \"$APK_DIR/SHA256SUMS.txt#SHA256SUMS.txt\""
echo "================================================================================"

