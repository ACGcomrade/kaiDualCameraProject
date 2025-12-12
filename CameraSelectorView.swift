import SwiftUI
import AVFoundation
import Combine

/// Optimized camera selector - ONE camera session at a time
struct CameraSelectorView: View {
    @StateObject private var viewer = OptimizedCameraViewer()
    @Environment(\.dismiss) var dismiss
    
    let isCameraActive: Bool  // 传入参数：摄像头是否激活
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if viewer.cameras.isEmpty {
                    VStack(spacing: 20) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                        
                        Text("正在检测摄像头...")
                            .foregroundColor(.white)
                            .font(.headline)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            // Warning message when camera is inactive
                            if !isCameraActive {
                                VStack(spacing: 8) {
                                    Image(systemName: "video.slash.fill")
                                        .font(.system(size: 40))
                                        .foregroundColor(.yellow)
                                    
                                    Text("主摄像头已暂停")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    Text("预览功能不可用")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                        .multilineTextAlignment(.center)
                                }
                                .padding()
                                .background(Color.yellow.opacity(0.2))
                                .cornerRadius(12)
                                .padding(.horizontal)
                                .padding(.top)
                            }
                            
                            // Camera list with previews
                            if !viewer.backCameras.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("后置摄像头")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                        .padding(.horizontal)
                                    
                                    ForEach(viewer.backCameras) { camera in
                                        CameraPreviewRow(
                                            camera: camera,
                                            isSelected: viewer.currentCamera?.id == camera.id,
                                            session: viewer.currentCamera?.id == camera.id ? viewer.currentSession : nil,
                                            isCameraActive: isCameraActive,
                                            onSelect: {
                                                if isCameraActive, let index = viewer.cameras.firstIndex(where: { $0.id == camera.id }) {
                                                    viewer.switchTo(index: index)
                                                }
                                            }
                                        )
                                        .padding(.horizontal)
                                    }
                                }
                                .padding(.top)
                            }
                            
                            if !viewer.frontCameras.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("前置摄像头")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                        .padding(.horizontal)
                                    
                                    ForEach(viewer.frontCameras) { camera in
                                        CameraPreviewRow(
                                            camera: camera,
                                            isSelected: viewer.currentCamera?.id == camera.id,
                                            session: viewer.currentCamera?.id == camera.id ? viewer.currentSession : nil,
                                            isCameraActive: isCameraActive,
                                            onSelect: {
                                                if isCameraActive, let index = viewer.cameras.firstIndex(where: { $0.id == camera.id }) {
                                                    viewer.switchTo(index: index)
                                                }
                                            }
                                        )
                                        .padding(.horizontal)
                                    }
                                }
                                .padding(.top)
                            }
                            
                            Spacer().frame(height: 40)
                        }
                    }
                }
            }
            .navigationTitle("摄像头列表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .preferredColorScheme(.dark)
        }
        .onAppear {
            if isCameraActive {
                viewer.start()
            } else {
                viewer.detectCamerasOnly()
            }
        }
        .onDisappear {
            viewer.stop()
        }
    }
}

/// Camera preview row - shows button with preview below
struct CameraPreviewRow: View {
    let camera: CameraDeviceInfo
    let isSelected: Bool
    let session: AVCaptureSession?
    let isCameraActive: Bool
    let onSelect: () -> Void
    
    var body: some View {
        VStack(spacing: 12) {
            // Selection button
            Button(action: onSelect) {
                HStack(spacing: 16) {
                    // Camera icon
                    ZStack {
                        Circle()
                            .fill(isSelected && isCameraActive ? Color.blue : Color.white.opacity(0.2))
                            .frame(width: 50, height: 50)
                        
                        Image(systemName: iconName)
                            .font(.system(size: 20))
                            .foregroundColor(.white)
                    }
                    
                    // Camera info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(camera.displayName)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                        
                        Text(camera.focalLength)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    
                    Spacer()
                    
                    // Selection indicator
                    if isSelected && isCameraActive {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.blue)
                            .font(.title3)
                    } else if !isCameraActive {
                        Image(systemName: "video.slash")
                            .foregroundColor(.gray)
                            .font(.body)
                    } else {
                        Image(systemName: "circle")
                            .foregroundColor(.gray)
                            .font(.title3)
                    }
                }
                .padding(12)
                .background(Color.white.opacity(isSelected && isCameraActive ? 0.15 : 0.05))
                .cornerRadius(12)
            }
            .disabled(!isCameraActive)
            
            // Preview (only for selected camera when active)
            if isSelected && isCameraActive {
                ZStack {
                    Color.black
                    
                    if let session = session, session.isRunning {
                        CameraPreviewLayer(session: session)
                            .aspectRatio(4/3, contentMode: .fit)
                            .cornerRadius(12)
                    } else {
                        VStack(spacing: 12) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.5)
                            Text("加载中...")
                                .foregroundColor(.gray)
                                .font(.caption)
                        }
                    }
                }
                .frame(height: 250)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.blue, lineWidth: 2)
                )
            }
        }
        .padding(12)
        .background(Color.white.opacity(isSelected ? 0.1 : 0.05))
        .cornerRadius(16)
    }
    
    private var iconName: String {
        switch camera.deviceType {
        case .builtInUltraWideCamera:
            return "arrow.down.left.and.arrow.up.right"
        case .builtInWideAngleCamera:
            return "camera.fill"
        case .builtInTelephotoCamera:
            return "arrow.up.left.and.arrow.down.right"
        case .builtInTrueDepthCamera:
            return "camera.fill"
        default:
            return "camera"
        }
    }
}

/// Optimized camera viewer - ONE session at a time to prevent resource exhaustion
class OptimizedCameraViewer: ObservableObject {
    @Published var cameras: [CameraDeviceInfo] = []
    @Published var backCameras: [CameraDeviceInfo] = []
    @Published var frontCameras: [CameraDeviceInfo] = []
    @Published var currentIndex: Int = 0
    @Published var currentSession: AVCaptureSession?
    
    var currentCamera: CameraDeviceInfo? {
        guard currentIndex < cameras.count else { return nil }
        return cameras[currentIndex]
    }
    
    private let queue = DispatchQueue(label: "optimizedCameraViewerQueue", qos: .userInitiated)
    
    /// Detect cameras without starting any sessions
    func detectCamerasOnly() {
        print("📷 OptimizedCameraViewer: Detecting cameras (no sessions)...")
        cameras = CameraDeviceDetector.getAllAvailableCameras()
        backCameras = cameras.filter { $0.position == .back }
        frontCameras = cameras.filter { $0.position == .front }
        print("📷 Found \(cameras.count) cameras (\(backCameras.count) back, \(frontCameras.count) front)")
    }
    
    /// Start with first camera
    func start() {
        print("📷 OptimizedCameraViewer: Starting...")
        detectCamerasOnly()
        
        // Start first camera session
        if !cameras.isEmpty {
            switchTo(index: 0)
        }
    }
    
    /// Switch to specific camera index
    func switchTo(index: Int) {
        guard index < cameras.count else { return }
        
        let camera = cameras[index]
        print("📷 Switching to: \(camera.displayName)")
        
        currentIndex = index
        
        // CRITICAL: Stop current session SYNCHRONOUSLY and wait for completion
        if let oldSession = currentSession, oldSession.isRunning {
            print("📷 Stopping previous session...")
            oldSession.stopRunning()
            print("✅ Previous session stopped")
            
            // Clear current session immediately
            DispatchQueue.main.async {
                self.currentSession = nil
            }
            
            // Wait 200ms for complete cleanup
            Thread.sleep(forTimeInterval: 0.2)
        }
        
        // Now start new session on background queue
        queue.async {
            self.startSession(for: camera)
        }
    }
    
    private func startSession(for camera: CameraDeviceInfo) {
        print("📷 Starting session for: \(camera.displayName)")
        
        let session = AVCaptureSession()
        session.beginConfiguration()
        
        // Use ULTRA LOW preset for minimal resource usage
        if session.canSetSessionPreset(.cif352x288) {
            session.sessionPreset = .cif352x288  // 352x288 - ultra low
            print("   Using CIF 352x288 (ultra low)")
        } else if session.canSetSessionPreset(.vga640x480) {
            session.sessionPreset = .vga640x480  // 640x480
            print("   Using VGA 640x480")
        } else {
            session.sessionPreset = .low
            print("   Using LOW preset")
        }
        
        do {
            // Configure device for low resource usage
            try camera.device.lockForConfiguration()
            
            // Set low frame rate (15 FPS)
            if let format = findLowResourceFormat(for: camera.device) {
                camera.device.activeFormat = format
                camera.device.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: 15)
                camera.device.activeVideoMaxFrameDuration = CMTimeMake(value: 1, timescale: 15)
                print("   Set to 15 FPS")
            }
            
            // CRITICAL: Disable auto focus and exposure to reduce CPU usage
            // Front camera may not support all modes, check first
            if camera.device.isFocusModeSupported(.locked) {
                camera.device.focusMode = .locked
                print("   Auto focus DISABLED (locked)")
            } else if camera.device.isFocusModeSupported(.autoFocus) {
                camera.device.focusMode = .autoFocus
                print("   Focus mode: autoFocus (locked not supported)")
            }
            
            if camera.device.isExposureModeSupported(.locked) {
                camera.device.exposureMode = .locked
                print("   Auto exposure DISABLED (locked)")
            } else if camera.device.isExposureModeSupported(.continuousAutoExposure) {
                camera.device.exposureMode = .continuousAutoExposure
                print("   Exposure mode: continuousAutoExposure (locked not supported)")
            }
            
            if camera.device.isWhiteBalanceModeSupported(.locked) {
                camera.device.whiteBalanceMode = .locked
                print("   Auto white balance DISABLED (locked)")
            } else if camera.device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                camera.device.whiteBalanceMode = .continuousAutoWhiteBalance
                print("   White balance: continuousAutoWhiteBalance (locked not supported)")
            }
            
            camera.device.unlockForConfiguration()
            
            // Add input
            let input = try AVCaptureDeviceInput(device: camera.device)
            
            if session.canAddInput(input) {
                session.addInput(input)
                session.commitConfiguration()
                
                // Update on main thread
                DispatchQueue.main.async {
                    self.currentSession = session
                }
                
                // Start session
                session.startRunning()
                
                // Verify after short delay
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if session.isRunning {
                        print("✅ Session running for: \(camera.displayName)")
                    } else {
                        print("❌ Session failed to start for: \(camera.displayName)")
                    }
                }
            } else {
                print("❌ Cannot add input for: \(camera.displayName)")
                session.commitConfiguration()
            }
        } catch {
            print("❌ Error starting session: \(error.localizedDescription)")
            session.commitConfiguration()
        }
    }
    
    private func findLowResourceFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        var bestFormat: AVCaptureDevice.Format?
        var minPixels: Int32 = Int32.max
        
        for format in device.formats {
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            let pixels = dimensions.width * dimensions.height
            
            // Prefer 480p or lower (200K-500K pixels)
            if pixels < minPixels && pixels >= 200_000 && pixels <= 500_000 {
                minPixels = pixels
                bestFormat = format
            }
        }
        
        return bestFormat
    }
    
    /// Stop all sessions
    func stop() {
        print("📷 OptimizedCameraViewer: Stopping...")
        
        if let session = currentSession, session.isRunning {
            queue.async {
                session.stopRunning()
                print("✅ Session stopped")
            }
        }
        
        currentSession = nil
    }
    
    deinit {
        stop()
    }
}

/// UIViewRepresentable for camera preview layer
struct CameraPreviewLayer: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        
        context.coordinator.previewLayer = previewLayer
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.previewLayer?.frame = uiView.bounds
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator {
        var previewLayer: AVCaptureVideoPreviewLayer?
    }
}

#Preview("Camera Active") {
    CameraSelectorView(isCameraActive: true)
}

#Preview("Camera Inactive") {
    CameraSelectorView(isCameraActive: false)
}
