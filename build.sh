#!/bin/bash
set -e

# TalkType Mac Build Pipeline
# Builds Direct Distribution (Unlocked DMG with Notarization readiness) or Mac App Store (Sandboxed PKG)

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

# MAS release needs BOTH Apple certs. Check before wiping build/ and dist/ so a
# doomed run can't take the last good DMG down with it.
if [ "${TARGET_MODE}" = "mas" ]; then
    MAS_IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
                   | grep "3rd Party Mac Developer Application\|Apple Distribution" | head -1 | sed 's/.*"\(.*\)"/\1/' || true)
    INSTALLER_ID=$(security find-identity -v -p basic 2>/dev/null \
                   | grep "3rd Party Mac Developer Installer\|Mac Installer Distribution" | head -1 | sed 's/.*"\(.*\)"/\1/' || true)
    if [ "${ALLOW_ADHOC_MAS:-0}" != "1" ] && { [ -z "${MAS_IDENTITY}" ] || [ -z "${INSTALLER_ID}" ]; }; then
        echo "❌ Cannot build a Mac App Store release — missing certificate(s):"
        [ -z "${MAS_IDENTITY}" ] && echo "   • App signing: 'Apple Distribution' or '3rd Party Mac Developer Application'"
        [ -z "${INSTALLER_ID}" ] && echo "   • Installer:   '3rd Party Mac Developer Installer' (Mac Installer Distribution)"
        echo "   Create them at developer.apple.com → Certificates, or Xcode → Settings → Accounts → Manage Certificates."
        echo "   ALLOW_ADHOC_MAS=1 ./build.sh mas  builds an ad-hoc sandboxed binary for local testing only."
        echo "   Nothing was touched: build/ and dist/ are as you left them."
        exit 1
    fi
fi

# Clean previous build artifacts
rm -rf "${BUILD_DIR}" "${DIST_DIR}"
mkdir -p "${BIN_DIR}" "${RES_DIR}" "${DIST_DIR}"

# 1. Compile Swift executable (Apple Silicon optimized)
SWIFT_FLAGS="-parse-as-library -O -target arm64-apple-macos13.0"
if [ "${TARGET_MODE}" = "mas" ]; then
    SWIFT_FLAGS="${SWIFT_FLAGS} -D MAS_BUILD"
fi
swiftc ${SWIFT_FLAGS} "${SRC_FILE}" -o "${BIN_DIR}/${APP_NAME}"

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

# 4. Code Signing & Entitlements (Secure Timestamp enabled)
if [ "${TARGET_MODE}" = "mas" ]; then
    ENTITLEMENTS="TalkType.sandbox.entitlements"
    echo "📦 Sandboxed App Store mode enabled with ${ENTITLEMENTS}"

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
        # Only reachable with ALLOW_ADHOC_MAS=1 (preflight exits otherwise)
        codesign --force --sign - \
                 --entitlements "${ENTITLEMENTS}" \
                 --identifier com.pibulus.talktype "${BIN_DIR}/${APP_NAME}"
        codesign --force --sign - \
                 --entitlements "${ENTITLEMENTS}" \
                 --identifier com.pibulus.talktype "${APP_DIR}"
        echo "🔏 Ad-hoc signed (ALLOW_ADHOC_MAS=1)"
    fi

    if [ -n "${MAS_IDENTITY}" ] && [ -n "${INSTALLER_ID}" ]; then
        productbuild --component "${APP_DIR}" /Applications \
                     --sign "${INSTALLER_ID}" \
                     "${DIST_DIR}/${APP_NAME}-${VERSION}.pkg"
        echo "✨ Mac App Store PKG ready at ${DIST_DIR}/${APP_NAME}-${VERSION}.pkg"
    else
        echo "🚧 LOCAL TEST BUILD ONLY — no .pkg, not submittable to App Store Connect."
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
    
    # 5. Build Styled DMG for Direct Distribution
    DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"
    rm -f "${DMG_PATH}"

    if command -v create-dmg >/dev/null 2>&1; then
        echo "🎨 Building styled DMG with custom volume icon and background..."
        DMG_STAGE="${BUILD_DIR}/dmg_stage"
        rm -rf "${DMG_STAGE}"
        mkdir -p "${DMG_STAGE}"
        cp -R "${APP_DIR}" "${DMG_STAGE}/"

        # Background art (1x+2x TIFF) comes from `swift Assets/make-art.swift`.
        # It is 660x400; the window is 28pt taller because Finder counts the title bar.
        CREATE_DMG_ARGS=(
            --volname "${APP_NAME}"
            --volicon "Assets/AppIcon.icns"
            --background "Assets/dmg-background.tiff"
            --window-pos 200 120
            --window-size 660 428
            --text-size 13
            --icon-size 112
            --icon "${APP_NAME}.app" 165 190
            --hide-extension "${APP_NAME}.app"
            --app-drop-link 495 190
            --no-internet-enable
            --format UDZO
            --overwrite
        )

        create-dmg "${CREATE_DMG_ARGS[@]}" "${DMG_PATH}" "${DMG_STAGE}" || true
        rm -rf "${DMG_STAGE}"
    fi

    # Fallback to hdiutil if create-dmg was missing or failed
    if [ ! -f "${DMG_PATH}" ]; then
        echo "💿 Fallback: Creating DMG with hdiutil..."
        DMG_STAGE="${BUILD_DIR}/dmg_stage"
        mkdir -p "${DMG_STAGE}"
        cp -R "${APP_DIR}" "${DMG_STAGE}/"
        ln -s /Applications "${DMG_STAGE}/Applications"
        if [ -f "Assets/AppIcon.icns" ]; then
            cp "Assets/AppIcon.icns" "${DMG_STAGE}/.VolumeIcon.icns"
            SetFile -c icnC "${DMG_STAGE}/.VolumeIcon.icns" 2>/dev/null || true
        fi
        hdiutil create -volname "${APP_NAME}" \
                -srcfolder "${DMG_STAGE}" \
                -ov -format UDZO \
                "${DMG_PATH}" > /dev/null
        if [ -f "Assets/AppIcon.icns" ]; then
            SetFile -a C "${DMG_PATH}" 2>/dev/null || true
        fi
        rm -rf "${DMG_STAGE}"
    fi

    # Sign the DMG disk image container
    if [ -n "${IDENTITY}" ]; then
        codesign --force --sign "${IDENTITY}" --timestamp "${DMG_PATH}"
        echo "🔏 Signed DMG container with Developer ID: ${IDENTITY}"
    fi

    # 6. Notarize & staple (direct distribution). Gracefully skipped without a profile.
    NOTARY_PROFILE="${NOTARY_PROFILE:-talktype-notary}"
    DMG_PATH="${DIST_DIR}/${APP_NAME}-${VERSION}.dmg"
    if [ "${SKIP_NOTARIZE:-0}" = "1" ]; then
        echo "⏭️  Skipping notarization (SKIP_NOTARIZE=1)."
    elif xcrun notarytool history --keychain-profile "${NOTARY_PROFILE}" >/dev/null 2>&1; then
        echo "🔐 Submitting DMG for notarization (profile: ${NOTARY_PROFILE})…"
        # Stapling only succeeds if Apple issued a ticket, so it's the real pass/fail.
        xcrun notarytool submit "${DMG_PATH}" --keychain-profile "${NOTARY_PROFILE}" --wait || true
        if xcrun stapler staple "${DMG_PATH}"; then
            echo "✅ Notarized & stapled: ${DMG_PATH}"
        else
            echo "❌ Notarization failed — see: xcrun notarytool log <submission-id> --keychain-profile ${NOTARY_PROFILE}"
            exit 1
        fi
    else
        echo "⚠️  Notary profile '${NOTARY_PROFILE}' not found — skipping notarization."
        echo "    Create it once with:"
        echo "      xcrun notarytool store-credentials \"${NOTARY_PROFILE}\" \\"
        echo "        --apple-id <apple-id-email> --team-id V433H655PN --password <app-specific-password>"
        echo "    (or an App Store Connect API key via --key / --key-id / --issuer)"
    fi

    # Gatekeeper is the only judge that matters for a download.
    if spctl -a -t open --context context:primary-signature "${DMG_PATH}" 2>/dev/null; then
        echo "✨ Direct DMG ready to ship: ${DMG_PATH}"
    else
        echo "🚧 ${DMG_PATH} is LOCAL-ONLY: Gatekeeper rejects it (not notarized). Do not upload it."
    fi
fi

echo "✨ Built successfully at ${APP_DIR}"
