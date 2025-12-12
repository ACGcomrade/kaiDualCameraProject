import SwiftUI

/// Alert that shows when video settings change (appears from top)
struct SettingsChangeAlert: View {
    let message: String
    let onDismiss: () -> Void
    
    var body: some View {
        VStack {
            VStack(spacing: 12) {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.white)
                
                Text("参数已更改")
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    .multilineTextAlignment(.center)
            }
            .padding(20)
            .background(Color.black.opacity(0.85))
            .cornerRadius(16)
            .shadow(radius: 20)
            .padding(.horizontal, 40)
            .padding(.top, 80)  // Position from top, accounting for safe area
            
            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .onAppear {
            // Provide haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            
            // Auto dismiss after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    onDismiss()
                }
            }
        }
    }
}

#Preview {
    ZStack {
        Color.gray.ignoresSafeArea()
        SettingsChangeAlert(message: "分辨率：1080p\n帧率：30 FPS", onDismiss: {})
    }
}
