#!/bin/bash
set -e

echo "Compiling DiskHealthApp in release mode..."
swift build -c release --arch arm64 --arch x86_64

APP_NAME="Aman Disk.app"
CONTENTS_DIR="$APP_NAME/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "Creating app bundle structure..."
rm -rf "$APP_NAME"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Determine swift architecture path
SWIFT_BIN_PATH=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)

echo "Copying executable..."
cp "$SWIFT_BIN_PATH/DiskHealthApp" "$MACOS_DIR/AmanDisk"

echo "Copying resources..."
cp "Branding/Aman-Disk-brand/icone-app/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
cp "Branding/Aman-Disk-brand/logo/aman-disk-logo-clair@2x.png" "$RESOURCES_DIR/"
cp "Branding/Aman-Disk-brand/logo/aman-disk-logo-sombre@2x.png" "$RESOURCES_DIR/"

echo "Creating Info.plist..."
cat > "$CONTENTS_DIR/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>AmanDisk</string>
    <key>CFBundleIdentifier</key>
    <string>io.github.aman-disk.AmanDisk</string>
    <key>CFBundleName</key>
    <string>Aman</string>
    <key>CFBundleDisplayName</key>
    <string>Aman Disk</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.3.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 Aman Disk contributors · Licence MIT</string>
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
PLIST

echo "Creating entitlements..."
cat > "AmanDisk-entitlement.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
</dict>
</plist>
PLIST

echo "Signing application..."
codesign --force --sign - --entitlements AmanDisk-entitlement.plist "$APP_NAME"

echo "Done! $APP_NAME has been created successfully."
