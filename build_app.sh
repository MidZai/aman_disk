#!/bin/bash
set -e

VERSION="${VERSION:-0.9.4}"
UNIVERSAL="${UNIVERSAL:-0}"
BUILT_BINARY=".build/AmanDisk-bundle-binary"

if [ "$UNIVERSAL" == "1" ]; then
    # One build per architecture (--triple doesn't need xcbuild, unlike
    # “--arch arm64 --arch x86_64”), then combined with lipo.
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
cp "Branding/Aman-Disk-brand/app-icon/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
cp "Branding/Aman-Disk-brand/logo/aman-disk-logo-light@2x.png" "$RESOURCES_DIR/"
cp "Branding/Aman-Disk-brand/logo/aman-disk-logo-dark@2x.png" "$RESOURCES_DIR/"
cp "Resources/usb-bridges.json" "$RESOURCES_DIR/"

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
    <string>© 2026 MidZai · MIT License</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSRemovableVolumesUsageDescription</key>
    <string>Aman Disk a besoin de cette permission pour détecter et surveiller l'état de vos disques durs externes et clés USB.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <!-- Resident app (menu bar): macOS must not quit it on its own when the window is closed
         (that would end monitoring), nor kill it without warning during a test. -->
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>CFBundleDevelopmentRegion</key>
    <string>fr</string>
    <key>CFBundleAllowMixedLocalizations</key>
    <true/>
    <key>CFBundleLocalizations</key>
    <array>
        <string>fr</string>
        <string>en</string>
        <string>zh-Hans</string>
        <string>zh-Hant</string>
        <string>ko</string>
        <string>ar</string>
        <string>pt-BR</string>
        <string>pt</string>
        <string>es</string>
        <string>de</string>
        <string>it</string>
        <string>ja</string>
        <string>ru</string>
        <string>tr</string>
        <string>nl</string>
        <string>pl</string>
        <string>hi</string>
        <string>vi</string>
        <string>uk</string>
    </array>
</dict>
</plist>
PLIST

echo "Creating localization resources..."
for lang in fr en zh-Hans zh-Hant ko ar pt-BR pt es de it ja ru tr nl pl hi vi uk; do
    mkdir -p "$RESOURCES_DIR/$lang.lproj"
    cat > "$RESOURCES_DIR/$lang.lproj/InfoPlist.strings" << EOF
CFBundleDisplayName = "Aman Disk";
CFBundleName = "Aman Disk";
EOF
    cat > "$RESOURCES_DIR/$lang.lproj/Localizable.strings" << EOF
"CFBundleDisplayName" = "Aman Disk";
EOF
done

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
# Ad hoc signature (no developer account: the app isn't notarized).
codesign --force --deep --sign - --entitlements AmanDisk-entitlement.plist "$APP_NAME"
codesign --verify --deep --strict "$APP_NAME"

echo "Copying to root folder..."
cp -R "$APP_NAME" "../$APP_NAME" 2>/dev/null || true

# Re-register with macOS LaunchServices so macOS updates its per-app language list
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_NAME" 2>/dev/null || true
if [ -d "../$APP_NAME" ]; then
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "../$APP_NAME" 2>/dev/null || true
fi

echo "Done! $APP_NAME has been created successfully."
