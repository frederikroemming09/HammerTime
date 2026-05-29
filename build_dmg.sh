#!/bin/bash
set -e

APP_NAME="HammerTime"
DMG_TEMP_NAME="HammerTime_temp.dmg"
DMG_FINAL_NAME="HammerTime.dmg"
VOLUME_NAME="HammerTime"
MOUNT_PATH="/Volumes/${VOLUME_NAME}"

# Clean up previous attempts
rm -f "${DMG_TEMP_NAME}" "${DMG_FINAL_NAME}"
if [ -d "${MOUNT_PATH}" ]; then
  echo "Detaching existing volume..."
  hdiutil detach "${MOUNT_PATH}" || true
fi

echo "Resizing background image..."
sips -s format png -z 600 600 "Resources/dmg_background_v2.png" --out "dmg_background.png"
sips -s dpiWidth 72.0 -s dpiHeight 72.0 "dmg_background.png" > /dev/null

sips -s format png -z 1200 1200 "Resources/dmg_background_v2.png" --out "dmg_background@2x.png"
sips -s dpiWidth 144.0 -s dpiHeight 144.0 "dmg_background@2x.png" > /dev/null

tiffutil -cathidpicheck dmg_background.png dmg_background@2x.png -out dmg_background.tiff

echo "Creating raw DMG image..."
hdiutil create -size 50m -fs HFS+ -volname "${VOLUME_NAME}" -ov "${DMG_TEMP_NAME}"

echo "Mounting DMG image..."
hdiutil attach "${DMG_TEMP_NAME}"
sleep 2

echo "Copying application and link..."
cp -R "${APP_NAME}.app" "${MOUNT_PATH}/"
ln -s /Applications "${MOUNT_PATH}/Applications"

echo "Copying background image..."
mkdir -p "${MOUNT_PATH}/.background"
cp dmg_background.tiff "${MOUNT_PATH}/.background/background.tiff"

echo "Customizing Finder layout via AppleScript..."
osascript <<EOF
tell application "Finder"
    tell disk "${VOLUME_NAME}"
        open
        delay 2
        set current view of container window to icon view
        set containerWindow to container window
        set arrangement of icon view options of containerWindow to not arranged
        set icon size of icon view options of containerWindow to 128
        set background picture of icon view options of containerWindow to file ".background:background.tiff"
        
        # Position icons
        set position of item "${APP_NAME}.app" of containerWindow to {142, 298}
        set position of item "Applications" of containerWindow to {454, 298}
        
        # Set bounds of the Finder window {left, top, right, bottom}
        set bounds of containerWindow to {100, 100, 700, 700}
        
        update without registering applications
        delay 2
        close
    end tell
end tell
EOF

echo "Finalizing volume attributes..."
chmod -Rf go-w "${MOUNT_PATH}" || true

echo "Unmounting DMG..."
hdiutil detach "${MOUNT_PATH}"

echo "Converting to compressed read-only DMG..."
hdiutil convert "${DMG_TEMP_NAME}" -format UDZO -imagekey zlib-level=9 -o "${DMG_FINAL_NAME}"

# Clean up temporary build artifacts
rm -f "${DMG_TEMP_NAME}" dmg_background.png dmg_background@2x.png dmg_background.tiff

echo "DMG built successfully: ${DMG_FINAL_NAME}"

# Find signing identity dynamically
SIGNING_IDENTITY=$(security find-identity -p codesigning -v | grep "Developer ID Application" | head -n 1 | awk -F '"' '{print $2}')
if [ -z "${SIGNING_IDENTITY}" ]; then
  SIGNING_IDENTITY=$(security find-identity -p codesigning -v | grep "Apple Development" | head -n 1 | awk -F '"' '{print $2}')
fi

# Code sign the DMG container
if [ -n "${SIGNING_IDENTITY}" ] && [ "${SIGNING_IDENTITY}" != "-" ]; then
  echo "Signing DMG container using certificate: ${SIGNING_IDENTITY}..."
  codesign --force --sign "${SIGNING_IDENTITY}" "${DMG_FINAL_NAME}"
else
  echo "No developer certificate found. Skipping DMG container signing..."
fi

# Notarization and Stapling
if [ "$1" == "--notarize" ] || [ "$2" == "--notarize" ]; then
  echo "Starting Apple Notarization process..."
  
  # Check if a keychain profile exists, otherwise print instructions
  if ! xcrun notarytool submit "${DMG_FINAL_NAME}" --keychain-profile "HammerTimeNotaryProfile" --wait; then
    echo ""
    echo "========================================================================="
    echo "❌ NOTARIZATION FAILED"
    echo "========================================================================="
    echo "You must save your Apple Developer credentials in the Keychain first."
    echo "Please perform the following steps:"
    echo "1. Go to https://appleid.apple.com and generate an 'App-Specific Password'."
    echo "2. Run this command to save your credentials to the Keychain:"
    echo "   xcrun notarytool store-credentials \"HammerTimeNotaryProfile\" \\"
    echo "     --apple-id \"frederikpedersen0907@gmail.com\" \\"
    echo "     --team-id \"QZF9WNAF2C\" \\"
    echo "     --password \"<your-app-specific-password>\""
    echo "3. Re-run this script with the --notarize flag."
    echo "========================================================================="
    exit 1
  fi
  
  echo "Stapling notarization ticket to ${DMG_FINAL_NAME}..."
  xcrun stapler staple "${DMG_FINAL_NAME}"
  echo "Notarization and stapling completed successfully!"
fi
