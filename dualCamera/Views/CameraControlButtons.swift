import SwiftUI

/// Camera control buttons (flash, capture, mode switch, gallery)
struct CameraControlButtons: View {
    let captureMode: CaptureMode
    let flashMode: FlashMode
    let isRecording: Bool
    let lastCapturedImage: UIImage?
    let onFlashToggle: () -> Void
    let onCapture: () -> Void
    let onModeSwitch: () -> Void
    let onOpenGallery: () -> Void
    let onInteraction: () -> Void
    let isUIVisible: Bool  // 控制辅助按钮的显示/隐藏
    
    @Environment(\.verticalSizeClass) var verticalSizeClass
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    // Detect if device is in landscape orientation
    private var isLandscape: Bool {
        verticalSizeClass == .compact
    }
    
    var body: some View {
        GeometryReader { geometry in
            if isLandscape {
                // Landscape layout: Vertical stack on the right edge
                VStack(spacing: 30) {
                    // Gallery button (top)
                    Button(action: {
                        onInteraction()
                        onOpenGallery()
                    }) {
                        galleryButtonContent
                    }
                    .opacity(isUIVisible ? 1 : 0)
                    
                    // Flash toggle with mode indicator
                    Button(action: {
                        onInteraction()
                        onFlashToggle()
                    }) {
                        ZStack {
                            Image(systemName: flashMode.iconName)
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                                .frame(width: 60, height: 60)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                            
                            // Mode indicator
                            if flashMode != .off {
                                Text(flashMode.displayName)
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.yellow)
                                    .cornerRadius(4)
                                    .offset(x: 0, y: 24)
                            }
                        }
                    }
                    .opacity(isUIVisible ? 1 : 0)
                    
                    // Capture button (centered vertically) - 始终显示
                    Spacer()
                    Button(action: onCapture) {
                        captureButtonContent
                    }
                    Spacer()
                    
                    // Mode switch button
                    Button(action: {
                        onInteraction()
                        onModeSwitch()
                    }) {
                        Image(systemName: captureMode == .photo ? "video.fill" : "camera.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                            .frame(width: 60, height: 60)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .opacity(isUIVisible ? 1 : 0)
                }
                .frame(width: 100)
                .padding(.trailing, 20)
                .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                // Portrait layout: Main control buttons at bottom
                VStack {
                    Spacer() // Push main buttons to bottom
                    
                    // Bottom: Main control buttons
                    HStack(spacing: 30) {
                        // Gallery/Photo Library button
                        Button(action: {
                            onInteraction()
                            onOpenGallery()
                        }) {
                            galleryButtonContent
                        }
                        .opacity(isUIVisible ? 1 : 0)
                        
                        // Capture button - 始终显示
                        Button(action: onCapture) {
                            captureButtonContent
                        }
                        
                        // Flash toggle with mode indicator
                        Button(action: {
                            onInteraction()
                            onFlashToggle()
                        }) {
                            ZStack {
                                Image(systemName: flashMode.iconName)
                                    .font(.system(size: 24))
                                    .foregroundColor(.white)
                                    .frame(width: 60, height: 60)
                                    .background(Color.black.opacity(0.6))
                                    .clipShape(Circle())
                                
                                // Mode indicator
                                if flashMode != .off {
                                    Text(flashMode.displayName)
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(Color.yellow)
                                        .cornerRadius(4)
                                        .offset(x: 0, y: 24)
                                }
                            }
                        }
                        .opacity(isUIVisible ? 1 : 0)
                        
                        // Mode switch button
                        Button(action: {
                            onInteraction()
                            onModeSwitch()
                        }) {
                            Image(systemName: captureMode == .photo ? "video.fill" : "camera.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.white)
                                .frame(width: 60, height: 60)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .opacity(isUIVisible ? 1 : 0)
                    }
                    .padding(.bottom, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    // MARK: - Reusable Button Content
    
    @ViewBuilder
    private var galleryButtonContent: some View {
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
    
    @ViewBuilder
    private var captureButtonContent: some View {
        ZStack {
            Circle()
                .stroke(Color.white, lineWidth: 3)
                .frame(width: 80, height: 80)
            
            if captureMode == .photo {
                Circle()
                    .fill(Color.white)
                    .frame(width: 70, height: 70)
            } else {
                if isRecording {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red)
                        .frame(width: 35, height: 35)
                } else {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 70, height: 70)
                }
            }
        }
    }
}

#Preview("Photo Mode - Portrait") {
    ZStack {
        Color.black
        VStack {
            Spacer()
            CameraControlButtons(
                captureMode: .photo,
                flashMode: .off,
                isRecording: false,
                lastCapturedImage: nil,
                onFlashToggle: {},
                onCapture: {},
                onModeSwitch: {},
                onOpenGallery: {},
                onInteraction: {},
                isUIVisible: true
            )
        }
    }
}

#Preview("Video Mode - Landscape", traits: .landscapeRight) {
    ZStack {
        Color.black
        CameraControlButtons(
            captureMode: .video,
            flashMode: .on,
            isRecording: false,
            lastCapturedImage: nil,
            onFlashToggle: {},
            onCapture: {},
            onModeSwitch: {},
            onOpenGallery: {},
            onInteraction: {},
            isUIVisible: true
        )
    }
}

#Preview("Video Mode - Recording") {
    ZStack {
        Color.black
        VStack {
            Spacer()
            CameraControlButtons(
                captureMode: .video,
                flashMode: .auto,
                isRecording: true,
                lastCapturedImage: nil,
                onFlashToggle: {},
                onCapture: {},
                onModeSwitch: {},
                onOpenGallery: {},
                onInteraction: {},
                isUIVisible: true
            )
        }
    }
}

#Preview("Photo Mode") {
    ZStack {
        Color.black
        VStack {
            Spacer()
            CameraControlButtons(
                captureMode: .photo,
                flashMode: .off,
                isRecording: false,
                lastCapturedImage: nil,
                onFlashToggle: {},
                onCapture: {},
                onModeSwitch: {},
                onOpenGallery: {},
                onInteraction: {},
                isUIVisible: true
            )
        }
    }
}

#Preview("Video Mode - Not Recording") {
    ZStack {
        Color.black
        VStack {
            Spacer()
            CameraControlButtons(
                captureMode: .video,
                flashMode: .on,
                isRecording: false,
                lastCapturedImage: nil,
                onFlashToggle: {},
                onCapture: {},
                onModeSwitch: {},
                onOpenGallery: {},
                onInteraction: {},
                isUIVisible: true
            )
        }
    }
}

#Preview("Flash Modes") {
    ZStack {
        Color.black
        VStack {
            Spacer()
            CameraControlButtons(
                captureMode: .photo,
                flashMode: .auto,
                isRecording: false,
                lastCapturedImage: nil,
                onFlashToggle: {},
                onCapture: {},
                onModeSwitch: {},
                onOpenGallery: {},
                onInteraction: {},
                isUIVisible: true
            )
        }
    }
}
