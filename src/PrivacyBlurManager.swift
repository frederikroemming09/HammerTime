import Cocoa
import SwiftUI

// Blurs every display while HammerTime is active so passers-by can't read what's on the screen.
// Uses the window server's behind-window blur, so no extra permissions are needed.
class PrivacyBlurManager: NSObject {
    static let shared = PrivacyBlurManager()

    // Sits just below the deterrent overlay (.screenSaver) and confetti (.screenSaver + 1)
    private static let activeLevel = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue - 1)
    // Below the deterrent overlay while it is lowered to .floating for the Touch ID prompt
    private static let loweredLevel = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue - 1)

    private var windows: [PrivacyBlurWindow] = []
    private var isLowered = false
    private var isPreviewing = false
    private var previewWorkItem: DispatchWorkItem?

    var isVisible: Bool {
        return !windows.isEmpty
    }

    override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func show() {
        cancelPreview()
        buildWindows()
        print("[PrivacyBlur] Privacy blur shown on \(windows.count) display(s).")
    }

    func hide() {
        cancelPreview()
        removeWindows()
        isLowered = false
    }

    // Shows the blur for a few seconds without locking, so the user can see what others would see
    func preview(duration: TimeInterval = 4.0) {
        guard !HammerTimeManager.shared.isLocked else { return }
        cancelPreview()
        isPreviewing = true
        buildWindows()

        let workItem = DispatchWorkItem { [weak self] in
            guard !HammerTimeManager.shared.isLocked else { return }
            self?.hide()
        }
        previewWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: workItem)
    }

    private func cancelPreview() {
        previewWorkItem?.cancel()
        previewWorkItem = nil
        isPreviewing = false
    }

    // Lowers the blur below the Touch ID prompt while authentication is in progress
    func setLowered(_ lowered: Bool) {
        isLowered = lowered
        for window in windows {
            window.level = lowered ? Self.loweredLevel : Self.activeLevel
        }
    }

    private func buildWindows() {
        removeWindows()
        for screen in NSScreen.screens {
            let window = PrivacyBlurWindow(screen: screen, showsPreviewBadge: isPreviewing)
            window.level = isLowered ? Self.loweredLevel : Self.activeLevel
            window.orderFrontRegardless()
            windows.append(window)
        }
    }

    private func removeWindows() {
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
    }

    @objc private func screenParametersChanged() {
        guard isVisible else { return }
        print("[PrivacyBlur] Screen configuration changed. Rebuilding blur windows.")
        buildWindows()
    }
}

class PrivacyBlurWindow: NSWindow {
    init(screen: NSScreen, showsPreviewBadge: Bool) {
        let frame = screen.frame
        super.init(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true // Input is already swallowed by the event tap
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        setFrame(frame, display: false)

        let blurView = NSVisualEffectView(frame: NSRect(origin: .zero, size: frame.size))
        blurView.blendingMode = .behindWindow
        blurView.material = .fullScreenUI
        blurView.state = .active
        blurView.autoresizingMask = [.width, .height]
        contentView = blurView

        let overlay = NSHostingView(rootView: PrivacyBlurOverlayView(showsPreviewBadge: showsPreviewBadge))
        overlay.frame = blurView.bounds
        overlay.autoresizingMask = [.width, .height]
        blurView.addSubview(overlay)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

struct PrivacyBlurOverlayView: View {
    let showsPreviewBadge: Bool

    var body: some View {
        ZStack {
            Image(systemName: "hammer.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.primary.opacity(0.35))

            if showsPreviewBadge {
                VStack {
                    Spacer()
                    HStack(spacing: 6) {
                        Image(systemName: "eye.slash.fill")
                        Text("Preview: this is what others see while HammerTime is active")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.ultraThickMaterial)
                    .clipShape(Capsule())
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
                    .padding(.bottom, 80)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
