#!/usr/bin/env bash
# iOS Release IPA build (aligned with scripts/build_android_apk.ps1)
# Usage: ./scripts/build_ios_ipa.sh

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.flutter-io.cn}"
export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"

if [[ -x "$HOME/flutter-sdk/bin/flutter" ]]; then
  export PATH="$HOME/flutter-sdk/bin:$PATH"
fi

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK not found. Install Flutter or set PATH." >&2
  exit 1
fi

VERSION_FILE="$PROJECT_ROOT/VERSION"
if [[ ! -f "$VERSION_FILE" ]]; then
  echo "VERSION file not found" >&2
  exit 1
fi
MAIN_VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
if [[ ! "$MAIN_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "VERSION must be x.y.z, got: $MAIN_VERSION" >&2
  exit 1
fi

PUBSPEC="$PROJECT_ROOT/pubspec.yaml"
BUILD_NUMBER="$(grep -E '^version:' "$PUBSPEC" | sed -E 's/.*\+([0-9]+).*/\1/')"
if [[ -z "$BUILD_NUMBER" ]]; then
  BUILD_NUMBER=1
fi
sed -i '' -E "s/^version:.*/version: ${MAIN_VERSION}+${BUILD_NUMBER}/" "$PUBSPEC"

BUILD_DATE="$(date +%Y%m%d)"
OUTPUT_NAME="agent_dance-${MAIN_VERSION}-${BUILD_DATE}.ipa"
OUTPUT_PATH="$PROJECT_ROOT/$OUTPUT_NAME"

echo "Version: $MAIN_VERSION"
echo "Build date: $BUILD_DATE"
echo "Output: $OUTPUT_NAME"

ICON_SCRIPT="$PROJECT_ROOT/scripts/generate_app_icon.sh"
if [[ "${SKIP_ICON:-0}" != "1" && -x "$ICON_SCRIPT" && -f "$PROJECT_ROOT/icon.svg" ]]; then
  "$ICON_SCRIPT" || echo "图标生成跳过（不影响编译）"
fi

flutter pub get
dart run build_runner build --delete-conflicting-outputs

flutter build ipa --release --export-options-plist=ios/ExportOptions.plist

BUILT_IPA="$PROJECT_ROOT/build/ios/ipa/agent_dance.ipa"
if [[ ! -f "$BUILT_IPA" ]]; then
  BUILT_IPA="$(find "$PROJECT_ROOT/build/ios/ipa" -name '*.ipa' -print -quit)"
fi
if [[ -z "$BUILT_IPA" || ! -f "$BUILT_IPA" ]]; then
  echo "Built IPA not found under build/ios/ipa" >&2
  exit 1
fi

cp -f "$BUILT_IPA" "$OUTPUT_PATH"
echo "Done: $OUTPUT_PATH"
ls -lh "$OUTPUT_PATH"
