#!/usr/bin/env bash
#
# Builds an installable Cairn and drops it in dist/.
#
#   ./tool/release.sh              arm64 only, which every tablet and phone from
#                                  about 2017 onwards runs. Smallest file.
#   ./tool/release.sh --universal  every architecture, for an older or unusual
#                                  device. Roughly half again the size.
#
# Analysis and tests run first: shipping an APK that does not compile cleanly
# onto the one device holding all your reading is not worth the seconds saved.

set -euo pipefail

cd "$(dirname "$0")/.."

FLUTTER="${FLUTTER:-flutter}"
TARGET=(--target-platform android-arm64)
SUFFIX="arm64"

if [[ "${1:-}" == "--universal" ]]; then
  TARGET=()
  SUFFIX="universal"
fi

echo "==> Checking"
"$FLUTTER" analyze
"$FLUTTER" test

echo "==> Building"
"$FLUTTER" build apk --release "${TARGET[@]}"

VERSION="$(grep '^version:' pubspec.yaml | awk '{print $2}' | cut -d+ -f1)"
STAMP="$(date +%Y%m%d)"
OUT="dist/cairn-${VERSION}-${STAMP}-${SUFFIX}.apk"

mkdir -p dist
cp build/app/outputs/flutter-apk/app-release.apk "$OUT"

echo
echo "Built $OUT ($(du -h "$OUT" | cut -f1))"
echo
echo "Install over USB:   adb install -r $OUT"
echo "Or copy to the tablet and open it from the file manager:"
echo "                    adb push $OUT /sdcard/Download/cairn.apk"
