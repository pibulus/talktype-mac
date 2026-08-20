#!/bin/bash

# TalkType Mac Build Script
# Creates a standalone .app bundle from a single Swift file

APP_NAME="TalkType"
SRC_FILE="TalkType.swift"
BUILD_DIR="build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
BIN_DIR="${APP_DIR}/Contents/MacOS"
RES_DIR="${APP_DIR}/Contents/Resources"

echo "🔨 Building ${APP_NAME}..."

# Clean previous build
rm -rf "${BUILD_DIR}"
mkdir -p "${BIN_DIR}"
mkdir -p "${RES_DIR}"

# Compile Swift file
# -O for optimization
# target arm64 (Apple Silicon)
swiftc -parse-as-library -O -target arm64-apple-macos13.0 "${SRC_FILE}" -o "${BIN_DIR}/${APP_NAME}"

# Create basic Info.plist
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
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSUIElement</key>
    <true/> <!-- Hides from Dock, Menu Bar app only -->
    <key>NSSpeechRecognitionUsageDescription</key>
    <string>TalkType needs speech recognition to transcribe your voice.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>TalkType needs microphone access to hear you speak.</string>
</dict>
</plist>
PLIST

# Copy assets (ghost mark, rendered from the web app's talktype-icon.svg)
cp Assets/*.png "${RES_DIR}/" 2>/dev/null

# Make executable
chmod +x "${BIN_DIR}/${APP_NAME}"

# Sign with the Developer ID if it is in the keychain, ad-hoc otherwise.
#
# This is not cosmetic. TCC (mic / speech / accessibility) remembers an app by its
# DESIGNATED REQUIREMENT. Ad-hoc signing produces `designated => cdhash H"..."` — a raw
# hash of the binary — so every single rebuild looks like a brand new app and macOS
# re-prompts for everything. A Developer ID gives `identifier "..." and ... subject.OU`,
# which is stable across rebuilds, so the grants stick.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
           | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/')

if [ -n "${IDENTITY}" ]; then
    codesign --force --sign "${IDENTITY}" --identifier com.pibulus.talktype \
             --timestamp=none "${APP_DIR}" 2>/dev/null \
      && echo "🔏 Signed: ${IDENTITY}"
else
    codesign --force --sign - --identifier com.pibulus.talktype "${APP_DIR}" 2>/dev/null \
      && echo "🔏 Ad-hoc signed (no Developer ID — TCC will re-prompt on every rebuild)"
fi

echo "✨ Built at ${APP_DIR}"
echo "🚀 Run with: open ${APP_DIR}"
