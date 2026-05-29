# HammerTime Distribution & Update Guide

This guide explains how to compile, sign, notarize, and publish updates for the HammerTime macOS application using GitHub Releases and the Sparkle Auto-Update framework.

---

## One-Time Requirements
Make sure the following are set up on your Mac before proceeding:
1. **Notarization Profile**: Stored in your Mac's Keychain under the profile name `"HammerTimeNotaryProfile"`.
   * Verified Command: `xcrun notarytool store-credentials "HammerTimeNotaryProfile" --apple-id "frederikpedersen0907@gmail.com" --team-id "25KM2AB3Y2" --password "your-app-specific-password"`
2. **Signing Certificate**: The certificate `Developer ID Application: Michael Jensen (25KM2AB3Y2)` must be installed in your Mac's **login** Keychain.

---

## How to Release an Update (Step-by-Step)

### Step 1: Bump the Version Numbers
Before compiling a new update, you must increment the version numbers.
1. Open the [Info.plist](file:///Users/frederikroemming/Documents/antigravity/delightful-meitner/Info.plist) file.
2. Update the following keys:
   * `CFBundleShortVersionString`: The user-facing version (e.g., `1.1`).
   * `CFBundleVersion`: The internal build number (integer). Increment this by 1 (e.g., `2`).

---

### Step 2: Build & Notarize the DMG
1. Open your terminal in the project directory.
2. Build and sign the application bundle:
   ```bash
   ./build.sh
   ```
3. Build, sign, and notarize the DMG installer:
   ```bash
   ./build_dmg.sh --notarize
   ```
   *This command will bundle the app, codesign it, upload it to Apple for malware checking, wait for approval, and attach the approval ticket ("staple" it) to the resulting `HammerTime.dmg` file.*

4. Note down the **file size of the newly built `HammerTime.dmg` in bytes** (the script will print this value in the terminal when it completes, e.g., `length="4790992"`).

---

### Step 3: Create the GitHub Release
1. Go to your GitHub repository: `frederikroemming09/HammerTime`.
2. On the right sidebar, click **Releases** > **Draft a new release**.
3. **Choose a tag**: Type `v1.1.0` (matching your new version, e.g., `v1.1.0`). Click **Create new tag**.
4. **Release title**: Type `HammerTime 1.1.0`.
5. Drag and drop the notarized `HammerTime.dmg` file from your project folder into the release box.
6. Click **Publish release**.
7. Right-click the uploaded `HammerTime.dmg` in the assets list and copy the link. It should look like:
   `https://github.com/frederikroemming09/HammerTime/releases/download/v1.1.0/HammerTime.dmg`

---

### Step 4: Update the Sparkle Feed (`appcast.xml`)
To tell currently installed apps that a new update is available, edit the update feed file.
1. Open the `appcast.xml` file in your GitHub repository.
2. Edit the file to add a new `<item>` section **at the top** of the channel (above the previous version).
3. Update the values in the new item:
   * `<title>`: E.g., `Version 1.1`.
   * `<pubDate>`: The current date and time (standard RSS format, e.g., `Fri, 29 May 2026 12:00:00 +0200`).
   * `<enclosure>`: Update the `url` to the new GitHub Release download link, set `sparkle:version` to the new build number, set `sparkle:shortVersionString` to the new user-facing version, and set `length` to the file size in bytes you noted down in Step 2.
4. Save (commit) the changes to the `appcast.xml` file on GitHub.

#### Example `appcast.xml` with two versions:
```xml
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
    <channel>
        <title>HammerTime Updates</title>
        <link>https://raw.githubusercontent.com/frederikroemming09/HammerTime/refs/heads/main/appcast.xml</link>
        <description>Most recent updates for HammerTime.</description>
        <language>en</language>
        
        <!-- NEW VERSION 1.1 -->
        <item>
            <title>Version 1.1</title>
            <sparkle:releaseNotesLink>https://github.com/frederikroemming09/HammerTime/releases</sparkle:releaseNotesLink>
            <pubDate>Sat, 30 May 2026 14:00:00 +0200</pubDate>
            <enclosure url="https://github.com/frederikroemming09/HammerTime/releases/download/v1.1.0/HammerTime.dmg"
                       sparkle:version="2"
                       sparkle:shortVersionString="1.1"
                       length="4791550"
                       type="application/octet-stream" />
        </item>

        <!-- PREVIOUS VERSION 1.0 -->
        <item>
            <title>Version 1.0</title>
            <sparkle:releaseNotesLink>https://github.com/frederikroemming09/HammerTime/releases</sparkle:releaseNotesLink>
            <pubDate>Fri, 29 May 2026 12:00:00 +0200</pubDate>
            <enclosure url="https://github.com/frederikroemming09/HammerTime/releases/download/v1.0.0/HammerTime.dmg"
                       sparkle:version="1"
                       sparkle:shortVersionString="1.0"
                       length="4790992"
                       type="application/octet-stream" />
        </item>
    </channel>
</rss>
```

---

## Verification
To verify that everything is working:
1. Launch HammerTime on your Mac.
2. Click the Hammer icon in the menu bar and select **Check for Updates...**.
3. If no updates are available, it will say "You're up to date!". If a new version was published in the feed, it will show the native Sparkle update popup prompting you to install it.
