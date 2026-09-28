#!/bin/bash
# Renders the app icon PNGs from design/icon/*.svg into the asset catalog.
# Needs rsvg-convert (brew install librsvg). Run from anywhere.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
src=design/icon
out=Apps/PointerLocker/Assets.xcassets/AppIcon.appiconset
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

rsvg-convert -w 1024 -h 1024 "$src/mouselook.svg" -o "$tmp/icon.png"
# The main icon must be opaque with no alpha channel: round-trip through BMP.
sips -s format bmp "$tmp/icon.png" --out "$tmp/icon.bmp" >/dev/null
sips -s format png "$tmp/icon.bmp" --out "$out/icon-1024.png" >/dev/null

# Dark and tinted keep their transparent background.
rsvg-convert -w 1024 -h 1024 "$src/mouselook-dark.svg" -o "$out/icon-1024-dark.png"
rsvg-convert -w 1024 -h 1024 "$src/mouselook-tinted.svg" -o "$out/icon-1024-tinted.png"

sips -g hasAlpha "$out"/icon-1024*.png | grep -E "png|hasAlpha"
