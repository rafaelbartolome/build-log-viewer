#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="${1:-"$ROOT_DIR/.build/BuildLogViewer.app"}"

cd "$ROOT_DIR"
"$ROOT_DIR/Scripts/build-icon.sh" >/dev/null
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$ROOT_DIR/.build/release/BuildLogViewer" "$APP_DIR/Contents/MacOS/BuildLogViewer"
cp "$ROOT_DIR/AppBundle/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/AppBundle/BuildLogViewer.icns" "$APP_DIR/Contents/Resources/BuildLogViewer.icns"
chmod +x "$APP_DIR/Contents/MacOS/BuildLogViewer"

echo "$APP_DIR"
