import SwiftUI

/// Camera control buttons (flash, capture, mode switch, gallery)
struct CameraControlButtons: View {
    let captureMode: CaptureMode
    let isFlashOn: Bool
    let isRecording: Bool
    let lastCapturedImage: UIImage?
    let onFlashToggle: () -> Void
    let onCapture: () -> Void
    let onModeSwitch: () -> Void
    let onOpenGallery: () -> Void
    
    var body: some View {
        HStack(spacing: 30) {
            // Gallery/Photo Library button (shows last captured photo)
            Button(action: onOpenGallery) {
                if let image = lastCapturedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 50, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.white, lineWidth: 2)
                        )
                } else {
                    Image(systemName: "photo.on.rectangle")
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                        .frame(width: 50, height: 50)
                        .background(Color.black.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            
            // Empty spacer to balance layout
            Color.clear
                .frame(width: 50, height: 50)
            
            // Capture button (changes based on mode)
            Button(action: onCapture) {
                ZStack {
                    // Outer ring
                    Circle()
                        .stroke(Color.white, lineWidth: 3)
                        .frame(width: 80, height: 80)
                    
                    // Inner shape - circle for photo, rounded rect for video
                    if captureMode == .photo {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 70, height: 70)
                    } else {
                        // Video mode
                        if isRecording {
                            // Square when recording
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.red)
                                .frame(width: 35, height: 35)
                        } else {
                            // Circle with red fill when not recording
                            Circle()
                                .fill(Color.red)
                                .frame(width: 70, height: 70)
                        }
                    }
                }
            }
            
            // Flash toggle
            Button(action: onFlashToggle) {
                Image(systemName: isFlashOn ? "bolt.fill" : "bolt.slash.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
            
            // Mode switch button (Photo/Video toggle)
            Button(action: onModeSwitch) {
                Image(systemName: captureMode == .photo ? "video.fill" : "camera.fill")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .frame(width: 60, height: 60)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
        }
        .padding(.bottom, 40)
    }
}

#Preview {
    ZStack {
        Color.black
        VStack {
            Spacer()
            CameraControlButtons(
                captureMode: .photo,
                isFlashOn: false,
                isRecording: false,
                lastCapturedImage: nil,
                onFlashToggle: {},
                onCapture: {},
                onModeSwitch: {},
                onOpenGallery: {}
            )
        }
    }
}
