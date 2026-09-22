#!/bin/bash
set -e

echo "Compiling DiskHealthApp in release mode..."
swift build -c release

APP_NAME="DiskHealth.app"
CONTENTS_DIR="$APP_NAME/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "Creating app bundle structure..."
rm -rf "$APP_NAME"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Determine swift architecture path
SWIFT_BIN_PATH=$(swift build -c release --show-bin-path)

echo "Copying executable..."
cp "$SWIFT_BIN_PATH/DiskHealthApp" "$MACOS_DIR/DiskHealth"

echo "Creating Info.plist..."
cat > "$CONTENTS_DIR/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>DiskHealth</string>
    <key>CFBundleIdentifier</key>
    <string>com.example.diskhealth</string>
    <key>CFBundleName</key>
    <string>DiskHealth</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.2.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <true/>
</dict>
</plist>
EOF

echo "Creating entitlements..."
cat > "DiskHealthApp-entitlement.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
</dict>
</plist>
EOF

echo "Signing application..."
codesign --force --sign - --entitlements DiskHealthApp-entitlement.plist "$APP_NAME"

echo "Done! $APP_NAME has been created successfully."
