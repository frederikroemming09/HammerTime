import Cocoa
import SwiftUI
import Sparkle

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var preferencesWindow: NSWindow?
    private var deterrentWindows: [NSWindow] = []
    private var confettiWindow: NSWindow?
    private var updaterController: SPUStandardUpdaterController!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Create standard main menu to enable Edit shortcuts like Cmd+A, Cmd+C, Cmd+V
        setupMainMenu()
        
        // Initialize Sparkle Auto-Updater
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        
        // Create Menu Bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusItem()
        
        // Register URL Scheme handler
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        
        // Register Global Shortcut
        HammerTimeManager.shared.registerGlobalShortcut()
        
        // Automatically open preferences window on launch so the user knows it is running
        showPreferencesWindow()
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPreferencesWindow()
        return true
    }
    
    private func setupMainMenu() {
        let mainMenu = NSMenu()
        
        // App Menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About HammerTime", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Quit HammerTime", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        
        // Edit Menu (critical for keyboard editing shortcuts)
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        
        NSApp.mainMenu = mainMenu
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Ensure sleep assertions and event taps are cleaned up
        HammerTimeManager.shared.deactivateLock()
        HammerTimeManager.shared.unregisterGlobalShortcut()
    }
    
    // Update Menu Bar Icon & Menu
    func updateStatusItem() {
        guard let button = statusItem.button else { return }
        
        let isLocked = HammerTimeManager.shared.isLocked
        
        // Icon configuration - use outline for unlocked, filled for locked
        let iconName = isLocked ? "hammer.fill" : "hammer"
        print("[AppDelegate] Updating menu bar status item. Locked: \(isLocked), Icon: \(iconName)")
        
        if let image = NSImage(systemSymbolName: iconName, accessibilityDescription: "HammerTime Lock Status") {
            image.isTemplate = true // Allows automatic matching of light/dark menu bar
            button.image = image
            button.title = ""
            print("[AppDelegate] Loaded SF Symbol image successfully.")
        } else {
            // Fallback to emoji if SF Symbol fails to load for any reason
            button.image = nil
            button.title = "🔨"
            print("[AppDelegate] WARNING: Failed to load SF Symbol. Falling back to emoji title.")
        }
        
        // Keep icon fully visible always (100% opacity) so it doesn't get lost in the menu bar
        button.alphaValue = 1.0
        
        // Create Dropdown Menu
        let menu = NSMenu()
        
        let toggleTitle = isLocked ? "Deactivate" : "Activate"
        let toggleMenuItem = NSMenuItem(title: toggleTitle, action: #selector(toggleLockAction), keyEquivalent: "")
        menu.addItem(toggleMenuItem)
        
        let settingsMenuItem = NSMenuItem(title: "Settings", action: #selector(showPreferencesAction), keyEquivalent: ",")
        menu.addItem(settingsMenuItem)
        
        let updateMenuItem = NSMenuItem(title: "Check for Updates...", action: #selector(checkForUpdatesAction), keyEquivalent: "")
        menu.addItem(updateMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit HammerTime", action: #selector(quitAction), keyEquivalent: "q"))
        
        statusItem.menu = menu
    }
    
    @objc private func toggleLockAction() {
        HammerTimeManager.shared.toggleLock()
    }
    
    @objc private func showPreferencesAction() {
        showPreferencesWindow()
    }
    
    @objc private func checkForUpdatesAction() {
        updaterController.checkForUpdates(nil)
    }
    
    @objc private func quitAction() {
        NSApplication.shared.terminate(nil)
    }
    
    // Handle URL events (IPC and Raycast)
    @objc func handleURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString) else {
            return
        }
        
        print("[URL] Received URL event: \(url)")
        
        DispatchQueue.main.async {
            switch url.host {
            case "toggle":
                HammerTimeManager.shared.toggleLock()
            case "lock":
                HammerTimeManager.shared.activateLock()
            case "unlock":
                HammerTimeManager.shared.deactivateLock()
            case "settings":
                self.showPreferencesWindow()
            default:
                break
            }
        }
    }
    
    // Preferences/Settings Window management (Glassmorphic Card UI)
    func showPreferencesWindow() {
        if preferencesWindow == nil {
            let hostingView = NSHostingView(rootView: PreferencesView())
            let size = hostingView.fittingSize
            
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "HammerTime Settings"
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden // Hides title text for floating look
            window.isMovableByWindowBackground = true // Drag anywhere on window background to move
            
            // Add Visual Effect View for Glassmorphism
            let visualEffectView = NSVisualEffectView()
            visualEffectView.blendingMode = .behindWindow
            visualEffectView.material = .hudWindow // Gorgeous adaptive translucent glass
            visualEffectView.state = .active
            visualEffectView.frame = window.contentView?.bounds ?? .zero
            visualEffectView.autoresizingMask = [.width, .height]
            
            hostingView.frame = visualEffectView.bounds
            hostingView.autoresizingMask = [.width, .height]
            
            visualEffectView.addSubview(hostingView)
            window.contentView?.addSubview(visualEffectView)
            
            window.center()
            window.isReleasedWhenClosed = false
            preferencesWindow = window
        }
        
        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // Deterrent Window management (Full screen on all connected displays)
    func showDeterrentOverlay(image: NSImage?) {
        closeDeterrentOverlay()
        
        let phrase = HammerTimeManager.shared.getKeyphrase()
        
        for screen in NSScreen.screens {
            let frame = screen.frame
            let window = NSWindow(
                contentRect: frame,
                styleMask: [.borderless, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            
            window.isOpaque = false
            window.backgroundColor = .clear
            window.level = .screenSaver // Above other windows
            window.ignoresMouseEvents = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            
            // Native Glassmorphic Blur via NSVisualEffectView
            let visualEffectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
            visualEffectView.blendingMode = .behindWindow
            visualEffectView.material = .hudWindow
            visualEffectView.state = .active
            visualEffectView.autoresizingMask = [.width, .height]
            window.contentView?.addSubview(visualEffectView)
            
            let view = DeterrentView(image: image, unlockPhrase: phrase)
            let hostingView = NSHostingView(rootView: view)
            hostingView.frame = NSRect(origin: .zero, size: frame.size)
            hostingView.autoresizingMask = [.width, .height]
            visualEffectView.addSubview(hostingView)
            
            window.makeKeyAndOrderFront(nil)
            deterrentWindows.append(window)
        }
        
        // Activate app to cover normal desktop components
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func closeDeterrentOverlay() {
        for window in deterrentWindows {
            window.orderOut(nil)
        }
        deterrentWindows.removeAll()
    }
    
    func setDeterrentWindowsLevel(_ level: NSWindow.Level) {
        for window in deterrentWindows {
            window.level = level
        }
    }
    
    func showActivationConfetti() {
        closeConfettiWindow()
        
        guard let screen = NSScreen.main else { return }
        let frame = screen.frame
        
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .screenSaver + 1 // High level above other app windows
        window.ignoresMouseEvents = true // Pass interactions through
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        
        let view = HammerConfettiView()
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: frame.size)
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView
        
        window.makeKeyAndOrderFront(nil)
        self.confettiWindow = window
        
        // Auto-close after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.closeConfettiWindow()
        }
    }
    
    private func closeConfettiWindow() {
        confettiWindow?.orderOut(nil)
        confettiWindow = nil
    }
}
