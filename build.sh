#!/bin/bash
set -e

# Define directories
APP_NAME="HammerTime"
APP_DIR="${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MAC_OS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
FRAMEWORKS_DIR="${CONTENTS_DIR}/Frameworks"

echo "Building ${APP_NAME}..."

# Create the bundle structure
mkdir -p "${MAC_OS_DIR}"
mkdir -p "${RESOURCES_DIR}"
mkdir -p "${FRAMEWORKS_DIR}"

# Find SDK path
SDK_PATH=$(xcrun --show-sdk-path)
echo "Using SDK: ${SDK_PATH}"

# Compile all Swift files in src/ linking against Sparkle
echo "Compiling Swift source files..."
swiftc \
  -sdk "${SDK_PATH}" \
  -framework Cocoa \
  -framework SwiftUI \
  -framework AVFoundation \
  -framework IOKit \
  -F Frameworks \
  -framework Sparkle \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -o "${MAC_OS_DIR}/${APP_NAME}" \
  src/*.swift

# Copy Info.plist
echo "Copying Info.plist..."
cp Info.plist "${CONTENTS_DIR}/Info.plist"

# Copy AppIcon.icns
if [ -f "Resources/AppIcon.icns" ]; then
  echo "Copying AppIcon.icns..."
  cp "Resources/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
fi

# Copy Sparkle.framework into bundle
if [ -d "Frameworks/Sparkle.framework" ]; then
  echo "Copying Sparkle.framework..."
  cp -R "Frameworks/Sparkle.framework" "${FRAMEWORKS_DIR}/"
else
  echo "⚠️ WARNING: Frameworks/Sparkle.framework not found!"
fi

# Find signing identity dynamically
SIGNING_IDENTITY=$(security find-identity -p codesigning -v | grep "Developer ID Application" | head -n 1 | awk -F '"' '{print $2}')

if [ -z "${SIGNING_IDENTITY}" ]; then
  SIGNING_IDENTITY=$(security find-identity -p codesigning -v | grep "Apple Development" | head -n 1 | awk -F '"' '{print $2}')
fi

if [ -z "${SIGNING_IDENTITY}" ]; then
  SIGNING_IDENTITY="-"
  echo "No Apple Developer certificates found in Keychain. Using ad-hoc signing..."
else
  echo "Found signing certificate: ${SIGNING_IDENTITY}"
fi

# Code sign the embedded Sparkle framework first
if [ -d "${FRAMEWORKS_DIR}/Sparkle.framework" ]; then
  echo "Applying code signature to Sparkle.framework using: ${SIGNING_IDENTITY}..."
  codesign --force --sign "${SIGNING_IDENTITY}" "${FRAMEWORKS_DIR}/Sparkle.framework"
fi

# Code sign the outer app bundle with Hardened Runtime enabled (mandatory for notarization)
echo "Applying code signature using: ${SIGNING_IDENTITY}..."
codesign --force --deep --options runtime --entitlements HammerTime.entitlements --sign "${SIGNING_IDENTITY}" "${APP_DIR}"

echo "${APP_NAME}.app built successfully!"

if [ "$1" == "--install" ] || [ "$1" == "-i" ]; then
  echo "Installing to /Applications..."
  killall "${APP_NAME}" 2>/dev/null || true
  rm -rf "/Applications/${APP_DIR}"
  cp -R "${APP_DIR}" "/Applications/"
  echo "Opening ${APP_NAME}..."
  open "/Applications/${APP_DIR}"
fi
