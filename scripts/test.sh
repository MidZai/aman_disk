#!/bin/bash
# Runs the whole test suite (Swift Testing).
#
# With Xcode: `swift test` is enough.
# With the Command Line Tools alone, the Testing module isn't in the search path,
# and since macOS 26 SwiftPM's helper (signed by Apple, library validation)
# refuses to load the locally built test bundle. So the tests are built, then
# run with a small local runner (scripts/TestRunner.swift).
set -e
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
cd "$DIR/.."

DEV="$(xcode-select -p)"
if [[ "$DEV" != *CommandLineTools* ]]; then
    exec swift test "$@"
fi

FW="$DEV/Library/Developer/Frameworks"
LIB="$DEV/Library/Developer/usr/lib"
swift build --build-tests \
    -Xswiftc -F -Xswiftc "$FW" \
    -Xlinker -F -Xlinker "$FW" \
    -Xlinker -rpath -Xlinker "$FW"

RUNNER=".build/test-runner/TestRunner"
if [ ! -x "$RUNNER" ] || [ "scripts/TestRunner.swift" -nt "$RUNNER" ]; then
    mkdir -p .build/test-runner
    swiftc -parse-as-library -O -F "$FW" -Xlinker -rpath -Xlinker "$FW" -Xlinker -rpath -Xlinker "$LIB" \
        scripts/TestRunner.swift -o "$RUNNER"
fi

BUNDLE="$(swift build --show-bin-path)/DiskHealthPackageTests.xctest/Contents/MacOS/DiskHealthPackageTests"
exec "$RUNNER" "$BUNDLE" "$@"
