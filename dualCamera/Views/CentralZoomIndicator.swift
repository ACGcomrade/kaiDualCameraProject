import SwiftUI

/// Central zoom level indicator that fades in/out when zoom changes
struct CentralZoomIndicator: View {
    let zoomFactor: CGFloat
    let baseZoomFactor: CGFloat?  // From camera info
    @State private var isVisible = false
    @State private var fadeOutTimer: Timer?
    
    // Format zoom display using base zoom mapping
    private var displayText: String {
        guard let base = baseZoomFactor else {
            return String(format: "%.1fx", zoomFactor)
        }
        return FocalLengthMapper.formatAsEquivalent(zoom: zoomFactor, baseZoomFactor: base)
    }
    
    var body: some View {
        VStack {
            Spacer()
            
            if isVisible {
                Text(displayText)
                    .font(.system(size: 100, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.25))
                    .shadow(color: .black.opacity(0.5), radius: 10)
                    .transition(.opacity)
            }
            
            Spacer()
        }
        .onChange(of: zoomFactor) { oldValue, newValue in
            // Cancel existing timer
            fadeOutTimer?.invalidate()
            
            // Show indicator
            withAnimation(.easeIn(duration: 0.2)) {
                isVisible = true
            }
            
            // Schedule fade out after 1 second
            fadeOutTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: false) { _ in
                withAnimation(.easeOut(duration: 0.3)) {
                    isVisible = false
                }
            }
        }
        .onDisappear {
            fadeOutTimer?.invalidate()
        }
    }
}

#Preview {
    ZStack {
        Color.black
        CentralZoomIndicator(zoomFactor: 1.0, baseZoomFactor: 2.0)
    }
}
