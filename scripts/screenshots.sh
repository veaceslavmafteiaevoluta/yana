#!/bin/zsh
# Regenerates the README screenshots in assets/screenshots/ by running YANA in its hidden
# screenshot mode (renders its own view, no Screen Recording permission needed).
# Tip: start some music in Spotify/Music first so the media views have content.
set -e
cd "$(dirname "$0")/.."
OUT="$PWD/assets/screenshots"
[[ -d build/YANA.app ]] || ./build.sh
build/YANA.app/Contents/MacOS/YANA \
  -YANAScreenshots "$OUT" \
  -YANAScreenshotTabs "home,audio,widgets,system" \
  -YANAScreenshotCity "Cupertino" \
  -glassBackground NO \
  -AppleLanguages "(en)"
ls -lh "$OUT"
