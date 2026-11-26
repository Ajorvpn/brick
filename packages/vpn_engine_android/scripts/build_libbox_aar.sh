#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# build_libbox_aar.sh — reproduce app/libs/libbox.aar from pinned sing-box source.
#
# This is a BUILD SCRIPT, not a library. It is idempotent: re-running it
# overwrites the AAR from scratch. It is also the ONLY place in the repo that
# knows how the AAR is made, so keep it boring and keep it asserted.
#
# ---------------------------------------------------------------------------
# Pinned inputs. These MUST agree with AI_ROLES/TOOLCHAIN_VERSIONS.md.
# ---------------------------------------------------------------------------
SINGBOX_TAG="v1.14.4"                          # mobile libbox bridge source
GOMOBILE_MODULE="github.com/sagernet/gomobile"  # official SagerNet fork
GOMOBILE_VERSION="v0.1.13"                      # upstream v1.14.4 Makefile lib_install pin
GO_MIN_MINOR="25"                               # v1.14.4 go.mod requires go >= 1.25.5
ANDROID_NDK_REV="28.2.13676358"                 # NDK r28c
ANDROID_API="24"                                # matches v1.14.4 main AAR & plugin minSdk

# ---------------------------------------------------------------------------
# Two footguns this script exists to prevent.
#
# 1. Go toolchain auto-resolution. From Go 1.21 onward, `go` will silently
#    download and switch to a NEWER toolchain when a module's `go` directive
#    demands it. That changes the compiled .so with no source change at all.
#    GOTOOLCHAIN=local disables that: we either build with the installed pinned
#    Go or fail loudly. This is a reproducibility control, not optional hardening.
#
# 2. 16 KB page alignment. Google requires 16 KB-aligned native libraries on
#    newer Android. A LOAD segment aligned to 0x1000 (4 KB) puts the app into
#    "16 KB backcompat mode" and draws a Play Store warning. NDK r27+ defaults
#    to 16 KB alignment, and CGO_LDFLAGS below enforces it explicitly as
#    defense-in-depth. The flag alone is not trusted: the result is measured
#    with readelf at the end on both arm64-v8a and x86_64.
# ---------------------------------------------------------------------------

set -euo pipefail

# ------------------------------------------------------------------ environment
export PATH="$HOME/go/bin:$HOME/.local/bin:$PATH"
export GOTOOLCHAIN=local
export GOMAXPROCS="${GOMAXPROCS:-2}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/${ANDROID_NDK_REV}"
export CGO_LDFLAGS="-Wl,-z,max-page-size=16384"

# P3-T11: this script moved from `native/android/scripts/` into the Flutter
# plugin package. `PLUGIN_DIR` is the package root and `NATIVE_DIR` is now the
# plugin's Android library module (previously `native/android`, where the AAR
# landed in `app/libs/` because it was an application module; it is now a
# library, so the AAR lands directly in `android/libs/`).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NATIVE_DIR="$PLUGIN_DIR/android"
BUILD_DIR="${BUILD_DIR:-$HOME/.cache/brick-sing-box-build}"
SRC_DIR="$BUILD_DIR/sing-box"
OUT_AAR="$NATIVE_DIR/libs/libbox.aar"
export TMPDIR="$BUILD_DIR/tmp"
mkdir -p "$TMPDIR"
trap 'rm -rf "$TMPDIR"' EXIT

die() { echo "ERROR: $*" >&2; exit 1; }

# -------------------------------------------------------------------- preflight
# Assert every pin before doing any expensive work, so a mismatch costs
# milliseconds instead of a ten-minute compile.
require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "$1 not found on PATH"
}

require_cmd go
require_cmd gomobile

# gobind ships in the same module as gomobile and MUST match its version.
# Do NOT suggest `gomobile init` here: that installs gobind@latest, which
# breaks the pin above and can pull a toolchain newer than the pinned Go.
command -v gobind >/dev/null 2>&1 || die \
"gobind not found on PATH.
  Install it MATCHED to gomobile:  go install ${GOMOBILE_MODULE}/cmd/gobind@${GOMOBILE_VERSION}"

[ -d "$ANDROID_NDK_HOME" ] || die "NDK r${ANDROID_NDK_REV} not found at $ANDROID_NDK_HOME"

GO_VER="$(go env GOVERSION)"
GO_MAJ_MIN="$(printf '%s\n' "$GO_VER" | sed -E 's/^go([0-9]+\.[0-9]+).*/\1/')"
GO_MAJOR="${GO_MAJ_MIN%%.*}"
GO_MINOR="${GO_MAJ_MIN#*.}"
if ! [ "$GO_MAJOR" -gt 1 ] 2>/dev/null && ! { [ "$GO_MAJOR" -eq 1 ] && [ "$GO_MINOR" -ge "$GO_MIN_MINOR" ]; } 2>/dev/null; then
  die "expected Go >= 1.${GO_MIN_MINOR} per TOOLCHAIN_VERSIONS.md, got $GO_VER"
fi

# gomobile's own version, read from the binary's build info rather than
# assumed from PATH.
GOMOBILE_VER="$(go version -m "$(command -v gomobile)" 2>/dev/null \
  | awk '/mod[[:space:]]+github.com\/sagernet\/gomobile/{print $3}')"
[ "$GOMOBILE_VER" = "$GOMOBILE_VERSION" ] \
  || die "expected gomobile ${GOMOBILE_VERSION} per TOOLCHAIN_VERSIONS.md, got '${GOMOBILE_VER:-unknown}'"

GOBIND_VER="$(go version -m "$(command -v gobind)" 2>/dev/null \
  | awk '/mod[[:space:]]+github.com\/sagernet\/gomobile/{print $3}')"
[ "$GOBIND_VER" = "$GOMOBILE_VERSION" ] \
  || die "expected gobind ${GOMOBILE_VERSION} per TOOLCHAIN_VERSIONS.md, got '${GOBIND_VER:-unknown}'"

echo "== preflight OK =="
echo "   go        : $GO_VER"
echo "   gomobile  : $GOMOBILE_VER ($(command -v gomobile))"
echo "   gobind    : $GOBIND_VER ($(command -v gobind))"
echo "   GOMAXPROCS: $GOMAXPROCS"
echo "   NDK       : $ANDROID_NDK_HOME"
echo "   BUILD_DIR : $BUILD_DIR"
echo "   sing-box  : $SINGBOX_TAG"
echo "   CGO_LDFLAGS: $CGO_LDFLAGS"

# ----------------------------------------------------------------- fetch source
mkdir -p "$BUILD_DIR"
if [ -d "$SRC_DIR/.git" ]; then
  echo "== reusing existing checkout at $SRC_DIR =="
else
  echo "== cloning sing-box =="
  rm -rf "$SRC_DIR"
  git clone --depth 1 --branch "$SINGBOX_TAG" https://github.com/SagerNet/sing-box "$SRC_DIR"
fi
# Fetch target tag cleanly so reusing an older cached checkout switches safely.
git -C "$SRC_DIR" fetch --tags --depth 1 origin "refs/tags/${SINGBOX_TAG}:refs/tags/${SINGBOX_TAG}"
git -C "$SRC_DIR" checkout -f "$SINGBOX_TAG"
# Submodules (`clients/android`, `clients/apple`) are NOT needed to bind
# `./experimental/libbox` -- that package does not import them. Fetching them
# cost ~20 minutes on 2026-10-03 and failed twice with
# `RPC failed; curl 56 GnuTLS recv error`, after which the step was tolerated
# by the `|| true` that has always been here anyway.
#
# So it is now OPT-IN: set FETCH_CLIENT_SUBMODULES=1 to restore the old
# behaviour. The default is to skip, which makes the build both faster and
# independent of those two large repositories.
if [ "${FETCH_CLIENT_SUBMODULES:-0}" = "1" ]; then
  git -C "$SRC_DIR" submodule update --init --recursive || true
else
  echo "== skipping client submodules (not required by experimental/libbox;"
  echo "   set FETCH_CLIENT_SUBMODULES=1 to fetch them) =="
fi

echo "== sing-box resolved commit: $(git -C "$SRC_DIR" rev-parse HEAD) =="

# Confirm the package we are binding is where P3-T1 verified it was, so a
# future refactor that moves it fails here rather than in gomobile.
[ -d "$SRC_DIR/experimental/libbox" ] \
  || die "expected $SRC_DIR/experimental/libbox (P3-T1 verified this path)"
grep -q '^package libbox$' "$SRC_DIR/experimental/libbox/platform.go" \
  || die "experimental/libbox/platform.go does not declare 'package libbox' (P3-T1 verified it does)"

# ----------------------------------------------------------------------- bind
mkdir -p "$(dirname "$OUT_AAR")"
rm -f "$OUT_AAR"

echo "== gomobile bind (this compiles Go+cgo for 4 Android ABIs; expect several minutes) =="
cd "$SRC_DIR"
# -target=android builds arm, arm64, 386 and amd64. arm64 is the one we verify
# against the 16 KB requirement. gomobile derives its CXXFLAGS from
# ANDROID_NDK_HOME; CGO_LDFLAGS above is what forces the page alignment.
#
# --- Build tags & linker flags (verified against sing-box v1.14.4) ----------
# Upstream `cmd/internal/build_libbox/main.go` + `cmd/internal/build_shared/flags.go`:
#   - `with_utls`: required for VLESS/Reality and uTLS client fingerprints.
#   - `with_quic`: required for Hysteria2 and TUIC outbounds.
#   - `with_wireguard`: required for WireGuard endpoints.
#   - `with_gvisor`: required for Android TUN gvisor/mixed stack.
#   - `badlinkname,tfogo_checklinkname0`: required for Go 1.23+ linkname usage.
# Deliberately excluded unused bloat: `with_tailscale`, `with_naive_outbound`,
# `with_openvpn`, `with_openconnect`, `with_usbip`, `with_clash_api`.
GOMOBILE_TAGS="with_gvisor,with_quic,with_wireguard,with_utls,badlinkname,tfogo_checklinkname0"
SINGBOX_VERSION="${SINGBOX_TAG#v}"
GOMOBILE_LDFLAGS="-X github.com/sagernet/sing-box/constant.Version=${SINGBOX_VERSION} -X runtime.godebugDefault=multipathtcp=0,tlssha1=1 -checklinkname=0 -s -w -buildid="

gomobile bind \
  -v \
  -target=android \
  -androidapi="$ANDROID_API" \
  -javapkg=io.nekohasekai.libbox \
  -trimpath \
  -buildvcs=false \
  -ldflags "$GOMOBILE_LDFLAGS" \
  -tags "$GOMOBILE_TAGS" \
  -o "$OUT_AAR" \
  ./experimental/libbox

# --------------------------------------------------------------------- verify
[ -s "$OUT_AAR" ] || die "libbox.aar was not produced or is empty"
echo "== produced: $OUT_AAR ($(du -h "$OUT_AAR" | cut -f1)) =="

# A gomobile-produced AAR names its native library `libgojni.so`, NOT
# `libbox.so`. Searching for the wrong name matches nothing and the check
# then passes for the wrong reason, so the file is asserted before it is read.
SO_DIR="$(mktemp -d)"
unzip -q -o "$OUT_AAR" 'jni/*/libgojni.so' -d "$SO_DIR"
echo "== ABIs built =="
ls -1 "$SO_DIR/jni" 2>/dev/null

for ABI in arm64-v8a x86_64; do
  ABI_SO="$SO_DIR/jni/${ABI}/libgojni.so"
  [ -f "$ABI_SO" ] || die "${ABI}/libgojni.so missing from AAR"
  echo "== 16 KB alignment check (jni/${ABI}/libgojni.so) =="
  ALIGN="$(readelf -l "$ABI_SO" | grep -A 1 LOAD | grep -oE '0x[0-9a-f]+$' | sort -u | tr '\n' ' ')"
  echo "   LOAD segment alignments: $ALIGN"
  if echo "$ALIGN" | grep -q '0x4000'; then
    echo "   PASS: ${ABI} LOAD segments are 16 KB aligned (0x4000)"
  else
    echo "   FAIL: expected 0x4000 on ${ABI}, found: $ALIGN" >&2
    echo "   The CGO_LDFLAGS flag was not honoured on the final link. Do NOT ship this AAR." >&2
    rm -rf "$SO_DIR"
    exit 1
  fi
done
rm -rf "$SO_DIR"

echo "== DONE: $OUT_AAR is built and 16 KB aligned (arm64-v8a + x86_64) =="
