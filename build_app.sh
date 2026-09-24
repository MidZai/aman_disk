#!/bin/bash
set -e

VERSION="${VERSION:-0.9.1}"
UNIVERSAL="${UNIVERSAL:-0}"
BUILT_BINARY=".build/AmanDisk-bundle-binary"

if [ "$UNIVERSAL" == "1" ]; then
    # Une compilation par architecture (--triple ne demande pas xcbuild, contrairement à
    # « --arch arm64 --arch x86_64 »), puis assemblage avec lipo.
    echo "Compiling DiskHealthApp (release, universal)..."
    SLICES=()
    for ARCH in arm64 x86_64; do
        swift build -c release --product DiskHealthApp --triple "$ARCH-apple-macosx14.0"
        SLICES+=("$(swift build -c release --product DiskHealthApp --triple "$ARCH-apple-macosx14.0" --show-bin-path)/DiskHealthApp")
    done
    lipo -create "${SLICES[@]}" -output "$BUILT_BINARY"
else
    echo "Compiling DiskHealthApp (release, $(uname -m))..."
    swift build -c release --product DiskHealthApp
    cp "$(swift build -c release --show-bin-path)/DiskHealthApp" "$BUILT_BINARY"
fi

APP_NAME="Aman Disk.app"
CONTENTS_DIR="$APP_NAME/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "Creating app bundle structure..."
rm -rf "$APP_NAME"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

echo "Copying executable..."
cp "$BUILT_BINARY" "$MACOS_DIR/AmanDisk"

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
    <string>$VERSION</string>
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
    <!-- App résidente (barre des menus) : macOS ne doit ni la fermer d'office quand la fenêtre
         est fermée (fin de la surveillance), ni la tuer sans prévenir pendant un test. -->
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
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
# Signature ad hoc (pas de compte développeur : l'app n'est pas notariée).
codesign --force --deep --sign - --entitlements AmanDisk-entitlement.plist "$APP_NAME"
codesign --verify --deep --strict "$APP_NAME"

echo "Done! $APP_NAME has been created successfully."
