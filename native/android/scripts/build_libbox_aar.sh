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
SINGBOX_TAG="v1.10.7"                          # mobile libbox bridge source
GOMOBILE_MODULE="github.com/sagernet/gomobile"  # official SagerNet fork
GOMOBILE_VERSION="v0.1.4"                       # what sing-box v1.10.7 requires
GO_MINOR="1.21"                                 # see "Go version" below
ANDROID_NDK_REV="26.1.10909125"                 # NDK r26b
ANDROID_API="21"                                # minSdk

# ---------------------------------------------------------------------------
# Two footguns this script exists to prevent.
#
# 1. Go toolchain auto-resolution. From Go 1.21 onward, `go` will silently
#    download and switch to a NEWER toolchain when a module's `go` directive
#    demands it. That changes the compiled .so with no source change at all.
#    GOTOOLCHAIN=local disables that: we either build with the pinned Go or
#    fail loudly. This is a reproducibility control, not optional hardening.
#
# 2. 16 KB page alignment. Google requires 16 KB-aligned native libraries on
#    newer Android. A LOAD segment aligned to 0x1000 (4 KB) puts the app into
#    "16 KB backcompat mode" and draws a Play Store warning. NDK r26b does NOT
#    default to 16 KB (r27+ does), so CGO_LDFLAGS below is load-bearing. The
#    flag alone is not trusted: the result is measured with readelf at the end.
# ---------------------------------------------------------------------------

set -euo pipefail

# ------------------------------------------------------------------ environment
export PATH="$HOME/.local/go/bin:$HOME/go/bin:$PATH"
export GOTOOLCHAIN=local
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/${ANDROID_NDK_REV}"
export CGO_LDFLAGS="-Wl,-z,max-page-size=16384"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-/tmp/sing-box-build}"
SRC_DIR="$BUILD_DIR/sing-box"
OUT_AAR="$NATIVE_DIR/app/libs/libbox.aar"

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

# Go version, and why it is 1.21 and not 1.20.
# P3-T1 pinned Go 1.20 by reading sing-box v1.10.7's `go 1.20` directive in
# go.mod. That directive UNDERSTATES the real requirement: the file
# experimental/libbox/command_connections.go imports the standard-library
# `slices` package, which only entered GOROOT in Go 1.21. gomobile bind
# therefore cannot compile the libbox package with Go 1.20, whatever go.mod
# declares. Corrected to 1.21.x with human approval during P3-T3.
# Generalisable lesson: a `go` directive is a floor, not a build recipe.
case "$GO_VER" in
  go${GO_MINOR}.*) ;;
  *) die "expected Go ${GO_MINOR}.x per TOOLCHAIN_VERSIONS.md, got $GO_VER" ;;
esac

# gomobile's own version, read from the binary's build info rather than
# assumed from PATH.
GOMOBILE_VER="$(go version -m "$(command -v gomobile)" 2>/dev/null \
  | awk '/mod[[:space:]]+github.com\/sagernet\/gomobile/{print $3}')"
[ "$GOMOBILE_VER" = "$GOMOBILE_VERSION" ] \
  || die "expected gomobile ${GOMOBILE_VERSION} per TOOLCHAIN_VERSIONS.md, got '${GOMOBILE_VER:-unknown}'"

echo "== preflight OK =="
echo "   go        : $GO_VER"
echo "   gomobile  : $GOMOBILE_VER"
echo "   gobind    : $(command -v gobind)"
echo "   NDK       : $ANDROID_NDK_HOME"
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
# The shallow branch clone already carries the tag; this fetch is belt-and-braces
# and is allowed to fail (some networks drop the sideband packet on large fetches).
git -C "$SRC_DIR" fetch --tags --depth 1 origin "refs/tags/${SINGBOX_TAG}:refs/tags/${SINGBOX_TAG}" || true
git -C "$SRC_DIR" checkout -q "$SINGBOX_TAG"
git -C "$SRC_DIR" submodule update --init --recursive || true

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
gomobile bind \
  -v \
  -target=android \
  -androidapi="$ANDROID_API" \
  -javapkg=io.nekohasekai.libbox \
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

ARM64_SO="$SO_DIR/jni/arm64-v8a/libgojni.so"
[ -f "$ARM64_SO" ] || die "arm64-v8a/libgojni.so missing from AAR"

echo "== 16 KB alignment check (jni/arm64-v8a/libgojni.so) =="
ALIGN="$(readelf -l "$ARM64_SO" | grep -A 1 LOAD | grep -oE '0x[0-9a-f]+$' | sort -u | tr '\n' ' ')"
echo "   LOAD segment alignments: $ALIGN"
if echo "$ALIGN" | grep -q '0x4000'; then
  echo "   PASS: arm64-v8a LOAD segments are 16 KB aligned (0x4000)"
else
  echo "   FAIL: expected 0x4000, found: $ALIGN" >&2
  echo "   The CGO_LDFLAGS flag was not honoured on the final link. Do NOT ship this AAR." >&2
  exit 1
fi
rm -rf "$SO_DIR"

echo "== DONE: $OUT_AAR is built and 16 KB aligned =="
