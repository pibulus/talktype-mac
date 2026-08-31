#!/bin/bash
set -e

# TalkType Mac Build Pipeline
# Builds Direct Distribution (Unlocked DMG) or Mac App Store (Sandboxed PKG)

APP_NAME="TalkType"
VERSION="1.0"
BUILD_NUMBER="1"
SRC_FILE="TalkType.swift"
BUILD_DIR="build"
DIST_DIR="dist"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
BIN_DIR="${APP_DIR}/Contents/MacOS"
RES_DIR="${APP_DIR}/Contents/Resources"

TARGET_MODE="${1:-direct}" # "direct" or "mas"

echo "🎨 Building ${APP_NAME} v${VERSION} (${TARGET_MODE} target)..."

# Clean previous build artifacts
rm -rf "${BUILD_DIR}" "${DIST_DIR}"
mkdir -p "${BIN_DIR}" "${RES_DIR}" "${DIST_DIR}"

# 1. Compile Swift executable (Apple Silicon optimized)
swiftc -parse-as-library -O -target arm64-apple-macos13.0 "${SRC_FILE}" -o "${BIN_DIR}/${APP_NAME}"

# 2. Generate Production Info.plist
cat > "${APP_DIR}/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.pibulus.talktype</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Pablo Alvarado. All rights reserved.</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>TalkType uses speech recognition to transcribe your voice into text accurately.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>TalkType needs microphone access to listen to your voice when you hold the dictate key.</string>
</dict>
</plist>
PLIST

# 3. Copy Assets & AppIcon
cp Assets/*.png "${RES_DIR}/" 2>/dev/null || true
if [ -f "Assets/AppIcon.icns" ]; then
    cp Assets/AppIcon.icns "${RES_DIR}/"
fi

chmod +x "${BIN_DIR}/${APP_NAME}"

# 4. Code Signing & Entitlements
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
           | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/')

if [ "${TARGET_MODE}" = "mas" ]; then
    ENTITLEMENTS="TalkType.sandbox.entitlements"
    echo "📦 Sandboxed App Store mode enabled with ${ENTITLEMENTS}"
    
    MAS_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
                   | grep "Apple Distribution\|3rd Party Mac Developer Application" | head -1 | sed 's/.*"\(.*\)"/\1/')
    SIGN_ID="${MAS_IDENTITY:-${IDENTITY}}"
    
    if [ -n "${SIGN_ID}" ]; then
        codesign --force --deep --sign "${SIGN_ID}" \
                 --entitlements "${ENTITLEMENTS}" \
                 --identifier com.pibulus.talktype \
                 --timestamp=none "${APP_DIR}"
        echo "🔏 Signed with: ${SIGN_ID}"
    else
        codesign --force --deep --sign - \
                 --entitlements "${ENTITLEMENTS}" \
                 --identifier com.pibulus.talktype "${APP_DIR}"
        echo "🔏 Ad-hoc signed for App Store local testing"
    fi
else
    ENTITLEMENTS="TalkType.entitlements"
    echo "⚡ Direct distribution mode enabled with Hardened Runtime & ${ENTITLEMENTS}"
    
    if [ -n "${IDENTITY}" ]; then
        codesign --force --deep --sign "${IDENTITY}" \
                 --options runtime \
                 --entitlements "${ENTITLEMENTS}" \
                 --identifier com.pibulus.talktype \
                 --timestamp=none "${APP_DIR}"
        echo "🔏 Signed with Developer ID: ${IDENTITY}"
    else
        codesign --force --deep --sign - \
                 --entitlements "${ENTITLEMENTS}" \
                 --identifier com.pibulus.talktype "${APP_DIR}"
        echo "🔏 Ad-hoc signed"
    fi
    
    # 5. Build DMG for Direct Distribution
    echo "💿 Creating DMG disk image..."
    DMG_STAGE="${BUILD_DIR}/dmg_stage"
    mkdir -p "${DMG_STAGE}"
    cp -R "${APP_DIR}" "${DMG_STAGE}/"
    ln -s /Applications "${DMG_STAGE}/Applications"
    
    hdiutil create -volname "${APP_NAME}" \
            -srcfolder "${DMG_STAGE}" \
            -ov -format UDZO \
            "${DIST_DIR}/${APP_NAME}-${VERSION}.dmg" > /dev/null
            
    rm -rf "${DMG_STAGE}"
    echo "✨ Direct DMG ready at ${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"
fi

echo "✨ Built successfully at ${APP_DIR}"
