#!/bin/bash
# Builds “Aman Disk.app”.
#   scripts/bundle.sh            → this machine's architecture (fast, for development)
#   scripts/bundle.sh --release  → universal binary (Apple Silicon + Intel), for release
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR/.."

VERSION="0.9.2"
UNIVERSAL=0
if [ "$1" == "--release" ]; then
    UNIVERSAL=1
fi

echo "Building Aman Disk v$VERSION bundle..."
VERSION="$VERSION" UNIVERSAL="$UNIVERSAL" ./build_app.sh
