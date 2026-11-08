#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Brick VPN - Deterministic SHA-256 Checksum Generation and Verification Script
#
# Usage:
#   scripts/generate_and_verify_checksums.sh <target-directory-or-files>
#
# If no argument is provided, defaults to scanning for APKs in:
#   apps/mobile/build/app/outputs/flutter-apk/
#
# Generates a canonical SHA256SUMS.txt file where:
#   - Checksums are SHA-256 (64 hex characters)
#   - Filenames are basenames (no absolute or relative directory paths)
#   - Output lines are sorted alphabetically by filename for deterministic diffing
#   - Checksums are immediately self-verified using sha256sum -c

set -euo pipefail

TARGET_DIR=""
OUTPUT_FILE="SHA256SUMS.txt"
FILES=()

if [ $# -eq 0 ]; then
    DEFAULT_APK_DIR="apps/mobile/build/app/outputs/flutter-apk"
    if [ -d "$DEFAULT_APK_DIR" ]; then
        TARGET_DIR="$DEFAULT_APK_DIR"
    else
        TARGET_DIR="."
    fi
elif [ -d "$1" ]; then
    TARGET_DIR="$1"
elif [ -f "$1" ]; then
    TARGET_DIR="$(cd "$(dirname "$1")" && pwd)"
    for f in "$@"; do
        if [ ! -f "$f" ]; then
            echo "Error: Artifact file does not exist: $f" >&2
            exit 1
        fi
        f_dir="$(cd "$(dirname "$f")" && pwd)"
        if [ "$f_dir" != "$TARGET_DIR" ]; then
            echo "Error: All explicit files must reside in the same directory ($TARGET_DIR), but '$f' is in '$f_dir'" >&2
            exit 1
        fi
        FILES+=("$(basename "$f")")
    done
else
    echo "Error: Target directory or file does not exist: $1" >&2
    exit 1
fi

# Detect sha256 calculation command (GNU sha256sum or BSD shasum -a 256)
if command -v sha256sum >/dev/null 2>&1; then
    SHA256_CMD="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
    SHA256_CMD="shasum -a 256"
else
    echo "Error: Neither sha256sum nor shasum is available in PATH." >&2
    exit 1
fi

cd "$TARGET_DIR"

if [ ${#FILES[@]} -eq 0 ]; then
    # Discover relevant release artifact files (*.apk, *.aab, *.tar.gz, *.zip)
    # Exclude intermediate build files, debug builds (*-debug.apk, *-debug.aab), or existing checksum files
    while IFS= read -r file; do
        if [ -n "$file" ] && [ "$file" != "$OUTPUT_FILE" ]; then
            FILES+=("$file")
        fi
    done < <(find . -maxdepth 1 -type f \( -name "*.apk" -o -name "*.aab" -o -name "*.tar.gz" -o -name "*.zip" \) ! -name "*-debug.apk" ! -name "*-debug.aab" -exec basename {} \; | sort)
fi

if [ ${#FILES[@]} -eq 0 ]; then
    echo "Warning: No release artifacts (*.apk, *.aab, *.tar.gz, *.zip) found in $(pwd)" >&2
    exit 1
fi

echo "Generating $OUTPUT_FILE in $(pwd) for ${#FILES[@]} artifact(s)..."
rm -f "$OUTPUT_FILE"

# Generate sorted checksums with deterministic two-space delimiter
TMP_SUMS=$(mktemp)
for file in "${FILES[@]}"; do
    if [ ! -f "$file" ]; then
        echo "Error: Artifact file not found: $file" >&2
        rm -f "$TMP_SUMS"
        exit 1
    fi
    $SHA256_CMD -- "$file" >> "$TMP_SUMS"
done

sort -k2,2 "$TMP_SUMS" > "$OUTPUT_FILE"
rm -f "$TMP_SUMS"

echo "Generated $OUTPUT_FILE contents:"
cat "$OUTPUT_FILE"
echo ""

echo "Verifying $OUTPUT_FILE with $SHA256_CMD -c..."
if command -v sha256sum >/dev/null 2>&1; then
    sha256sum -c -- "$OUTPUT_FILE"
else
    shasum -a 256 -c -- "$OUTPUT_FILE"
fi

echo ""
echo "Integrity verification SUCCESSFUL: all checksums match."
