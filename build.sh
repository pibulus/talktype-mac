#!/bin/bash
set -e

# TalkType Mac Build Pipeline
# Builds Direct Distribution (Unlocked DMG with Notarization readiness) or Mac App Store (Sandboxed PKG)

APP_NAME="TalkType"
VERSION="${VERSION:-1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SRC_FILE="TalkType.swift"
BUILD_DIR="build"
DIST_DIR="dist"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
BIN_DIR="${APP_DIR}/Contents/MacOS"
RES_DIR="${APP_DIR}/Contents/Resources"

TARGET_MODE="${1:-direct}" # "direct" or "mas"
UNIVERSAL="${UNIVERSAL:-0}"  # UNIVERSAL=1 builds a fat arm64 + x86_64 binary

echo "🎨 Building ${APP_NAME} v${VERSION} (${BUILD_NUMBER}) (${TARGET_MODE} target)..."

# Toolchain facts App Store validation likes to see in Info.plist
SDK_VERSION=$(xcrun --sdk macosx --show-sdk-version 2>/dev/null || echo "13.0")
SDK_BUILD=$(xcrun --sdk macosx --show-sdk-build-version 2>/dev/null || echo "")
XCODE_VERSION=$(xcodebuild -version 2>/dev/null | awk '/Xcode/ {print $2}' || echo "")
XCODE_BUILD=$(xcodebuild -version 2>/dev/null | awk '/Build version/ {print $3}' || echo "")
MACHINE_BUILD=$(sw_vers -buildVersion 2>/dev/null || echo "")

# Clean previous build artifacts
rm -rf "${BUILD_DIR}" "${DIST_DIR}"
mkdir -p "${BIN_DIR}" "${RES_DIR}" "${DIST_DIR}"

# 1. Compile Swift executable (Apple Silicon by default, universal with UNIVERSAL=1)
SWIFT_FLAGS="-parse-as-library -O"
if [ "${TARGET_MODE}" = "mas" ]; then
    SWIFT_FLAGS="${SWIFT_FLAGS} -D MAS_BUILD"
fi
if [ "${UNIVERSAL}" = "1" ]; then
    swiftc ${SWIFT_FLAGS} -target arm64-apple-macos13.0 "${SRC_FILE}" -o "${BUILD_DIR}/${APP_NAME}-arm64"
    swiftc ${SWIFT_FLAGS} -target x86_64-apple-macos13.0 "${SRC_FILE}" -o "${BUILD_DIR}/${APP_NAME}-x86_64"
    lipo -create "${BUILD_DIR}/${APP_NAME}-arm64" "${BUILD_DIR}/${APP_NAME}-x86_64" -output "${BIN_DIR}/${APP_NAME}"
    rm -f "${BUILD_DIR}/${APP_NAME}-arm64" "${BUILD_DIR}/${APP_NAME}-x86_64"
    echo "🧬 Universal binary (arm64 + x86_64)"
else
    swiftc ${SWIFT_FLAGS} -target arm64-apple-macos13.0 "${SRC_FILE}" -o "${BIN_DIR}/${APP_NAME}"
fi

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
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Pablo Alvarado. All rights reserved.</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>es</string>
    </array>
    <key>CFBundleSupportedPlatforms</key>
    <array>
        <string>MacOSX</string>
    </array>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
    <key>ITSAppUsesNonExemptEncryption</key>
    <false/>
    <key>DTPlatformName</key>
    <string>macosx</string>
    <key>DTSDKName</key>
    <string>macosx${SDK_VERSION}</string>
    <key>DTSDKBuild</key>
    <string>${SDK_BUILD}</string>
    <key>DTPlatformVersion</key>
    <string>${SDK_VERSION}</string>
    <key>DTXcode</key>
    <string>${XCODE_VERSION}</string>
    <key>DTXcodeBuild</key>
    <string>${XCODE_BUILD}</string>
    <key>BuildMachineOSBuild</key>
    <string>${MACHINE_BUILD}</string>
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>TalkType uses on-device speech recognition to transcribe your voice into text accurately.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>TalkType needs microphone access to listen to your voice when you hold the dictate shortcut.</string>
</dict>
</plist>
PLIST

# 3. Copy Assets & AppIcon
cp Assets/*.png "${RES_DIR}/" 2>/dev/null || true
if [ -f "Assets/AppIcon.icns" ]; then
    cp Assets/AppIcon.icns "${RES_DIR}/"
fi
if [ -f "PrivacyInfo.xcprivacy" ]; then
    cp PrivacyInfo.xcprivacy "${RES_DIR}/"
fi

chmod +x "${BIN_DIR}/${APP_NAME}"

# App Store builds must carry a provisioning profile (App Store Connect → Profiles →
# "Mac App Store Connect" type, bundle id com.pibulus.talktype). Drop it next to build.sh.
if [ "${TARGET_MODE}" = "mas" ] && [ -f "TalkType.provisionprofile" ]; then
    cp "TalkType.provisionprofile" "${APP_DIR}/Contents/embedded.provisionprofile"
    echo "📎 Embedded provisioning profile"
elif [ "${TARGET_MODE}" = "mas" ]; then
    echo "⚠️  No TalkType.provisionprofile found — App Store upload will be rejected without one."
fi

# 4. Code Signing & Entitlements (Secure Timestamp enabled)
if [ "${TARGET_MODE}" = "mas" ]; then
    ENTITLEMENTS="TalkType.sandbox.entitlements"
    echo "📦 Sandboxed App Store mode enabled with ${ENTITLEMENTS}"
    
    MAS_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
                   | grep "3rd Party Mac Developer Application\|Apple Distribution" | head -1 | sed 's/.*"\(.*\)"/\1/' || true)
    
    if [ -n "${MAS_IDENTITY}" ]; then
        codesign --force --sign "${MAS_IDENTITY}" \
                 --entitlements "${ENTITLEMENTS}" \
                 --timestamp \
                 --identifier com.pibulus.talktype "${BIN_DIR}/${APP_NAME}"
        codesign --force --sign "${MAS_IDENTITY}" \
                 --entitlements "${ENTITLEMENTS}" \
                 --timestamp \
                 --identifier com.pibulus.talktype "${APP_DIR}"
        echo "🔏 Signed with MAS certificate: ${MAS_IDENTITY}"
    else
        echo "⚠️ No Mac App Store Application certificate found. Signing ad-hoc for local testing..."
        codesign --force --sign - \
                 --entitlements "${ENTITLEMENTS}" \
                 --identifier com.pibulus.talktype "${BIN_DIR}/${APP_NAME}"
        codesign --force --sign - \
                 --entitlements "${ENTITLEMENTS}" \
                 --identifier com.pibulus.talktype "${APP_DIR}"
        echo "🔏 Ad-hoc signed for local testing"
    fi

    # Check for Installer certificate to package .pkg
    INSTALLER_ID=$(security find-identity -v -p basic 2>/dev/null \
                   | grep "3rd Party Mac Developer Installer\|Mac Developer Installer" | head -1 | sed 's/.*"\(.*\)"/\1/' || true)
    if [ -n "${INSTALLER_ID}" ]; then
        productbuild --component "${APP_DIR}" /Applications \
                     --sign "${INSTALLER_ID}" \
                     "${DIST_DIR}/${APP_NAME}-${VERSION}.pkg"
        echo "✨ Mac App Store PKG ready at ${DIST_DIR}/${APP_NAME}-${VERSION}.pkg"
        echo "    Validate:  xcrun altool --validate-app -f ${DIST_DIR}/${APP_NAME}-${VERSION}.pkg -t macos --apiKey <key-id> --apiIssuer <issuer>"
        echo "    Upload:    open -a Transporter ${DIST_DIR}/${APP_NAME}-${VERSION}.pkg"
    else
        echo "⚠️  No '3rd Party Mac Developer Installer' certificate — skipping .pkg (needed for App Store upload)."
    fi

else
    ENTITLEMENTS="TalkType.entitlements"
    echo "⚡ Direct distribution mode enabled with Hardened Runtime & ${ENTITLEMENTS}"
    
    IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
               | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/' || true)
    
    if [ -n "${IDENTITY}" ]; then
        codesign --force --sign "${IDENTITY}" \
                 --options runtime \
                 --entitlements "${ENTITLEMENTS}" \
                 --timestamp \
                 --identifier com.pibulus.talktype "${BIN_DIR}/${APP_NAME}"
        codesign --force --sign "${IDENTITY}" \
                 --options runtime \
                 --entitlements "${ENTITLEMENTS}" \
                 --timestamp \
                 --identifier com.pibulus.talktype "${APP_DIR}"
        echo "🔏 Signed with Developer ID: ${IDENTITY}"
    else
        codesign --force --sign - \
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

    # Sign the DMG disk image container
    if [ -n "${IDENTITY}" ]; then
        codesign --force --sign "${IDENTITY}" --timestamp "${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"
        echo "🔏 Signed DMG container with Developer ID: ${IDENTITY}"
    fi

    # 6. Notarize & staple (direct distribution). Gracefully skipped without a profile.
    NOTARY_PROFILE="${NOTARY_PROFILE:-talktype-notary}"
    DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"
    if [ "${SKIP_NOTARIZE:-0}" = "1" ]; then
        echo "⏭️  Skipping notarization (SKIP_NOTARIZE=1)."
    elif xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" >/dev/null 2>&1; then
        echo "🔐 Submitting DMG for notarization (profile: ${NOTARY_PROFILE})…"
        if xcrun notarytool submit "${DMG_PATH}" --keychain-profile "${NOTARY_PROFILE}" --wait; then
            echo "📎 Stapling notarization ticket…"
            xcrun stapler staple "${DMG_PATH}"
            echo "✅ Notarized & stapled: ${DMG_PATH}"
        else
            echo "❌ Notarization failed. DMG is signed but not notarized."
        fi
    else
        echo "⚠️  Notary profile '${NOTARY_PROFILE}' not found — skipping notarization."
        echo "    Create it once with:"
        echo "      xcrun notarytool store-credentials \"${NOTARY_PROFILE}\" \\"
        echo "        --apple-id <apple-id-email> --team-id V433H655PN --password <app-specific-password>"
        echo "    (or an App Store Connect API key via --key / --key-id / --issuer)"
    fi
    echo "✨ Direct DMG ready at ${DMG_PATH}"
fi

echo "✨ Built successfully at ${APP_DIR}"
