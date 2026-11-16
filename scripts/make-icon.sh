#!/bin/zsh
# Rigenera Resources/AppIcon.icns e AppIcon-1024.png da logo-with-bg.png
set -e
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
swift scripts/make-icon.swift logo-with-bg.png "$TMP/icon_1024.png"
mkdir "$TMP/AppIcon.iconset"
for s in 16 32 128 256 512; do
  sips -z $s $s "$TMP/icon_1024.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$TMP/icon_1024.png" --out "$TMP/AppIcon.iconset/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$TMP/AppIcon.iconset" -o Resources/AppIcon.icns
cp "$TMP/icon_1024.png" Resources/AppIcon-1024.png
rm -rf "$TMP"
echo "✅ Icona rigenerata"
