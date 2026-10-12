#!/bin/bash
set -e
# Always work from the repository root, whatever the current directory.
cd "$(dirname "$0")"

# Single source for the version number: the VERSION file at the repository root.
VERSION="${VERSION:-$(tr -d '[:space:]' < VERSION)}"
# Build number: the number of commits, or 1 outside a git checkout.
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
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
cp "Sources/DiskHealthCore/Resources/usb-bridges.json" "$RESOURCES_DIR/"

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
    <string>$BUILD_NUMBER</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 MidZai · MIT License</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSRemovableVolumesUsageDescription</key>
    <string>Aman Disk needs this permission to detect and monitor the health of your external drives and USB sticks.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <!-- Resident app (menu bar): macOS must not quit it on its own when the window is closed
         (that would end monitoring), nor kill it without warning during a test. -->
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
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

# Text of the “Removable Volumes” permission prompt, per language (macOS shows the user's language).
removable_volumes_description() {
    case "$1" in
        en) echo "Aman Disk needs this permission to detect and monitor the health of your external drives and USB sticks." ;;
        fr) echo "Aman Disk a besoin de cette permission pour détecter et surveiller l'état de vos disques externes et clés USB." ;;
        zh-Hans) echo "Aman Disk 需要此权限来检测并监控您的外置硬盘和 U 盘的健康状况。" ;;
        zh-Hant) echo "Aman Disk 需要此權限來偵測並監控您的外接硬碟和 USB 隨身碟的健康狀況。" ;;
        ko) echo "Aman Disk가 외장 드라이브와 USB 메모리의 상태를 감지하고 모니터링하려면 이 권한이 필요합니다." ;;
        ar) echo "يحتاج Aman Disk إلى هذا الإذن لاكتشاف أقراصك الخارجية ومفاتيح USB ومراقبة حالتها." ;;
        pt-BR|pt) echo "O Aman Disk precisa desta permissão para detectar e monitorar a saúde dos seus discos externos e pen drives." ;;
        es) echo "Aman Disk necesita este permiso para detectar y supervisar el estado de sus discos externos y memorias USB." ;;
        de) echo "Aman Disk benötigt diese Berechtigung, um den Zustand Ihrer externen Laufwerke und USB-Sticks zu erkennen und zu überwachen." ;;
        it) echo "Aman Disk ha bisogno di questa autorizzazione per rilevare e monitorare lo stato dei tuoi dischi esterni e delle chiavette USB." ;;
        ja) echo "Aman Disk が外付けドライブや USB メモリの状態を検出して監視するには、この許可が必要です。" ;;
        ru) echo "Aman Disk нужно это разрешение, чтобы обнаруживать внешние диски и USB-накопители и следить за их состоянием." ;;
        tr) echo "Aman Disk, harici sürücülerinizin ve USB belleklerinizin sağlığını algılayıp izlemek için bu izne ihtiyaç duyar." ;;
        nl) echo "Aman Disk heeft deze toestemming nodig om de gezondheid van uw externe schijven en usb-sticks te detecteren en te bewaken." ;;
        pl) echo "Aman Disk potrzebuje tego uprawnienia, aby wykrywać dyski zewnętrzne i pamięci USB oraz monitorować ich stan." ;;
        hi) echo "Aman Disk को आपकी बाहरी ड्राइव और USB स्टिक की स्थिति का पता लगाने और निगरानी करने के लिए इस अनुमति की आवश्यकता है।" ;;
        vi) echo "Aman Disk cần quyền này để phát hiện và theo dõi tình trạng ổ đĩa ngoài và USB của bạn." ;;
        uk) echo "Aman Disk потрібен цей дозвіл, щоб виявляти зовнішні диски та USB-накопичувачі й стежити за їхнім станом." ;;
        *) echo "Aman Disk needs this permission to detect and monitor the health of your external drives and USB sticks." ;;
    esac
}

echo "Creating localization resources..."
for lang in fr en zh-Hans zh-Hant ko ar pt-BR pt es de it ja ru tr nl pl hi vi uk; do
    mkdir -p "$RESOURCES_DIR/$lang.lproj"
    cat > "$RESOURCES_DIR/$lang.lproj/InfoPlist.strings" << EOF
CFBundleDisplayName = "Aman Disk";
CFBundleName = "Aman Disk";
NSRemovableVolumesUsageDescription = "$(removable_volumes_description "$lang")";
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
# Ad hoc signature (no developer account: the app isn't notarized). Each binary inside the
# bundle is signed explicitly, then the bundle itself, with the hardened runtime.
codesign --force --sign - --options runtime --entitlements AmanDisk-entitlement.plist "$MACOS_DIR/AmanDisk"
codesign --force --sign - --options runtime --entitlements AmanDisk-entitlement.plist "$APP_NAME"
codesign --verify --deep --strict "$APP_NAME"

# Re-register with macOS LaunchServices so macOS updates its per-app language list
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_NAME" 2>/dev/null || true

echo "Done! $APP_NAME has been created successfully."
