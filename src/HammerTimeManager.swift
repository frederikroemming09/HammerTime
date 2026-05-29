import Cocoa
import AVFoundation
import SwiftUI
import Carbon
import LocalAuthentication

class HammerTimeManager: NSObject {
    static let shared = HammerTimeManager()
    
    private(set) var isLocked = false
    private(set) var isDeterrentOverlayVisible = false
    private var isCapturingPhoto = false
    
    private var sleepAssertionToken: NSObjectProtocol?
    private var isSleepPrevented = false
    
    private let keyphraseKey = "HammerTimeSecretKeyphrase"
    private let biometricsEnabledKey = "HammerTimeBiometricsEnabled"
    private var isAuthenticatingWithBiometrics = false
    
    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private let shortcutEnabledKey = "HammerTimeShortcutEnabled"
    
    var appDelegate: AppDelegate? {
        return NSApplication.shared.delegate as? AppDelegate
    }
    
    // Check if keyphrase is set
    func hasKeyphrase() -> Bool {
        return true
    }
    
    func getKeyphrase() -> String {
        if let val = UserDefaults.standard.string(forKey: keyphraseKey) {
            return val.isEmpty ? "hammertime" : val
        }
        // Write the default keyphrase on first launch
        UserDefaults.standard.set("hammertime", forKey: keyphraseKey)
        return "hammertime"
    }
    
    func setKeyphrase(_ phrase: String) {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(trimmed, forKey: keyphraseKey)
        print("[Manager] Keyphrase updated successfully.")
    }
    
    var isBiometricsEnabled: Bool {
        if UserDefaults.standard.object(forKey: biometricsEnabledKey) == nil {
            UserDefaults.standard.set(false, forKey: biometricsEnabledKey)
            return false
        }
        return UserDefaults.standard.bool(forKey: biometricsEnabledKey)
    }
    
    func setBiometricsEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: biometricsEnabledKey)
        print("[Manager] Biometrics enabled state set to: \(enabled)")
    }
    
    func canUseBiometrics() -> Bool {
        let context = LAContext()
        return context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }
    
    func toggleLock() {
        if isLocked {
            deactivateLock()
        } else {
            activateLock()
        }
    }
    
    func verifyAndPromptPermissions() -> Bool {
        let accessibilityGranted = checkAccessibilityPermission()
        
        let cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let cameraAvailable = CameraManager.shared.isCameraAvailable
        
        var missingAccessibility = false
        var missingCamera = false
        var cameraDenied = false
        
        if !accessibilityGranted {
            missingAccessibility = true
        }
        
        if cameraAvailable {
            if cameraStatus == .notDetermined {
                missingCamera = true
            } else if cameraStatus == .denied || cameraStatus == .restricted {
                cameraDenied = true
            }
        }
        
        if missingAccessibility || missingCamera || cameraDenied {
            DispatchQueue.main.async {
                self.appDelegate?.showPreferencesWindow()
                
                let alert = NSAlert()
                alert.alertStyle = .warning
                
                if missingAccessibility && (missingCamera || cameraDenied) {
                    alert.messageText = "Permissions Required"
                    alert.informativeText = "HammerTime requires Accessibility and Camera permissions to secure your Mac and snap intruder photos. Please grant access in the system dialogs."
                    alert.addButton(withTitle: "Request Permissions")
                    alert.addButton(withTitle: "Cancel")
                    
                    let response = alert.runModal()
                    if response == .alertFirstButtonReturn {
                        self.promptAccessibilityPermission()
                        if missingCamera {
                            CameraManager.shared.checkPermission { _ in }
                        }
                    }
                } else if missingAccessibility {
                    alert.messageText = "Accessibility Permission Required"
                    alert.informativeText = "HammerTime requires Accessibility permissions to swallow input and secure your Mac. Please enable it in the system settings."
                    alert.addButton(withTitle: "Open Settings")
                    alert.addButton(withTitle: "Cancel")
                    
                    let response = alert.runModal()
                    if response == .alertFirstButtonReturn {
                        self.promptAccessibilityPermission()
                    }
                } else if missingCamera {
                    alert.messageText = "Camera Permission Required"
                    alert.informativeText = "HammerTime requires Camera access to capture photos of intruders. Please grant access."
                    alert.addButton(withTitle: "Request Access")
                    alert.addButton(withTitle: "Cancel")
                    
                    let response = alert.runModal()
                    if response == .alertFirstButtonReturn {
                        CameraManager.shared.checkPermission { _ in }
                    }
                } else if cameraDenied {
                    alert.messageText = "Camera Access Denied"
                    alert.informativeText = "Camera access was previously denied. Please enable Camera permissions for HammerTime in System Settings -> Privacy & Security -> Camera."
                    alert.addButton(withTitle: "Open Privacy Settings")
                    alert.addButton(withTitle: "Cancel")
                    
                    let response = alert.runModal()
                    if response == .alertFirstButtonReturn {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            }
            return false
        }
        
        return true
    }
    
    func activateLock() {
        guard !isLocked else { return }
        
        // Safeguard 1: Do not lock if keyphrase is not set
        let phrase = getKeyphrase()
        if phrase.isEmpty {
            print("[Manager] No secret keyphrase set. Aborting lock and showing preferences.")
            DispatchQueue.main.async {
                self.appDelegate?.showPreferencesWindow()
                
                // Show an alert to warn the user
                let alert = NSAlert()
                alert.messageText = "Secret Keyphrase Required"
                alert.informativeText = "Please define a Secret Keyphrase in Preferences before activating the Invisible Lock to avoid locking yourself out."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
            return
        }
        
        // Safeguard 2: Verify and prompt for missing system permissions
        guard verifyAndPromptPermissions() else {
            print("[Manager] Activating lock aborted due to missing permissions.")
            return
        }
        
        print("[Manager] Activating Invisible Lock...")
        isLocked = true
        isDeterrentOverlayVisible = false
        isCapturingPhoto = false
        
        // Assert sleep prevention (prevent display and system sleep)
        preventSleep()
        
        // Start CGEventTap input swallowing
        EventTapManager.shared.start()
        
        // Trigger hammer emoji confetti animation on main screen
        appDelegate?.showActivationConfetti()
        
        // Update menu bar icon
        appDelegate?.updateStatusItem()
    }
    
    func deactivateLock() {
        guard isLocked else { return }
        
        print("[Manager] Deactivating Invisible Lock...")
        isLocked = false
        isDeterrentOverlayVisible = false
        isCapturingPhoto = false
        
        // Stop CGEventTap input swallowing
        EventTapManager.shared.stop()
        
        // Release sleep prevention assertions
        allowSleep()
        
        // Close overlay window
        appDelegate?.closeDeterrentOverlay()
        
        // Update menu bar icon
        appDelegate?.updateStatusItem()
        
        // Play an subtle unlock sound
        NSSound(named: "Glass")?.play()
    }
    
    func triggerTouchID(completion: ((Bool) -> Void)? = nil) {
        guard isLocked else {
            completion?(false)
            return
        }
        
        guard canUseBiometrics() && isBiometricsEnabled else {
            completion?(false)
            return
        }
        
        guard !isAuthenticatingWithBiometrics else {
            completion?(false)
            return
        }
        
        print("[Manager] Triggering biometric/password authentication. Temporarily suspending event tap...")
        isAuthenticatingWithBiometrics = true
        
        // Stop event tap so the user can interact with the Touch ID dialog / password input
        EventTapManager.shared.stop()
        
        // Lower deterrent window level to let Touch ID prompt display on top of it
        self.appDelegate?.setDeterrentWindowsLevel(.floating)
        
        let context = LAContext()
        let reason = "Unlock HammerTime"
        
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { [weak self] success, error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isAuthenticatingWithBiometrics = false
                
                // Restore deterrent window level to .screenSaver to keep screen covered
                self.appDelegate?.setDeterrentWindowsLevel(.screenSaver)
                
                if success {
                    print("[Manager] Biometric/Password authentication succeeded. Unlocking HammerTime.")
                    self.deactivateLock()
                    completion?(true)
                } else {
                    print("[Manager] Biometric/Password authentication failed or was canceled. Error: \(String(describing: error)). Re-enabling event tap.")
                    // Re-enable event tap if we are still locked
                    if self.isLocked {
                        EventTapManager.shared.start()
                    }
                    completion?(false)
                }
            }
        }
    }
    
    func captureIntruder(reason: String) {
        guard isLocked && !isDeterrentOverlayVisible && !isCapturingPhoto else { return }
        print("[Manager] Intruder captured! Reason: \(reason)")
        isCapturingPhoto = true
        
        // Play warning sound
        NSSound(named: "Basso")?.play()
        
        // Capture photo and display overlay
        CameraManager.shared.capturePhoto { [weak self] image in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isCapturingPhoto = false
                self.isDeterrentOverlayVisible = true
                
                // Add entry to our history log
                self.addHistoryEntry(reason: reason, image: image)
                
                // Save the warning card image (with graphics and captured photo) to the Desktop
                self.saveImageToDesktop(cameraImage: image)
                
                // Display full-screen overlay (even if photo is nil, we display a fallback UI)
                self.appDelegate?.showDeterrentOverlay(image: image)
            }
        }
    }
    
    private func saveImageToDesktop(cameraImage: NSImage?) {
        // Create the warning card view without the unlock instructions
        let cardWidth: CGFloat = 500
        let cardHeight: CGFloat = 500
        let scale: CGFloat = 3.0 // 3x high-resolution rendering
        
        let cardView = DeterrentCardView(image: cameraImage, showUnlockInstructions: false)
            .frame(width: cardWidth, height: cardHeight)
        
        let hostingView = NSHostingView(rootView: cardView)
        hostingView.frame = NSRect(x: 0, y: 0, width: cardWidth, height: cardHeight)
        
        // Force layout pass
        hostingView.layoutSubtreeIfNeeded()
        
        // Create high-resolution bitmap representation
        guard let representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(cardWidth * scale),
            pixelsHigh: Int(cardHeight * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            print("[Manager] Failed to create high-res bitmap image rep for card view")
            return
        }
        
        representation.size = NSSize(width: cardWidth, height: cardHeight)
        
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)
        
        // Get PNG representation to preserve transparency and rounded corners
        guard let pngData = representation.representation(using: .png, properties: [:]) else {
            print("[Manager] Failed to convert rendered card to PNG data")
            return
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dateString = formatter.string(from: Date())
        let fileName = "HammerTime_Intruder_\(dateString).png"
        
        guard let desktopURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first else {
            print("[Manager] Failed to find Desktop directory")
            return
        }
        
        let fileURL = desktopURL.appendingPathComponent(fileName)
        
        do {
            try pngData.write(to: fileURL)
            print("[Manager] Saved high-res intruder card image to desktop: \(fileURL.path)")
        } catch {
            print("[Manager] Failed to write card image data to Desktop: \(error.localizedDescription)")
        }
    }
    
    // Sleep Prevention (Caffeine feature) using Foundation ProcessInfo Activity
    private func preventSleep() {
        guard !isSleepPrevented else { return }
        
        let options: ProcessInfo.ActivityOptions = [.idleDisplaySleepDisabled, .idleSystemSleepDisabled, .suddenTerminationDisabled]
        sleepAssertionToken = ProcessInfo.processInfo.beginActivity(
            options: options,
            reason: "HammerTime Invisible Lock Active"
        )
        
        isSleepPrevented = true
        print("[Manager] Sleep prevention assertion created successfully via ProcessInfo.")
    }
    
    private func allowSleep() {
        guard isSleepPrevented else { return }
        
        if let token = sleepAssertionToken {
            ProcessInfo.processInfo.endActivity(token)
            sleepAssertionToken = nil
        }
        
        isSleepPrevented = false
        print("[Manager] Sleep prevention assertion released.")
    }
    
    // Permissions Checks
    func checkAccessibilityPermission() -> Bool {
        return AXIsProcessTrusted()
    }
    
    func promptAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as NSObject: true as AnyObject] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    
    // Shortcut configuration
    var isShortcutEnabled: Bool {
        if UserDefaults.standard.object(forKey: shortcutEnabledKey) == nil {
            UserDefaults.standard.set(true, forKey: shortcutEnabledKey)
            return true
        }
        return UserDefaults.standard.bool(forKey: shortcutEnabledKey)
    }
    
    func setShortcutEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: shortcutEnabledKey)
        if enabled {
            registerGlobalShortcut()
        } else {
            unregisterGlobalShortcut()
        }
    }
    
    func registerGlobalShortcut() {
        unregisterGlobalShortcut()
        
        let hotKeyID = EventHotKeyID(signature: OSType(1213486157), id: 1) // "HMTM"
        
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        
        let handler: EventHandlerUPP = { (nextHandler, event, userData) -> OSStatus in
            DispatchQueue.main.async {
                HammerTimeManager.shared.activateLock()
            }
            return noErr
        }
        
        var installedHandler: EventHandlerRef?
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            nil,
            &installedHandler
        )
        
        if status == noErr {
            self.hotKeyHandler = installedHandler
        } else {
            print("[Manager] Failed to install event handler: \(status)")
        }
        
        var registeredRef: EventHotKeyRef?
        let regStatus = RegisterEventHotKey(
            UInt32(4), // 'H' key code is 4
            UInt32(cmdKey | optionKey | controlKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &registeredRef
        )
        
        if regStatus == noErr {
            self.hotKeyRef = registeredRef
            print("[Manager] Global shortcut (⌃⌥⌘H) registered successfully.")
        } else {
            print("[Manager] Failed to register hotkey: \(regStatus)")
        }
    }
    
    func unregisterGlobalShortcut() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = hotKeyHandler {
            RemoveEventHandler(handler)
            hotKeyHandler = nil
        }
        print("[Manager] Global shortcut unregistered.")
    }
    
    // MARK: - History Management
    
    func getHistoryDirectory() -> URL {
        let fileManager = FileManager.default
        guard let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return fileManager.temporaryDirectory.appendingPathComponent("HammerTime/History")
        }
        let historyURL = appSupportURL.appendingPathComponent("HammerTime/History", isDirectory: true)
        
        if !fileManager.fileExists(atPath: historyURL.path) {
            try? fileManager.createDirectory(at: historyURL, withIntermediateDirectories: true, attributes: nil)
        }
        return historyURL
    }
    
    func loadHistory() -> [HistoryEntry] {
        let historyDir = getHistoryDirectory()
        let fileURL = historyDir.appendingPathComponent("history.json")
        
        guard let data = try? Data(contentsOf: fileURL) else {
            return []
        }
        
        let decoder = JSONDecoder()
        if let entries = try? decoder.decode([HistoryEntry].self, from: data) {
            return entries.sorted(by: { $0.date > $1.date })
        }
        return []
    }
    
    func saveHistoryEntries(_ entries: [HistoryEntry]) {
        let historyDir = getHistoryDirectory()
        let fileURL = historyDir.appendingPathComponent("history.json")
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(entries) {
            try? data.write(to: fileURL)
        }
    }
    
    func addHistoryEntry(reason: String, image: NSImage?) {
        var entries = loadHistory()
        let id = UUID()
        var filename: String? = nil
        
        if let img = image {
            let historyDir = getHistoryDirectory()
            let fn = "intruder_\(id.uuidString).png"
            filename = fn
            let fileURL = historyDir.appendingPathComponent(fn)
            
            if let tiffData = img.tiffRepresentation,
               let bitmap = NSBitmapImageRep(data: tiffData),
               let pngData = bitmap.representation(using: .png, properties: [:]) {
                try? pngData.write(to: fileURL)
            }
        }
        
        let newEntry = HistoryEntry(id: id, date: Date(), reason: reason, photoFilename: filename)
        entries.append(newEntry)
        saveHistoryEntries(entries)
        print("[Manager] Added history entry for reason: \(reason)")
    }
    
    func getHistoryImage(filename: String) -> NSImage? {
        let historyDir = getHistoryDirectory()
        let fileURL = historyDir.appendingPathComponent(filename)
        return NSImage(contentsOf: fileURL)
    }
    
    func deleteHistoryEntry(id: UUID) {
        var entries = loadHistory()
        if let index = entries.firstIndex(where: { $0.id == id }) {
            let entry = entries[index]
            if let filename = entry.photoFilename {
                let historyDir = getHistoryDirectory()
                let fileURL = historyDir.appendingPathComponent(filename)
                try? FileManager.default.removeItem(at: fileURL)
            }
            entries.remove(at: index)
            saveHistoryEntries(entries)
            print("[Manager] Deleted history entry: \(id)")
        }
    }
    
    func clearHistory() {
        let historyDir = getHistoryDirectory()
        let entries = loadHistory()
        
        for entry in entries {
            if let filename = entry.photoFilename {
                let fileURL = historyDir.appendingPathComponent(filename)
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        
        let fileURL = historyDir.appendingPathComponent("history.json")
        try? FileManager.default.removeItem(at: fileURL)
        print("[Manager] Cleared all history entries.")
    }
}

struct HistoryEntry: Codable, Identifiable {
    let id: UUID
    let date: Date
    let reason: String
    let photoFilename: String?
}
