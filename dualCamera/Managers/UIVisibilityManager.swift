import SwiftUI
import Combine

/// Manages UI element visibility based on user interaction
/// - UI buttons: Manually toggled by double-tap gesture
/// - Preview: Hide after 1 minute normally, 5 minutes during video recording
class UIVisibilityManager: ObservableObject {
    
    @Published var isUIVisible: Bool = true {
        didSet {
            print("👁️ UIVisibilityManager: ============ isUIVisible changed from \(oldValue) to \(isUIVisible) ============")
        }
    }
    
    @Published var isPreviewVisible: Bool = true {
        didSet {
            print("👁️ UIVisibilityManager: ============ isPreviewVisible changed from \(oldValue) to \(isPreviewVisible) ============")
            if !isPreviewVisible {
                print("👁️ UIVisibilityManager: ⚫️⚫️⚫️ PREVIEW IS NOW HIDDEN ⚫️⚫️⚫️")
            } else {
                print("👁️ UIVisibilityManager: ✅✅✅ PREVIEW IS NOW VISIBLE ✅✅✅")
            }
        }
    }
    
    private var previewHideTimer: Timer?
    
    // Timing constants
    private let previewHideDelayNormal: TimeInterval = 60.0        // 1 minute when not recording
    private let previewHideDelayRecording: TimeInterval = 300.0    // 5 minutes during recording
    
    private var timerStartCount = 0  // Debug counter
    private var isRecording = false   // Track recording state
    
    init() {
        print("👁️ UIVisibilityManager: ========== INITIALIZED ==========")
        print("👁️ UIVisibilityManager: UI controlled by double-tap gesture")
        print("👁️ UIVisibilityManager: Preview hide delay (normal): \(previewHideDelayNormal)s (60s = 1 min)")
        print("👁️ UIVisibilityManager: Preview hide delay (recording): \(previewHideDelayRecording)s (300s = 5 min)")
        startPreviewTimer()
    }
    
    /// Update recording state to adjust preview hide timing
    func setRecordingState(_ recording: Bool) {
        let wasRecording = isRecording
        isRecording = recording
        
        if wasRecording != recording {
            print("👁️ UIVisibilityManager: 🎥 Recording state changed: \(recording)")
            print("👁️ UIVisibilityManager: 🎥 Preview will hide after \(recording ? previewHideDelayRecording : previewHideDelayNormal)s")
            
            // Restart preview timer with new timing
            startPreviewTimer()
        }
    }
    
    /// Toggle camera session (called on double-tap) - Stop/Start receiving camera frames
    func toggleCameraSession() {
        // MUST run on main thread to ensure immediate UI updates
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.toggleCameraSession()
            }
            return
        }
        
        print("👁️ UIVisibilityManager: ========== TOGGLE CAMERA SESSION ==========")
        print("👁️ UIVisibilityManager: Current isPreviewVisible: \(isPreviewVisible)")
        
        // Force immediate update using objectWillChange
        objectWillChange.send()
        
        // Instant change, no animation
        isPreviewVisible.toggle()
        
        // Force another update to ensure SwiftUI catches the change
        DispatchQueue.main.async { [weak self] in
            self?.objectWillChange.send()
        }
        
        print("👁️ UIVisibilityManager: ✅ Camera session is now: \(isPreviewVisible ? "RUNNING ✅" : "STOPPED ⚫️")")
    }
    
    /// User touched the screen - show everything and restart preview timer
    func userDidInteract() {
        // MUST run on main thread to ensure immediate UI updates
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.userDidInteract()
            }
            return
        }
        
        print("👁️ UIVisibilityManager: ========== USER INTERACTION DETECTED ==========")
        
        // Instant change, no animation
        // Show UI immediately
        if !self.isUIVisible {
            self.isUIVisible = true
            print("👁️ UIVisibilityManager: ✅ UI shown (was hidden)")
        } else {
            print("👁️ UIVisibilityManager: ℹ️  UI already visible")
        }
        
        // Show preview immediately
        if !self.isPreviewVisible {
            self.isPreviewVisible = true
            print("👁️ UIVisibilityManager: ✅ Preview shown (was hidden)")
        } else {
            print("👁️ UIVisibilityManager: ℹ️  Preview already visible")
        }
        
        // Restart preview timer only (outside animation block)
        print("👁️ UIVisibilityManager: 🔄 Restarting preview timer...")
        self.startPreviewTimer()
    }
    
    /// Start/restart preview timer only
    private func startPreviewTimer() {
        // MUST be called on main thread to ensure Timer is added to main RunLoop
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.startPreviewTimer()
            }
            return
        }
        
        // Cancel existing timer
        previewHideTimer?.invalidate()
        
        // Calculate preview delay based on recording state
        let previewDelay = isRecording ? previewHideDelayRecording : previewHideDelayNormal
        
        timerStartCount += 1
        let now = Date()
        
        print("👁️ UIVisibilityManager: ========== STARTING PREVIEW TIMER (Count: \(timerStartCount)) ==========")
        print("👁️ UIVisibilityManager: Current time: \(now)")
        print("👁️ UIVisibilityManager: Recording: \(isRecording)")
        print("👁️ UIVisibilityManager: ⏰ Preview will hide in \(previewDelay)s at: \(now.addingTimeInterval(previewDelay))")
        
        // Create preview timer - MUST be on main thread and main RunLoop
        previewHideTimer = Timer.scheduledTimer(withTimeInterval: previewDelay, repeats: false) { [weak self] timer in
            print("👁️ UIVisibilityManager: ⏰⏰⏰ PREVIEW TIMER FIRED at \(Date()) ⏰⏰⏰")
            print("👁️ UIVisibilityManager: Timer valid: \(timer.isValid)")
            self?.hidePreview()
        }
        
        // Verify timer was created
        if let previewTimer = previewHideTimer {
            print("👁️ UIVisibilityManager: ✅ Preview timer created (valid: \(previewTimer.isValid), fireDate: \(previewTimer.fireDate))")
        } else {
            print("👁️ UIVisibilityManager: ❌ Preview timer is nil!")
        }
        
        print("👁️ UIVisibilityManager: ========== PREVIEW TIMER STARTED ==========")
    }
    
    /// Hide camera preview (show black screen)
    private func hidePreview() {
        print("👁️ UIVisibilityManager: ========== HIDING PREVIEW ==========")
        print("👁️ UIVisibilityManager: Current isPreviewVisible: \(isPreviewVisible)")
        
        let delay = isRecording ? previewHideDelayRecording : previewHideDelayNormal
        
        // Instant change, no animation
        isPreviewVisible = false
        
        print("👁️ UIVisibilityManager: ✅ Preview hidden after \(delay) seconds of inactivity")
    }
    
    /// Force show UI (called when capture button is tapped)
    func forceShowUI() {
        userDidInteract()
    }
    
    /// Cleanup
    func invalidateTimers() {
        previewHideTimer?.invalidate()
    }
    
    deinit {
        invalidateTimers()
    }
}
