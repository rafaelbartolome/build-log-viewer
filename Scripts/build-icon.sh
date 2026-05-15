#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SVG_PATH="$ROOT_DIR/Assets/AppIcon.svg"
ICONSET_DIR="$ROOT_DIR/AppBundle/BuildLogViewer.iconset"
ICNS_PATH="$ROOT_DIR/AppBundle/BuildLogViewer.icns"

command -v rsvg-convert >/dev/null
command -v iconutil >/dev/null

rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

render_icon() {
    local size="$1"
    local output="$2"
    rsvg-convert -w "$size" -h "$size" "$SVG_PATH" -o "$ICONSET_DIR/$output"
}

render_icon 16 icon_16x16.png
render_icon 32 icon_16x16@2x.png
render_icon 32 icon_32x32.png
render_icon 64 icon_32x32@2x.png
render_icon 128 icon_128x128.png
render_icon 256 icon_128x128@2x.png
render_icon 256 icon_256x256.png
render_icon 512 icon_256x256@2x.png
render_icon 512 icon_512x512.png
render_icon 1024 icon_512x512@2x.png

iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"
echo "$ICNS_PATH"
