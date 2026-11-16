#!/bin/zsh
set -e
cd "$(dirname "$0")"
swift build -c release
APP=build/YANA.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/YANA "$APP/Contents/MacOS/YANA"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/*.lproj "$APP/Contents/Resources/"

# Signing identity: SIGN_ID env > "YANA Local Signing" certificate > ad-hoc.
# A stable certificate keeps macOS privacy permissions across rebuilds (ad-hoc changes identity every build).
if [[ -z "$SIGN_ID" ]] && security find-identity -p codesigning 2>/dev/null | grep -q "YANA Local Signing"; then
  SIGN_ID="YANA Local Signing"
fi
if [[ -n "$SIGN_ID" ]]; then
  codesign --force --deep -s "$SIGN_ID" "$APP"
  echo "🔏 Firmata con: $SIGN_ID"
else
  codesign --force --deep -s - "$APP"
  echo "⚠️  Firma ad-hoc: i permessi (Accessibilità, Disco) andranno ridati dopo ogni build."
  echo "    Crea il certificato 'YANA Local Signing' (vedi docs/07-build-sviluppo.md)."
fi
echo "✅ Creato $APP"
