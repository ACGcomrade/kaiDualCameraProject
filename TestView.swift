import SwiftUI

/// Minimal test view to verify SwiftUI is working
/// Use this if you still see white screen to rule out camera issues
struct TestView: View {
    var body: some View {
        ZStack {
            Color.green.ignoresSafeArea()
            
            VStack(spacing: 20) {
                Text("Test View Works!")
                    .font(.title)
                    .foregroundColor(.white)
                
                Text("If you see this, SwiftUI is working")
                    .foregroundColor(.white)
                
                Text("The issue is in camera setup, not basic UI")
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding()
            }
        }
    }
}

// To test: In dualCameraApp.swift, temporarily change:
// ContentView() to TestView()
// If you see green screen with text, SwiftUI works fine
// Then the issue is in camera/preview setup

#Preview {
    TestView()
}
