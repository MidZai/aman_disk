#!/bin/bash
# Creates dist/Aman-Disk-<version>.dmg (the app, a shortcut to /Applications and the install guide),
# with hdiutil only.
# Run after “scripts/bundle.sh --release”.
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR/.."

APP="Aman Disk.app"
if [ ! -d "$APP" ]; then
    echo "“$APP” not found: run scripts/bundle.sh --release first." >&2
    exit 1
fi

VERSION=$(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString)
DMG="dist/Aman-Disk-$VERSION.dmg"
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT

mkdir -p dist
rm -f "$DMG"
# ditto keeps the bundle's signature and extended attributes.
ditto "$APP" "$STAGING/$APP"
ln -s /Applications "$STAGING/Applications"
cp "scripts/dmg/How to Install.txt" "$STAGING/"

hdiutil create -volname "Aman Disk $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG"
hdiutil verify "$DMG"
echo "DMG created: $DMG ($(du -h "$DMG" | cut -f1))"
