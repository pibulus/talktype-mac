#!/bin/bash
set -e

# TalkType Screenshot & Asset Generator
# Conforms to Pablo's WORKFLOW-screenshot-standards.md & Apple Mac App Store specs

OUT_DIR="screenshots"
mkdir -p "${OUT_DIR}"

RAW_SHOT="${OUT_DIR}/raw_capture.png"

if [ -n "$1" ] && [ -f "$1" ]; then
    echo "📸 Using provided image: $1"
    cp "$1" "${RAW_SHOT}"
else
    echo "📸 TalkType Screenshot Capture Tool"
    echo "Select what you want to do:"
    echo "  1) Capture screen interactively (click window or drag region)"
    echo "  2) Capture entire main display after 3s delay"
    echo "  3) Process existing image (${RAW_SHOT})"
    read -p "Choice [1-3]: " CHOICE

    case "$CHOICE" in
        1)
            echo "👉 Click on the TalkType popover or HUD window..."
            screencapture -i "${RAW_SHOT}"
            ;;
        2)
            echo "⏳ Waiting 3 seconds... open the TalkType menu or hold Option!"
            sleep 3
            screencapture -m "${RAW_SHOT}"
            ;;
        3)
            if [ ! -f "${RAW_SHOT}" ]; then
                echo "❌ File ${RAW_SHOT} does not exist. Please capture one first."
                exit 1
            fi
            ;;
        *)
            echo "Invalid choice."
            exit 1
    esac
fi

if [ ! -f "${RAW_SHOT}" ]; then
    echo "❌ Capture cancelled or file not found."
    exit 1
fi

echo "✨ Processing screenshot presets with ImageMagick..."

# Check dimensions of the input
IMG_W=$(magick identify -format "%w" "${RAW_SHOT}")
IMG_H=$(magick identify -format "%h" "${RAW_SHOT}")

# 1. Mac App Store (16:10 Retina 2880x1800)
# If it's a window crop (e.g. popover card), present it on a clean Soft Neo Toybrut canvas with soft shadow
if [ "$IMG_W" -lt 1600 ]; then
    echo "🎨 Compositing window card onto 2880x1800 App Store presentation canvas..."
    magick -size 2880x1800 xc:"#FFF8F2" \
      \( "${RAW_SHOT}" -resize 1200x \
         \( +clone -background "#403038" -shadow 35x15+0+18 \) \
         +swap -background none -layers merge +repage \) \
      -gravity center -composite \
      -modulate 100,108,100 \
      -brightness-contrast 0x4 \
      -quality 95 \
      -set comment "TalkType for Mac - App Store" \
      -set copyright "© Pablo Alvarado" \
      "${OUT_DIR}/appstore-2880x1800.png"
else
    magick "${RAW_SHOT}" \
      -resize 2880x1800^ -gravity center -extent 2880x1800 \
      -modulate 100,110,100 \
      -brightness-contrast 0x5 \
      -quality 92 \
      -set comment "TalkType for Mac - App Store" \
      -set copyright "© Pablo Alvarado" \
      "${OUT_DIR}/appstore-2880x1800.png"
fi

# 2. README / Open Graph Hero (1200x, aspect preserved)
magick "${RAW_SHOT}" \
  -resize 1200x \
  -modulate 100,110,100 \
  -brightness-contrast 0x5 \
  -quality 85 \
  -set comment "Project: TalkType" \
  -set copyright "© Pablo Alvarado" \
  "${OUT_DIR}/hero-readme.jpg"

# 3. Twitter / X Announcement (1200x, aspect preserved)
magick "${RAW_SHOT}" \
  -resize 1200x \
  -modulate 100,110,100 \
  -brightness-contrast 0x5 \
  -quality 85 \
  -set comment "Project: TalkType" \
  -set copyright "© Pablo Alvarado" \
  "${OUT_DIR}/twitter-1200x.jpg"

# 4. Instagram Feed (1080x1080 presentation canvas)
magick -size 1080x1080 xc:"#FFF8F2" \
  \( "${RAW_SHOT}" -resize 720x \
     \( +clone -background "#403038" -shadow 30x10+0+12 \) \
     +swap -background none -layers merge +repage \) \
  -gravity center -composite \
  -modulate 100,108,100 \
  -brightness-contrast 0x4 \
  -quality 85 \
  -set comment "Project: TalkType" \
  -set copyright "© Pablo Alvarado" \
  "${OUT_DIR}/instagram-square.jpg"

echo "✅ Generated all presets in ${OUT_DIR}/:"
ls -lh "${OUT_DIR}/"
