import SwiftUI

/// Focus indicator that appears when user taps to focus
struct FocusIndicator: View {
    let position: CGPoint
    @State private var scale: CGFloat = 1.2
    @State private var opacity: Double = 1.0
    
    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .stroke(Color.yellow, lineWidth: 2)
            .frame(width: 80, height: 80)
            .position(position)
            .scaleEffect(scale)
            .opacity(opacity)
            .onAppear {
                // Animate in
                withAnimation(.easeOut(duration: 0.2)) {
                    scale = 1.0
                }
                
                // Fade out after 1.5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        opacity = 0
                    }
                }
            }
    }
}

#Preview {
    ZStack {
        Color.black
            .ignoresSafeArea()
        
        FocusIndicator(position: CGPoint(x: 200, y: 300))
    }
}
