#!/bin/bash
# Crée dist/Aman-Disk-<version>.dmg (l'app + un raccourci vers /Applications), avec hdiutil uniquement.
# À lancer après « scripts/bundle.sh --release ».
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR/.."

APP="Aman Disk.app"
if [ ! -d "$APP" ]; then
    echo "« $APP » introuvable : lancez d'abord scripts/bundle.sh --release." >&2
    exit 1
fi

VERSION=$(defaults read "$PWD/$APP/Contents/Info" CFBundleShortVersionString)
DMG="dist/Aman-Disk-$VERSION.dmg"
STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT

mkdir -p dist
rm -f "$DMG"
# ditto conserve la signature et les attributs étendus du bundle.
ditto "$APP" "$STAGING/$APP"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "Aman Disk $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG"
hdiutil verify "$DMG"
echo "DMG créé : $DMG ($(du -h "$DMG" | cut -f1))"
