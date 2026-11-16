#!/bin/zsh
# Builds YANA.app and packages it as dist/YANA-<version>.dmg and .zip.
# With --publish, also tags v<version> and creates the GitHub release (requires `gh auth login`).
set -e
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
NAME="YANA-$VERSION"
DIST=dist

./build.sh

rm -rf "$DIST"
mkdir -p "$DIST"

# ZIP (ditto keeps the code signature and extended attributes intact)
ditto -c -k --sequesterRsrc --keepParent build/YANA.app "$DIST/$NAME.zip"

# DMG with a shortcut to /Applications for drag-and-drop install
STAGE=$(mktemp -d)
cp -R build/YANA.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "YANA $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$DIST/$NAME.dmg" >/dev/null
rm -rf "$STAGE"

(cd "$DIST" && shasum -a 256 "$NAME.dmg" "$NAME.zip" > SHA256SUMS.txt)
echo "📦 Created:"
ls -lh "$DIST"

if [[ "$1" == "--publish" ]]; then
  TAG="v$VERSION"
  NOTES=$(cat <<EOF
## Install
1. Download **$NAME.dmg**, open it and drag **YANA** to **Applications**.
2. YANA isn't notarized, so the first launch is blocked: open **System Settings › Privacy & Security** and click **Open Anyway**, or run:
   \`\`\`
   xattr -dr com.apple.quarantine /Applications/YANA.app
   \`\`\`
3. Look for the capsule icon in the menu bar. Grant the permissions from **Settings… › Permissions**.

Requires macOS 14+ on Apple Silicon. See the [README](https://github.com/veaceslavmafteiaevoluta/yana#readme) for details.
EOF
)
  gh release create "$TAG" "$DIST/$NAME.dmg" "$DIST/$NAME.zip" "$DIST/SHA256SUMS.txt" \
    --title "YANA $VERSION" --notes "$NOTES"
fi
