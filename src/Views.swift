import SwiftUI
import AVFoundation

enum Tab {
    case settings
    case wallOfShame
}

struct PreferencesView: View {
    @State private var selectedTab: Tab = .settings
    @State private var keyphrase: String = HammerTimeManager.shared.getKeyphrase()
    @State private var isAccessibilityGranted: Bool = AXIsProcessTrusted()
    @State private var isCameraGranted: Bool = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    @State private var isCameraAvailable: Bool = CameraManager.shared.isCameraAvailable
    @State private var testCountdown: Int = 0
    @State private var timer: Timer? = nil
    
    @Environment(\.colorScheme) var colorScheme
    private let statusTimer = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()
    
    var body: some View {
        VStack(spacing: 16) {
            // Header (Window title alternative)
            HStack {
                Image(systemName: "hammer.fill")
                    .font(.system(size: 15))
                    .foregroundColor(.accentColor)
                
                Text("HammerTime Settings")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)
                
                Spacer()
            }
            
            // Tab Selector
            Picker("", selection: $selectedTab) {
                Text("Settings").tag(Tab.settings)
                Text("Wall of Shame").tag(Tab.wallOfShame)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            
            if selectedTab == .settings {
                // Keyphrase Card
                VStack(alignment: .leading, spacing: 8) {
                Text("SECRET KEYPHRASE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .tracking(1)
                
                TextField("Enter keyphrase", text: $keyphrase)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: keyphrase) { oldValue, newValue in
                        HammerTimeManager.shared.setKeyphrase(newValue)
                    }
                
                Text("Type anywhere to unlock. Case-insensitive.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .padding(12)
            .background(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
            .cornerRadius(10)
            
            // Touch ID Card (only if biometrics are supported on the device)
            if HammerTimeManager.shared.canUseBiometrics() {
                HStack(alignment: .center, spacing: 6) {
                    Image(systemName: "touchid")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    Text("Deactivate with Touch ID")
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                    Button(action: showTouchIDInfo) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("How to use Touch ID unlock")
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { HammerTimeManager.shared.isBiometricsEnabled },
                        set: { HammerTimeManager.shared.setBiometricsEnabled($0) }
                    ))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                }
                .padding(12)
                .background(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
                .cornerRadius(10)
            }
            
            // Permissions Card
            VStack(alignment: .leading, spacing: 12) {
                Text("SYSTEM PERMISSIONS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .tracking(1)
                
                // Accessibility API
                HStack {
                    Image(systemName: "keyboard")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    Text("Accessibility API")
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                    Spacer()
                    if isAccessibilityGranted {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.green)
                            Text("Active")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                    } else {
                        Button("Grant") {
                            HammerTimeManager.shared.promptAccessibilityPermission()
                            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                
                Divider()
                
                // Camera Access
                HStack {
                    Image(systemName: "video")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    Text("Camera Access")
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                    Spacer()
                    if !isCameraAvailable {
                        HStack(spacing: 5) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.red)
                            Text("No Camera")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                    } else if isCameraGranted {
                        HStack(spacing: 5) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .foregroundColor(.green)
                            Text("Active")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.primary)
                        }
                    } else {
                        Button("Grant") {
                            let status = AVCaptureDevice.authorizationStatus(for: .video)
                            if status == .denied || status == .restricted {
                                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
                                    NSWorkspace.shared.open(url)
                                }
                            } else {
                                CameraManager.shared.checkPermission { granted in
                                    isCameraGranted = granted
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            .padding(12)
            .background(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
            .cornerRadius(10)
            
            // Shortcuts Card
            VStack(alignment: .leading, spacing: 8) {
                Text("GLOBAL SHORTCUT")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .tracking(1)
                
                HStack {
                    Image(systemName: "keyboard.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                    
                    Text("Activate Lock")
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    HStack(spacing: 4) {
                        KeyCapView(key: "⌃")
                        KeyCapView(key: "⌥")
                        KeyCapView(key: "⌘")
                        KeyCapView(key: "H")
                    }
                }
            }
            .padding(12)
            .background(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
            .cornerRadius(10)
            
            // Testing / Operations
            HStack {
                Button(action: startTestTimer) {
                    if testCountdown > 0 {
                        Text("Testing in \(testCountdown)...")
                    } else {
                        Text("Test Intruder Capture")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(testCountdown > 0)
            }
            .padding(.top, 4)
            } else {
                WallOfShameView()
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 40)
        .padding(.top, 40)
        .frame(width: 320)
        .onReceive(statusTimer) { _ in
            isAccessibilityGranted = AXIsProcessTrusted()
            isCameraGranted = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
            isCameraAvailable = CameraManager.shared.isCameraAvailable
        }
    }
    
    private func startTestTimer() {
        testCountdown = 5
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { t in
            if testCountdown > 1 {
                testCountdown -= 1
            } else {
                testCountdown = 0
                t.invalidate()
                HammerTimeManager.shared.activateLock()
                if HammerTimeManager.shared.isLocked {
                    HammerTimeManager.shared.captureIntruder(reason: "Manual Test")
                }
            }
        }
    }
    
    private func showTouchIDInfo() {
        let alert = NSAlert()
        alert.messageText = "How Touch ID Unlock Works"
        alert.informativeText = "Because HammerTime blocks all keyboard and mouse inputs globally to secure your Mac, background apps cannot directly monitor the Touch ID sensor.\n\nTo use Touch ID:\n1. Lock HammerTime.\n2. When you return, click the screen or press the Spacebar or Return key.\n3. The warning overlay will appear, temporarily suspend input-swallowing, and display the macOS system Touch ID prompt on top.\n4. Scan your fingerprint to unlock!"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Got it")
        alert.runModal()
    }
}

// Deterrent Card containing the captured intruder photo and warning messages
struct DeterrentCardView: View {
    let image: NSImage?
    var showUnlockInstructions: Bool = true
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.orange)
                
                Text("Intruder Captured")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Text("This person touched a computer that is not theirs.")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary)
            }
            
            // Photo Frame
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .frame(width: 400, height: 300)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                
                if let img = image {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 390, height: 290)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "video.slash.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        
                        Text("No Camera Detected or Access Denied")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                }
            }
            
            if showUnlockInstructions {
                VStack(spacing: 6) {
                    Text("System is Locked")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    
                    if HammerTimeManager.shared.canUseBiometrics() && HammerTimeManager.shared.isBiometricsEnabled {
                        Text("Type keyphrase, click screen, or press Space to use Touch ID.")
                            .font(.body)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    } else {
                        Text("Type the secret keyphrase to unlock.")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .padding(32)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}

// Deterrent View (Full-Screen locked overlay containing a static centered card)
struct DeterrentView: View {
    let image: NSImage?
    let unlockPhrase: String
    
    var body: some View {
        ZStack {
            DeterrentCardView(image: image)
                .shadow(color: Color.black.opacity(0.5), radius: 30, x: 0, y: 15)
                .frame(width: 480, height: 500)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.clear)
    }
}

struct HammerConfettiView: View {
    @State private var animate = false
    let count = 45
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if animate {
                    ForEach(0..<count, id: \.self) { i in
                        ConfettiParticleView(index: i, size: geometry.size)
                    }
                }
            }
            .onAppear {
                animate = true
            }
        }
        .background(Color.clear)
    }
}

struct ConfettiParticleView: View {
    let index: Int
    let size: CGSize
    
    @State private var position: CGPoint
    @State private var rotation: Double = 0.0
    @State private var scale: CGFloat = 0.1
    @State private var opacity: Double = 1.0
    
    init(index: Int, size: CGSize) {
        self.index = index
        self.size = size
        _position = State(initialValue: CGPoint(x: size.width / 2, y: size.height / 2))
    }
    
    var body: some View {
        Text("🔨")
            .font(.system(size: CGFloat.random(in: 24...48)))
            .scaleEffect(scale)
            .rotationEffect(.degrees(rotation))
            .position(position)
            .opacity(opacity)
            .onAppear {
                let angle = Double.random(in: 0...(2 * .pi))
                let distance = CGFloat.random(in: 150...600)
                let targetX = (size.width / 2) + cos(angle) * distance
                let targetY = (size.height / 2) + sin(angle) * distance + CGFloat.random(in: 150...350)
                
                withAnimation(.easeOut(duration: 1.8)) {
                    position = CGPoint(x: targetX, y: targetY)
                    rotation = Double.random(in: 360...1080)
                    scale = CGFloat.random(in: 1.0...2.5)
                }
                
                withAnimation(.easeIn(duration: 1.2).delay(0.6)) {
                    opacity = 0.0
                }
            }
    }
}

struct KeyCapView: View {
    let key: String
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        Text(key)
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .frame(minWidth: 18, minHeight: 18)
            .padding(.horizontal, 4)
            .background(colorScheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.08))
            .foregroundColor(.primary)
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
            )
    }
}

// MARK: - Wall of Shame View

struct WallOfShameView: View {
    @State private var entries: [HistoryEntry] = []
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("CAPTURED INTRUDERS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .tracking(1)
                
                Spacer()
                
                if !entries.isEmpty {
                    Button("Clear All") {
                        let alert = NSAlert()
                        alert.messageText = "Clear History?"
                        alert.informativeText = "Are you sure you want to permanently delete all captured intruder records and photos?"
                        alert.alertStyle = .critical
                        alert.addButton(withTitle: "Clear All")
                        alert.addButton(withTitle: "Cancel")
                        
                        if alert.runModal() == .alertFirstButtonReturn {
                            HammerTimeManager.shared.clearHistory()
                            refreshHistory()
                        }
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.red)
                    .font(.system(size: 10, weight: .bold))
                }
            }
            
            if entries.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "shield.checkered")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    
                    Text("No intruders captured yet.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 200)
                .background(colorScheme == .dark ? Color.white.opacity(0.04) : Color.black.opacity(0.02))
                .cornerRadius(10)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(entries) { entry in
                            HistoryEntryRow(entry: entry, onDelete: {
                                HammerTimeManager.shared.deleteHistoryEntry(id: entry.id)
                                refreshHistory()
                            })
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
        }
        .padding(12)
        .background(colorScheme == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.04))
        .cornerRadius(10)
        .onAppear {
            refreshHistory()
        }
    }
    
    private func refreshHistory() {
        entries = HammerTimeManager.shared.loadHistory()
    }
}

struct HistoryEntryRow: View {
    let entry: HistoryEntry
    let onDelete: () -> Void
    
    @State private var image: NSImage? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                // Thumbnail
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(NSColor.controlBackgroundColor))
                        .frame(width: 80, height: 60)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
                        )
                    
                    if let img = image {
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 80, height: 60)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    } else {
                        Image(systemName: "video.slash")
                            .font(.system(size: 16))
                            .foregroundColor(.secondary)
                    }
                }
                .onAppear {
                    if let filename = entry.photoFilename {
                        DispatchQueue.global(qos: .userInitiated).async {
                            if let img = HammerTimeManager.shared.getHistoryImage(filename: filename) {
                                DispatchQueue.main.async {
                                    self.image = img
                                }
                            }
                        }
                    }
                }
                
                // Metadata Block
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.reason)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(formatDate(entry.date))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    if let filename = entry.photoFilename {
                        Text(filename)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary.opacity(0.8))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                
                Spacer()
            }
            
            Divider()
                .opacity(0.2)
            
            // Actions Toolbar
            HStack(spacing: 8) {
                Spacer()
                
                if entry.photoFilename != nil {
                    // Open in Preview
                    Button(action: openInPreview) {
                        HStack(spacing: 4) {
                            Image(systemName: "eye")
                                .font(.system(size: 10))
                            Text("Preview")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Open Photo in Preview")
                    
                    // Show in Finder
                    Button(action: showInFinder) {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.system(size: 10))
                            Text("Reveal")
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Show Photo in Finder")
                }
                
                // Delete button
                Button(action: onDelete) {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 10))
                        Text("Delete")
                    }
                    .foregroundColor(.red)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Delete Record")
            }
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.4))
        .cornerRadius(8)
    }
    
    private func openInPreview() {
        guard let filename = entry.photoFilename else { return }
        let historyDir = HammerTimeManager.shared.getHistoryDirectory()
        let fileURL = historyDir.appendingPathComponent(filename)
        NSWorkspace.shared.open(fileURL)
    }
    
    private func showInFinder() {
        guard let filename = entry.photoFilename else { return }
        let historyDir = HammerTimeManager.shared.getHistoryDirectory()
        let fileURL = historyDir.appendingPathComponent(filename)
        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}
