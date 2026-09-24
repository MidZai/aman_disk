#!/bin/bash
# Construit « Aman Disk.app ».
#   scripts/bundle.sh            → architecture de la machine (rapide, pour le développement)
#   scripts/bundle.sh --release  → binaire universel (Apple Silicon + Intel), pour la publication
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR/.."

VERSION="0.9.1"
UNIVERSAL=0
if [ "$1" == "--release" ]; then
    UNIVERSAL=1
fi

echo "Building Aman Disk v$VERSION bundle..."
VERSION="$VERSION" UNIVERSAL="$UNIVERSAL" ./build_app.sh
