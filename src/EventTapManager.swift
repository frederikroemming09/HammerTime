import Cocoa

class EventTapManager: NSObject {
    static let shared = EventTapManager()
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isEnabled = false
    
    // State variables for triggers
    private var typedBuffer = ""
    private var typingTimer: Timer?
    
    private var recentTouchTimes: [Date] = []
    private var lastMouseMovedTime: Date?
    
    private var continuousMovementStart: Date?
    private var lastMouseEventTime: Date?
    
    func start() {
        guard !isEnabled else { return }
        
        typedBuffer = ""
        recentTouchTimes.removeAll()
        lastMouseMovedTime = nil
        continuousMovementStart = nil
        lastMouseEventTime = nil
        cancelTypingTimer()
        
        let eventMask = (1 << CGEventType.keyDown.rawValue) |
                        (1 << CGEventType.mouseMoved.rawValue) |
                        (1 << CGEventType.leftMouseDown.rawValue) |
                        (1 << CGEventType.leftMouseUp.rawValue) |
                        (1 << CGEventType.rightMouseDown.rawValue) |
                        (1 << CGEventType.rightMouseUp.rawValue) |
                        (1 << CGEventType.leftMouseDragged.rawValue) |
                        (1 << CGEventType.rightMouseDragged.rawValue) |
                        (1 << CGEventType.scrollWheel.rawValue)
        
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                let manager = Unmanaged<EventTapManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: refcon
        ) else {
            print("[EventTap] Failed to create event tap. Accessibility permission may be required.")
            return
        }
        
        self.eventTap = tap
        self.runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
        isEnabled = true
        print("[EventTap] Started event tap successfully.")
    }
    
    func stop() {
        guard isEnabled else { return }
        
        cancelTypingTimer()
        
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        
        eventTap = nil
        runLoopSource = nil
        isEnabled = false
        print("[EventTap] Stopped event tap.")
    }
    
    private func cancelTypingTimer() {
        typingTimer?.invalidate()
        typingTimer = nil
    }
    
    private func resetTypingTimer() {
        cancelTypingTimer()
        
        typingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            print("[EventTap] Triggered: Keyboard timeout (user stopped typing without completing keyphrase)")
            self.triggerIntruderCapture(reason: "Keyboard timeout trigger")
        }
    }
    
    private func triggerIntruderCapture(reason: String) {
        recentTouchTimes.removeAll()
        continuousMovementStart = nil
        cancelTypingTimer()
        
        // Notify manager to snap photo and display overlay
        DispatchQueue.main.async {
            HammerTimeManager.shared.captureIntruder(reason: reason)
        }
    }
    
    private func trackMouseEvent(type: CGEventType, time: Date) {
        // 1. Frequency Trigger (3 distinct touches in 3s)
        let isClickOrScroll = [
            .leftMouseDown, .rightMouseDown, .scrollWheel
        ].contains(type)
        
        if isClickOrScroll {
            recentTouchTimes.append(time)
        } else if [.mouseMoved, .leftMouseDragged, .rightMouseDragged].contains(type) {
            if lastMouseMovedTime == nil || time.timeIntervalSince(lastMouseMovedTime!) > 1.5 {
                recentTouchTimes.append(time)
            }
            lastMouseMovedTime = time
        }
        
        recentTouchTimes = recentTouchTimes.filter { time.timeIntervalSince($0) <= 3.0 }
        if recentTouchTimes.count >= 3 {
            print("[EventTap] Triggered: Mouse frequency (3 touches in 3s)")
            triggerIntruderCapture(reason: "Mouse frequency trigger")
            return
        }
        
        // 2. Duration Trigger (continuous movement for 3s)
        if [.mouseMoved, .leftMouseDragged, .rightMouseDragged, .scrollWheel].contains(type) {
            if continuousMovementStart == nil {
                continuousMovementStart = time
                lastMouseEventTime = time
            } else {
                if time.timeIntervalSince(lastMouseEventTime!) > 1.0 {
                    // Interrupted, reset start time
                    continuousMovementStart = time
                }
                lastMouseEventTime = time
                
                let duration = time.timeIntervalSince(continuousMovementStart!)
                if duration >= 3.0 {
                    print("[EventTap] Triggered: Mouse duration (continuous movement for \(duration)s)")
                    triggerIntruderCapture(reason: "Mouse duration trigger")
                }
            }
        }
    }
    
    private func handleKeyPress(nsEvent: NSEvent, time: Date) {
        let isOverlayVisible = HammerTimeManager.shared.isDeterrentOverlayVisible
        
        if !isOverlayVisible {
            resetTypingTimer()
        }
        
        let keyphrase = HammerTimeManager.shared.getKeyphrase()
        guard !keyphrase.isEmpty else { return }
        
        // Backspace / Delete
        if nsEvent.keyCode == 51 {
            if !typedBuffer.isEmpty {
                typedBuffer.removeLast()
                print("[EventTap] Typed buffer after backspace: \(typedBuffer)")
            }
            return
        }
        
        if let characters = nsEvent.characters {
            for char in characters {
                // Only consider printable characters to avoid control sequences corrupting the phrase
                if char.isLetter || char.isNumber || char.isPunctuation || char.isSymbol || char == " " {
                    typedBuffer.append(char.lowercased())
                    
                    // Restrict buffer size to double keyphrase length or at least 50
                    let maxLen = max(50, keyphrase.count * 2)
                    if typedBuffer.count > maxLen {
                        typedBuffer.removeFirst(typedBuffer.count - maxLen)
                    }
                    
                    print("[EventTap] Typed buffer: \(typedBuffer)")
                    
                    if typedBuffer.hasSuffix(keyphrase.lowercased()) {
                        print("[EventTap] Secret keyphrase matched!")
                        cancelTypingTimer()
                        typedBuffer = ""
                        
                        DispatchQueue.main.async {
                            HammerTimeManager.shared.deactivateLock()
                        }
                        return
                    }
                }
            }
        }
    }
    
    private func handleEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
                print("[EventTap] Re-enabled after timeout or user input disable event")
            }
            return Unmanaged.passRetained(event)
        }
        
        guard HammerTimeManager.shared.isLocked else {
            return Unmanaged.passRetained(event)
        }
        
        let now = Date()
        
        let isMouseEvent = [
            .mouseMoved, .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
            .leftMouseDragged, .rightMouseDragged, .scrollWheel
        ].contains(type)
        
        if isMouseEvent {
            if !HammerTimeManager.shared.isDeterrentOverlayVisible {
                trackMouseEvent(type: type, time: now)
            }
            // Swallow mouse events
            return nil
        }
        
        if type == .keyDown {
            if let nsEvent = NSEvent(cgEvent: event) {
                handleKeyPress(nsEvent: nsEvent, time: now)
            }
            // Swallow keyboard events
            return nil
        }
        
        return Unmanaged.passRetained(event)
    }
}
