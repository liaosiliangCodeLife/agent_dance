#!/usr/bin/env bash
# 从 icon.svg 生成 Android / iOS 启动图标
# 用法: ./scripts/generate_app_icon.sh

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

SVG_PATH="$PROJECT_ROOT/icon.svg"
ASSETS_DIR="$PROJECT_ROOT/assets"
PNG_PATH="$ASSETS_DIR/icon.png"

if [[ ! -f "$SVG_PATH" ]]; then
  echo "icon.svg not found: $SVG_PATH" >&2
  exit 1
fi

mkdir -p "$ASSETS_DIR"

export PUB_HOSTED_URL="${PUB_HOSTED_URL:-https://pub.flutter-io.cn}"
export FLUTTER_STORAGE_BASE_URL="${FLUTTER_STORAGE_BASE_URL:-https://storage.flutter-io.cn}"

if [[ -x "$HOME/flutter-sdk/bin/flutter" ]]; then
  export PATH="$HOME/flutter-sdk/bin:$PATH"
fi

echo "Converting icon.svg -> assets/icon.png (1024x1024)..."
if command -v rsvg-convert >/dev/null 2>&1; then
  rsvg-convert -w 1024 -h 1024 "$SVG_PATH" -o "$PNG_PATH"
elif command -v npx >/dev/null 2>&1; then
  npx --yes @resvg/resvg-js-cli "$SVG_PATH" "$PNG_PATH" --fit-width 1024 --fit-height 1024
else
  echo "Need rsvg-convert or npx to convert icon.svg" >&2
  exit 1
fi

flutter pub get
dart run flutter_launcher_icons

echo "App icons generated from icon.svg"
