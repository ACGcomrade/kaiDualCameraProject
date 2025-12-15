import SwiftUI
import Combine

/// Unified notification manager for displaying temporary toast notifications
class NotificationManager: ObservableObject {
    
    init() {
        print("🔔 NotificationManager initialized: \(ObjectIdentifier(self))")
    }
    
    // Notification types
    enum NotificationType {
        case captureMode(CaptureMode)
        case cameraMode(CameraMode)
        case success(String)
        case error(String)
        case info(String)
        
        var icon: String {
            switch self {
            case .captureMode(let mode):
                return mode.icon
            case .cameraMode(let mode):
                return mode.iconName
            case .success:
                return "checkmark.circle.fill"
            case .error:
                return "xmark.circle.fill"
            case .info:
                return "info.circle.fill"
            }
        }
        
        var text: String {
            switch self {
            case .captureMode(let mode):
                return mode.fullDisplayName
            case .cameraMode(let mode):
                return mode.displayName
            case .success(let message):
                return message
            case .error(let message):
                return message
            case .info(let message):
                return message
            }
        }
        
        var backgroundColor: Color {
            switch self {
            case .captureMode:
                return Color.black.opacity(0.85)
            case .cameraMode(let mode):
                return mode == .picInPic ? Color.purple.opacity(0.85) : Color.black.opacity(0.85)
            case .success:
                return Color.green.opacity(0.85)
            case .error:
                return Color.red.opacity(0.85)
            case .info:
                return Color.blue.opacity(0.85)
            }
        }
    }
    
    // Published properties
    @Published var isShowing = false
    @Published var currentNotification: NotificationType?
    
    // Timer for auto-hiding
    private var hideTimer: AnyCancellable?
    private var autoHideDuration: TimeInterval = 2.0
    
    /// Show a notification with automatic dismissal
    /// - Parameters:
    ///   - type: The type of notification to show
    ///   - duration: How long to show the notification (default 2 seconds)
    func show(_ type: NotificationType, duration: TimeInterval = 2.0) {
        print("🔔 NotificationManager.show() called: \(type.text)")
        print("   Currently showing: \(isShowing), currentNotification: \(currentNotification?.text ?? "nil")")
        print("   Self reference: \(ObjectIdentifier(self))")
        
        // Cancel existing timer
        hideTimer?.cancel()
        
        // If already showing a notification, quickly fade it out and show new one
        if isShowing {
            print("   Replacing existing notification with new one")
            // Quick fade out
            withAnimation(.easeOut(duration: 0.15)) {
                isShowing = false
            }
            
            // After brief delay, show new notification
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                self.currentNotification = type
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    self.isShowing = true
                }
                self.restartTimer(duration: duration)
            }
        } else {
            print("   Showing new notification")
            // Show immediately
            currentNotification = type
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                isShowing = true
            }
            restartTimer(duration: duration)
        }
    }
    
    /// Restart the auto-hide timer
    private func restartTimer(duration: TimeInterval) {
        print("   Starting auto-hide timer for \(duration) seconds")
        
        // Auto-hide after duration
        hideTimer = Just(())
            .delay(for: .seconds(duration), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                print("🔔 NotificationManager: Auto-hiding notification")
                withAnimation(.easeOut(duration: 0.3)) {
                    self?.isShowing = false
                }
            }
    }
    
    /// Manually hide the notification
    func hide() {
        hideTimer?.cancel()
        withAnimation(.easeOut(duration: 0.3)) {
            isShowing = false
        }
    }
}

/// Reusable notification view component
struct NotificationBanner: View {
    let type: NotificationManager.NotificationType
    
    init(type: NotificationManager.NotificationType) {
        self.type = type
        print("🎨 NotificationBanner created: \(type.text)")
    }
    
    var body: some View {
        VStack {
            HStack(spacing: 10) {
                Image(systemName: type.icon)
                    .font(.system(size: 20))
                Text(type.text)
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundColor(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                Capsule()
                    .fill(type.backgroundColor)
                    .shadow(color: Color.black.opacity(0.3), radius: 10, x: 0, y: 4)
            )
            .padding(.top, 60)
            
            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .allowsHitTesting(false)
        .onAppear {
            print("🎨 NotificationBanner appeared on screen")
        }
        .onDisappear {
            print("🎨 NotificationBanner disappeared from screen")
        }
    }
}
