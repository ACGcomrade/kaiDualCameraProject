import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = CameraViewModel()
    @State private var hasAppearedOnce = false
    @State private var showGallery = false
    @State private var recordingDotOpacity: Double = 1.0  // For slow blinking
    @State private var previewRefreshID = UUID()  // Force preview rebuild
    @State private var focusPoint: CGPoint? = nil  // Focus indicator position
    @State private var showFocusIndicator = false  // Control focus indicator visibility
    @State private var showResolutionPicker = false  // Show resolution picker
    @State private var showFrameRatePicker = false  // Show frame rate picker
    @State private var showSettingsChangeAlert = false  // Show settings change alert
    @State private var settingsChangeMessage = ""  // Settings change message
    @State private var selectedResolution: VideoResolution = .resolution_1080p  // Temporary resolution selection
    @State private var selectedFrameRate: FrameRate = .fps_30  // Temporary frame rate selection
    
    var body: some View {
        cameraView
            .sheet(isPresented: $showGallery) {
                PhotoGalleryView()
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
            
            // Full screen dual camera preview - always visible
            DualCameraPreview(viewModel: viewModel)
                .ignoresSafeArea()
                .id(previewRefreshID)  // Force rebuild when ID changes
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            handleTapToFocus(at: value.location)
                        }
                )
            
            // Recording indicator (red dot) - always show during recording
            if viewModel.isRecording {
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
                        // Horizontal sliders at bottom
                        VStack {
                            Spacer()
                            
                            VStack(spacing: 15) {
                                // Zoom slider
                                ZoomSlider(
                                    zoomFactor: $viewModel.zoomFactor,
                                    minZoom: viewModel.cameraManager.minZoomFactor,
                                    maxZoom: viewModel.cameraManager.maxZoomFactor,
                                    isHorizontal: true
                                )
                                .onChange(of: viewModel.zoomFactor) { _, newValue in
                                    viewModel.setZoom(newValue)
                                }
                            }
                            .padding(.bottom, 20)
                            .opacity(viewModel.uiVisibilityManager.isUIVisible && viewModel.uiVisibilityManager.isPreviewVisible ? 1.0 : 0.0)
                            .animation(.easeInOut(duration: 0.3), value: viewModel.uiVisibilityManager.isUIVisible)
                            .animation(.easeInOut(duration: 0.3), value: viewModel.uiVisibilityManager.isPreviewVisible)
                        }
                    } else {
                        // Vertical sliders on left side
                        VStack {
                            Spacer()
                            
                            HStack {
                                // Zoom slider
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
                                
                                // Right side vertical buttons: Filter, Resolution, Frame Rate
                                VStack(spacing: 15) {
                                    // Filter button
                                    Button(action: {
                                        switchFilter()
                                    }) {
                                        Image(systemName: "camera.filters")
                                            .font(.system(size: 24))
                                            .foregroundColor(.white)
                                            .frame(width: 50, height: 50)
                                            .background(Color.black.opacity(0.7))
                                            .clipShape(Circle())
                                    }
                                    .id(viewModel.cameraManager.currentFilter.rawValue)
                                    
                                    // Resolution button
                                    Button(action: {
                                        selectedResolution = viewModel.cameraManager.currentResolution
                                        showResolutionPicker = true
                                    }) {
                                        VStack(spacing: 2) {
                                            Image(systemName: "4k.tv")
                                                .font(.system(size: 18))
                                            Text("分辨率")
                                                .font(.system(size: 8))
                                        }
                                        .foregroundColor(.white)
                                        .frame(width: 50, height: 50)
                                        .background(Color.black.opacity(0.7))
                                        .clipShape(Circle())
                                    }
                                    
                                    // Frame rate button
                                    Button(action: {
                                        selectedFrameRate = viewModel.cameraManager.currentFrameRate
                                        showFrameRatePicker = true
                                    }) {
                                        VStack(spacing: 2) {
                                            Image(systemName: "speedometer")
                                                .font(.system(size: 18))
                                            Text("帧率")
                                                .font(.system(size: 8))
                                        }
                                        .foregroundColor(.white)
                                        .frame(width: 50, height: 50)
                                        .background(Color.black.opacity(0.7))
                                        .clipShape(Circle())
                                    }
                                }
                                .padding(.trailing, 20)
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
                                    // 摄像模式切换按钮 - 长条形，在PIP预览框正下方
                                    if viewModel.uiVisibilityManager.isUIVisible {
                                        VStack {
                                            Spacer()
                                                .frame(height: 60) // 顶部安全区域
                                            
                                            // PIP预览框区域
                                            VStack {
                                                Spacer()
                                                    .frame(height: geo.size.height * 0.30) // PIP高度
                                                
                                                // 相机切换按钮直接在PIP下方
                                                Button(action: {
                                                    switchCameraMode()
                                                }) {
                                                    HStack(spacing: 8) {
                                                        Image(systemName: viewModel.cameraManager.cameraMode.iconName)
                                                            .font(.system(size: 18))
                                                        Text(viewModel.cameraManager.cameraMode.displayName)
                                                            .font(.system(size: 13, weight: .medium))
                                                    }
                                                    .foregroundColor(.white)
                                                    .padding(.horizontal, 14)
                                                    .padding(.vertical, 8)
                                                    .background(Color.black.opacity(0.7))
                                                    .cornerRadius(16)
                                                }
                                                .transition(.opacity)
                                                .padding(.top, 8)
                                            }
                                            .frame(maxWidth: .infinity, alignment: .trailing)
                                            .padding(.trailing, 20)
                                            
                                            Spacer()
                                        }
                                    }
                                    
                                    // 右侧垂直布局
                                    HStack {
                                        Spacer()
                                        
                                        VStack(spacing: 0) {
                                            // 顶部区域
                                            Spacer().frame(height: 60)
                                            
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
                                            
                                            // 底部按钮横向排列: Resolution, FPS, Flash, Filter, Mode, Gallery
                                            if viewModel.uiVisibilityManager.isUIVisible {
                                                VStack(spacing: 15) {
                                                    // 第一排：分辨率和帧率
                                                    HStack(spacing: 20) {
                                                        // Resolution button
                                                        Button(action: {
                                                            selectedResolution = viewModel.cameraManager.currentResolution
                                                            showResolutionPicker = true
                                                        }) {
                                                            VStack(spacing: 2) {
                                                                Image(systemName: "4k.tv")
                                                                    .font(.system(size: 18))
                                                                Text("分辨率")
                                                                    .font(.system(size: 8))
                                                            }
                                                            .foregroundColor(.white)
                                                            .frame(width: 50, height: 50)
                                                            .background(Color.black.opacity(0.6))
                                                            .clipShape(Circle())
                                                        }
                                                        
                                                        // Frame rate button
                                                        Button(action: {
                                                            selectedFrameRate = viewModel.cameraManager.currentFrameRate
                                                            showFrameRatePicker = true
                                                        }) {
                                                            VStack(spacing: 2) {
                                                                Image(systemName: "speedometer")
                                                                    .font(.system(size: 18))
                                                                Text("帧率")
                                                                    .font(.system(size: 8))
                                                            }
                                                            .foregroundColor(.white)
                                                            .frame(width: 50, height: 50)
                                                            .background(Color.black.opacity(0.6))
                                                            .clipShape(Circle())
                                                        }
                                                    }
                                                    
                                                    // 第二排：原有按钮
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
                                                    
                                                    // Filter button
                                                    Button(action: {
                                                        switchFilter()
                                                    }) {
                                                        Image(systemName: "camera.filters")
                                                            .font(.system(size: 26))
                                                            .foregroundColor(.white)
                                                            .frame(width: 56, height: 56)
                                                            .background(Color.black.opacity(0.6))
                                                            .clipShape(Circle())
                                                    }
                                                    .id(viewModel.cameraManager.currentFilter.rawValue)
                                                    
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
                                                }
                                                .padding(.bottom, 30)
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
                            // 竖屏布局
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
            
            // Camera mode switch button for portrait (left top corner)
            if viewModel.uiVisibilityManager.isUIVisible && viewModel.uiVisibilityManager.isPreviewVisible {
                GeometryReader { geometry in
                    let isLandscape = geometry.size.width > geometry.size.height
                    
                    if !isLandscape {
                        // 竖屏：左上角
                        VStack {
                            HStack {
                                Button(action: {
                                    switchCameraMode()
                                }) {
                                    Image(systemName: viewModel.cameraManager.cameraMode.iconName)
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
            
            // Focus indicator - shows when user taps to focus
            if showFocusIndicator, let point = focusPoint {
                FocusIndicator(position: point)
                    .allowsHitTesting(false)
                    .id(point.x + point.y)  // Force recreation on new tap
            }
            
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
            
            // Resolution picker
            if showResolutionPicker {
                PickerOverlay(
                    title: "选择分辨率",
                    options: VideoResolution.getSupportedResolutions(),
                    selection: $selectedResolution,
                    onConfirm: {
                        // Only apply if different from current
                        if selectedResolution != viewModel.cameraManager.currentResolution {
                            handleResolutionChange(selectedResolution)
                        }
                        showResolutionPicker = false
                    },
                    onCancel: {
                        // Reset to current value and close
                        selectedResolution = viewModel.cameraManager.currentResolution
                        showResolutionPicker = false
                    },
                    displayName: { $0.displayName }
                )
            }
            
            // Frame rate picker
            if showFrameRatePicker {
                FrameRatePickerOverlay(
                    title: "选择帧率",
                    options: FrameRate.getSupportedFrameRates(),
                    selection: $selectedFrameRate,
                    onConfirm: {
                        // Only apply if different from current
                        if selectedFrameRate != viewModel.cameraManager.currentFrameRate {
                            handleFrameRateChange(selectedFrameRate)
                        }
                        showFrameRatePicker = false
                    },
                    onCancel: {
                        // Reset to current value and close
                        selectedFrameRate = viewModel.cameraManager.currentFrameRate
                        showFrameRatePicker = false
                    }
                )
            }
            
            // Settings change alert
            if showSettingsChangeAlert {
                SettingsChangeAlert(
                    message: settingsChangeMessage,
                    onDismiss: {
                        showSettingsChangeAlert = false
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
    
    // Switch camera mode (front only / back only / dual)
    private func switchCameraMode() {
        print("🔄 ContentView: Switching camera mode...")
        
        let allModes: [CameraMode] = [.dual, .backOnly, .frontOnly]
        let currentIndex = allModes.firstIndex(of: viewModel.cameraManager.cameraMode) ?? 0
        let nextIndex = (currentIndex + 1) % allModes.count
        let newMode = allModes[nextIndex]
        
        print("🔄 ContentView: Mode changing from \(viewModel.cameraManager.cameraMode.displayName) to \(newMode.displayName)")
        
        // Stop current session
        viewModel.cameraManager.stopSession()
        
        // Update mode
        viewModel.cameraManager.cameraMode = newMode
        
        // Restart session with new mode and force preview rebuild
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            viewModel.cameraManager.setupSession(forceReconfigure: true)
            previewRefreshID = UUID()
            print("🔄 ContentView: ✅ Camera mode switched to \(newMode.displayName)")
        }
    }
    
    // Switch filter (cycle through all filters)
    private func switchFilter() {
        let allFilters = FilterStyle.allCases
        let currentIndex = allFilters.firstIndex(of: viewModel.cameraManager.currentFilter) ?? 0
        let nextIndex = (currentIndex + 1) % allFilters.count
        let nextFilter = allFilters[nextIndex]
        
        print("🎨 ContentView: Switching filter from \(viewModel.cameraManager.currentFilter.displayName) to \(nextFilter.displayName)")
        
        // Direct assignment without animation for instant response
        viewModel.cameraManager.currentFilter = nextFilter
        
        // Provide haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        
        print("🎨 ContentView: ✅ Filter switched to \(nextFilter.displayName)")
    }
    
    // Handle resolution change
    private func handleResolutionChange(_ resolution: VideoResolution) {
        viewModel.cameraManager.setResolution(resolution)
        
        settingsChangeMessage = "分辨率：\(resolution.displayName)"
        withAnimation {
            showSettingsChangeAlert = true
        }
    }
    
    // Handle frame rate change
    private func handleFrameRateChange(_ frameRate: FrameRate) {
        viewModel.cameraManager.setFrameRate(frameRate)
        
        settingsChangeMessage = "帧率：\(frameRate.displayName)"
        withAnimation {
            showSettingsChangeAlert = true
        }
    }
    
    // Handle tap to focus
    private func handleTapToFocus(at location: CGPoint) {
        print("👆 ContentView: Tap to focus at (\(location.x), \(location.y))")
        
        // Get screen bounds
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = windowScene.windows.first else {
            print("⚠️ ContentView: Could not get window bounds")
            return
        }
        
        let screenSize = window.bounds.size
        
        // Convert tap location to normalized coordinates (0.0 to 1.0)
        // Camera coordinates have origin at top-left
        let normalizedPoint = CGPoint(
            x: location.x / screenSize.width,
            y: location.y / screenSize.height
        )
        
        print("👆 ContentView: Normalized focus point: (\(normalizedPoint.x), \(normalizedPoint.y))")
        
        // Show focus indicator at tap location
        focusPoint = location
        showFocusIndicator = true
        
        // Hide indicator after animation completes
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            showFocusIndicator = false
        }
        
        // Trigger focus and exposure in camera manager (runs on background queue)
        viewModel.cameraManager.focusAndExpose(at: normalizedPoint)
        
        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        
        // User interaction - reset UI hide timer
        viewModel.uiVisibilityManager.userDidInteract()
    }
}

#Preview {
    ContentView()
}
