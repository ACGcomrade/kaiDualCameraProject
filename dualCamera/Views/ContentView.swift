import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = CameraViewModel()
    @State private var hasAppearedOnce = false
    @State private var showGallery = false
    @State private var showCameraSelector = false
    @State private var recordingDotOpacity: Double = 1.0  // For slow blinking
    
    var body: some View {
        cameraView
            .sheet(isPresented: $showGallery) {
                PhotoGalleryView()
            }
            .sheet(isPresented: $showCameraSelector) {
                AllCamerasGridView(viewModel: viewModel)
                    .onAppear {
                        // 调用双击冻结的method停止主预览
                        if viewModel.uiVisibilityManager.isPreviewVisible {
                            viewModel.toggleCameraSession()
                        }
                    }
                    .onDisappear {
                        // 恢复主预览
                        if !viewModel.uiVisibilityManager.isPreviewVisible {
                            viewModel.toggleCameraSession()
                        }
                    }
            }
            .onAppear {
                // SAFETY: Only run setup once, even if onAppear is called multiple times
                guard !hasAppearedOnce else {
                    print("⚠️ ContentView: onAppear called again, ignoring (already initialized)")
                    return
                }
                hasAppearedOnce = true
                print("🟢 ContentView: onAppear called (first time)")
                viewModel.startCameraIfNeeded()
            }
    }
    
    private var cameraView: some View {
        ZStack {
            // Background color - always black - handles taps when everything is hidden
            Color.black
                .ignoresSafeArea()
            
            // Full screen dual camera preview (can be stopped by double-tap)
            // Double tap stops the camera session (stops receiving frames from camera)
            DualCameraPreview(viewModel: viewModel)
                .ignoresSafeArea()
                .id(viewModel.uiVisibilityManager.isPreviewVisible)  // Force view rebuild
                .opacity(viewModel.uiVisibilityManager.isPreviewVisible ? 1.0 : 0.0)
                .contentShape(Rectangle())
                .allowsHitTesting(true)  // Always allow hit testing
                .onTapGesture(count: 2) {
                    print("🖐️ ContentView: Double tap - toggling camera session")
                    // Double tap stops/starts camera session (stops receiving camera frames)
                    viewModel.toggleCameraSession()
                }
                .onTapGesture {
                    print("🖐️ ContentView: Single tap - ensuring camera is running")
                    // Single tap starts camera if stopped and resets timer
                    viewModel.handleUserInteraction()
                }
            
            // Recording indicator (red dot) when preview is hidden
            if !viewModel.uiVisibilityManager.isPreviewVisible && viewModel.isRecording {
                VStack {
                    HStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 16, height: 16)
                            .opacity(recordingDotOpacity)
                            .onAppear {
                                withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                                    recordingDotOpacity = 0.3
                                }
                            }
                            .padding(.leading, 20)
                            .padding(.top, 60)
                        
                        Spacer()
                    }
                    Spacer()
                }
                .allowsHitTesting(false) // Don't block tap gestures
            }
            
            // Central zoom level indicator (fades in/out)
            CentralZoomIndicator(
                zoomFactor: viewModel.zoomFactor,
                baseZoomFactor: viewModel.cameraManager.cameraInfo?.baseZoomFactor
            )
            .opacity(viewModel.uiVisibilityManager.isPreviewVisible ? 1.0 : 0.0)
            .animation(.easeInOut(duration: 0.3), value: viewModel.uiVisibilityManager.isPreviewVisible)
            .allowsHitTesting(false) // Don't block interactions
            
            // Zoom slider (with auto-hide) - only show when preview is visible
            if (viewModel.captureMode == .photo || viewModel.captureMode == .video) {
                GeometryReader { geometry in
                    let isLandscape = geometry.size.width > geometry.size.height
                    
                    if isLandscape {
                        // Horizontal slider centered at bottom
                        VStack {
                            Spacer()
                            
                            ZoomSlider(
                                zoomFactor: $viewModel.zoomFactor,
                                minZoom: viewModel.cameraManager.minZoomFactor,
                                maxZoom: viewModel.cameraManager.maxZoomFactor,
                                isHorizontal: true
                            )
                            .onChange(of: viewModel.zoomFactor) { _, newValue in
                                viewModel.setZoom(newValue)
                            }
                            .padding(.bottom, 20)
                            .opacity(viewModel.uiVisibilityManager.isUIVisible && viewModel.uiVisibilityManager.isPreviewVisible ? 1.0 : 0.0)
                            .animation(.easeInOut(duration: 0.3), value: viewModel.uiVisibilityManager.isUIVisible)
                            .animation(.easeInOut(duration: 0.3), value: viewModel.uiVisibilityManager.isPreviewVisible)
                        }
                    } else {
                        // Vertical slider on left side
                        VStack {
                            Spacer()
                            
                            HStack {
                                ZoomSlider(
                                    zoomFactor: $viewModel.zoomFactor,
                                    minZoom: viewModel.cameraManager.minZoomFactor,
                                    maxZoom: viewModel.cameraManager.maxZoomFactor,
                                    isHorizontal: false
                                )
                                .onChange(of: viewModel.zoomFactor) { _, newValue in
                                    viewModel.setZoom(newValue)
                                }
                                .padding(.leading, 20)
                                
                                Spacer()
                            }
                            .padding(.bottom, 150)
                            .opacity(viewModel.uiVisibilityManager.isUIVisible && viewModel.uiVisibilityManager.isPreviewVisible ? 1.0 : 0.0)
                            .animation(.easeInOut(duration: 0.3), value: viewModel.uiVisibilityManager.isUIVisible)
                            .animation(.easeInOut(duration: 0.3), value: viewModel.uiVisibilityManager.isPreviewVisible)
                        }
                    }
                }
            }
            
            // Camera controls and UI - conditionally rendered based on preview visibility
            if viewModel.uiVisibilityManager.isPreviewVisible {
                GeometryReader { geometry in
                    let isLandscape = geometry.size.width > geometry.size.height
                    
                    ZStack {
                        // Recording indicator - updates in real-time
                        if viewModel.isRecording {
                            VStack {
                                HStack(spacing: 12) {
                                    // Animated pulsing red circle
                                    Circle()
                                        .fill(Color.red)
                                        .frame(width: 20, height: 20)
                                        .overlay(
                                            Circle()
                                                .stroke(Color.red.opacity(0.5), lineWidth: 2)
                                                .scaleEffect(viewModel.isRecording ? 1.5 : 1.0)
                                                .opacity(viewModel.isRecording ? 0 : 1)
                                                .animation(
                                                    .easeInOut(duration: 1.0)
                                                    .repeatForever(autoreverses: false),
                                                    value: viewModel.isRecording
                                                )
                                        )
                                    
                                    // Real-time recording duration with monospaced font
                                    Text(timeString(from: viewModel.recordingDuration))
                                        .font(.system(size: 18, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.white)
                                        .id(viewModel.recordingDuration)
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(
                                    Capsule()
                                        .fill(Color.black.opacity(0.75))
                                        .shadow(color: Color.red.opacity(0.3), radius: 8, x: 0, y: 2)
                                )
                                .padding(.top, 60)
                                
                                Spacer()
                            }
                            .allowsHitTesting(false) // Don't block interactions
                            .transition(.scale.combined(with: .opacity))
                        }
                        
                        if isLandscape {
                            // 横屏布局
                            GeometryReader { geo in
                                ZStack {
                                    // 右侧垂直布局
                                    HStack {
                                        Spacer()
                                        
                                        VStack(spacing: 0) {
                                            // 顶部按钮区域
                                            Spacer().frame(height: 60)
                                            
                                            // Camera selector button - 在顶部
                                            if viewModel.uiVisibilityManager.isUIVisible {
                                                Button(action: {
                                                    showCameraSelector = true
                                                }) {
                                                    Image(systemName: "camera.metering.multispot")
                                                        .font(.system(size: 26))
                                                        .foregroundColor(.white)
                                                        .frame(width: 56, height: 56)
                                                        .background(Color.black.opacity(0.6))
                                                        .clipShape(Circle())
                                                }
                                                .transition(.opacity)
                                            }
                                            
                                            Spacer()
                                            
                                            // Capture button - 垂直居中
                                            Button(action: { 
                                                viewModel.captureOrRecord()
                                            }) {
                                                ZStack {
                                                    Circle()
                                                        .stroke(Color.white, lineWidth: 3)
                                                        .frame(width: 80, height: 80)
                                                    
                                                    if viewModel.captureMode == .photo {
                                                        Circle()
                                                            .fill(Color.white)
                                                            .frame(width: 70, height: 70)
                                                    } else {
                                                        if viewModel.isRecording {
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
                                            
                                            Spacer()
                                            
                                            // 底部三个按钮横向排列: Flash, Mode, Gallery
                                            if viewModel.uiVisibilityManager.isUIVisible {
                                                HStack(spacing: 20) {
                                                    // Flash toggle with mode indicator
                                                    Button(action: { 
                                                        viewModel.ensureCameraActiveAndExecute {
                                                            viewModel.toggleFlash()
                                                        }
                                                    }) {
                                                        ZStack {
                                                            Image(systemName: viewModel.flashMode.iconName)
                                                                .font(.system(size: 26))
                                                                .foregroundColor(.white)
                                                                .frame(width: 56, height: 56)
                                                                .background(Color.black.opacity(0.6))
                                                                .clipShape(Circle())
                                                            
                                                            // Mode indicator text
                                                            if viewModel.flashMode != .off {
                                                                Text(viewModel.flashMode.displayName)
                                                                    .font(.system(size: 8, weight: .bold))
                                                                    .foregroundColor(.white)
                                                                    .padding(.horizontal, 4)
                                                                    .padding(.vertical, 2)
                                                                    .background(Color.yellow)
                                                                    .cornerRadius(4)
                                                                    .offset(x: 0, y: 22)
                                                            }
                                                        }
                                                    }
                                                    
                                                    // Mode switch button
                                                    Button(action: { 
                                                        viewModel.ensureCameraActiveAndExecute {
                                                            viewModel.switchMode()
                                                        }
                                                    }) {
                                                        Image(systemName: viewModel.captureMode == .photo ? "video.fill" : "camera.fill")
                                                            .font(.system(size: 26))
                                                            .foregroundColor(.white)
                                                            .frame(width: 56, height: 56)
                                                            .background(Color.black.opacity(0.6))
                                                            .clipShape(Circle())
                                                    }
                                                    
                                                    // Gallery button
                                                    Button(action: { 
                                                        viewModel.ensureCameraActiveAndExecute {
                                                            showGallery = true
                                                        }
                                                    }) {
                                                        if let image = viewModel.lastCapturedImage {
                                                            Image(uiImage: image)
                                                                .resizable()
                                                                .scaledToFill()
                                                                .frame(width: 56, height: 56)
                                                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                                                .overlay(
                                                                    RoundedRectangle(cornerRadius: 10)
                                                                        .stroke(Color.white, lineWidth: 2)
                                                                )
                                                        } else {
                                                            Image(systemName: "photo.on.rectangle")
                                                                .font(.system(size: 26))
                                                                .foregroundColor(.white)
                                                                .frame(width: 56, height: 56)
                                                                .background(Color.black.opacity(0.6))
                                                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                                        }
                                                    }
                                                }
                                                .padding(.bottom, 40)
                                                .transition(.opacity)
                                            } else {
                                                Spacer().frame(height: 40)
                                            }
                                        }
                                        .padding(.trailing, 30)
                                    }
                                }
                            }
                        } else {
                            // 竖屏布局: 使用原来的 CameraControlButtons
                            VStack {
                                Spacer()
                                
                                CameraControlButtons(
                                    captureMode: viewModel.captureMode,
                                    flashMode: viewModel.flashMode,
                                    isRecording: viewModel.isRecording,
                                    lastCapturedImage: viewModel.lastCapturedImage,
                                    onFlashToggle: { 
                                        viewModel.ensureCameraActiveAndExecute {
                                            viewModel.toggleFlash()
                                        }
                                    },
                                    onCapture: { viewModel.captureOrRecord() },
                                    onModeSwitch: { 
                                        viewModel.ensureCameraActiveAndExecute {
                                            viewModel.switchMode()
                                        }
                                    },
                                    onOpenGallery: { 
                                        viewModel.ensureCameraActiveAndExecute {
                                            showGallery = true
                                        }
                                    },
                                    onInteraction: { viewModel.uiVisibilityManager.userDidInteract() },
                                    isUIVisible: viewModel.uiVisibilityManager.isUIVisible
                                )
                            }
                        }
                    }
                }
                .ignoresSafeArea()
                .transition(.opacity)
            }
            
            // Camera selector button for portrait (left top corner)
            if viewModel.uiVisibilityManager.isUIVisible && viewModel.uiVisibilityManager.isPreviewVisible {
                GeometryReader { geometry in
                    let isLandscape = geometry.size.width > geometry.size.height
                    
                    if !isLandscape {
                        // 竖屏：左上角
                        VStack {
                            HStack {
                                Button(action: {
                                    showCameraSelector = true
                                }) {
                                    Image(systemName: "camera.metering.multispot")
                                        .font(.system(size: 24))
                                        .foregroundColor(.white)
                                        .frame(width: 50, height: 50)
                                        .background(Color.black.opacity(0.6))
                                        .clipShape(Circle())
                                }
                                .padding(.leading, 20)
                                .padding(.top, 60)
                                
                                Spacer()
                            }
                            
                            Spacer()
                        }
                    }
                }
                .transition(.opacity)
            }
        
            // Capture button when preview is hidden (for stopping recording)
            // Always rendered but only visible when preview is hidden
            GeometryReader { geometry in
                let isLandscape = geometry.size.width > geometry.size.height
                
                if isLandscape {
                    // Landscape: button on right side, vertically centered
                    HStack {
                        Spacer()
                        
                        Button(action: {
                            viewModel.captureOrRecord()
                        }) {
                            ZStack {
                                Circle()
                                    .stroke(Color.white, lineWidth: 3)
                                    .frame(width: 80, height: 80)
                                
                                if viewModel.captureMode == .photo {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 70, height: 70)
                                } else {
                                    if viewModel.isRecording {
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
                        .padding(.trailing, 40)
                    }
                } else {
                    // Portrait: button at bottom center
                    VStack {
                        Spacer()
                        
                        Button(action: {
                            viewModel.captureOrRecord()
                        }) {
                            ZStack {
                                Circle()
                                    .stroke(Color.white, lineWidth: 3)
                                    .frame(width: 80, height: 80)
                                
                                if viewModel.captureMode == .photo {
                                    Circle()
                                        .fill(Color.white)
                                        .frame(width: 70, height: 70)
                                } else {
                                    if viewModel.isRecording {
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
                        .padding(.bottom, 40)
                    }
                }
            }
            .opacity(!viewModel.uiVisibilityManager.isPreviewVisible ? 1.0 : 0.0)
            .animation(.easeInOut(duration: 0.3), value: viewModel.uiVisibilityManager.isPreviewVisible)
            .allowsHitTesting(!viewModel.uiVisibilityManager.isPreviewVisible)  // Only allow interaction when preview is hidden
            
            // Screen flash overlay
            if viewModel.showScreenFlash {
                Color.white
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
            
            // Camera permission alert
            if viewModel.showSettingAlert {
                CameraPermissionAlert(
                    onOpenSettings: {
                        viewModel.openSettings()
                        viewModel.showSettingAlert = false
                    },
                    onDismiss: {
                        viewModel.showSettingAlert = false
                    }
                )
            }
            
            // Save status alert
            if viewModel.showSaveAlert, let status = viewModel.saveStatus {
                SaveStatusAlert(
                    status: status,
                    onDismiss: {
                        viewModel.showSaveAlert = false
                        viewModel.saveStatus = nil
                    }
                )
            }
        }
    }
    
    // Helper function to format time
    private func timeString(from timeInterval: TimeInterval) -> String {
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval) % 60
        let milliseconds = Int((timeInterval.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%02d:%02d.%01d", minutes, seconds, milliseconds)
    }
}

#Preview {
    ContentView()
}
