import SwiftUI
import AVFoundation
import Combine

/// Optimized camera viewer - ONE camera at a time to avoid overload
struct AllCamerasGridView: View {
    @ObservedObject var viewModel: CameraViewModel
    @Environment(\.dismiss) var dismiss
    
    @StateObject private var cameraViewer = SingleCameraViewer()
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Title bar
                HStack {
                    Text("所有摄像头")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button("完成") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .padding(.trailing, 20)
                }
                .padding(.top, 60)
                .padding(.leading, 20)
                .padding(.bottom, 20)
                
                if cameraViewer.cameras.isEmpty {
                    VStack(spacing: 20) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                        Text("正在检测摄像头...")
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 0) {
                        // Large preview of current camera
                        ZStack {
                            Color.black
                            
                            if let session = cameraViewer.currentSession, session.isRunning {
                                OptimizedCameraPreview(session: session)
                                    .aspectRatio(4/3, contentMode: .fit)
                            } else {
                                VStack(spacing: 16) {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                        .scaleEffect(1.5)
                                    Text("加载中...")
                                        .foregroundColor(.gray)
                                }
                            }
                        }
                        .frame(height: 300)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                        
                        // Current camera info
                        if let current = cameraViewer.currentCamera {
                            VStack(spacing: 8) {
                                Text(current.displayName)
                                    .font(.title3)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                
                                Text(current.focalLength)
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                            }
                            .padding(.bottom, 20)
                        }
                        
                        // Camera switcher buttons
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(Array(cameraViewer.cameras.enumerated()), id: \.element.id) { index, camera in
                                    CameraSwitchButton(
                                        camera: camera,
                                        isSelected: index == cameraViewer.currentIndex,
                                        action: {
                                            cameraViewer.switchTo(index: index)
                                        }
                                    )
                                }
                            }
                            .padding(.horizontal, 20)
                        }
                        .padding(.bottom, 30)
                        
                        Spacer()
                    }
                }
            }
        }
        .onAppear {
            cameraViewer.start()
        }
        .onDisappear {
            cameraViewer.stop()
        }
    }
}

/// Camera switch button
struct CameraSwitchButton: View {
    let camera: CameraDeviceInfo
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.blue : Color.white.opacity(0.2))
                        .frame(width: 60, height: 60)
                    
                    Image(systemName: iconName)
                        .font(.system(size: 24))
                        .foregroundColor(.white)
                }
                
                Text(shortName)
                    .font(.caption)
                    .foregroundColor(isSelected ? .white : .gray)
            }
        }
    }
    
    private var shortName: String {
        // Simplify name for button
        if camera.position == .front {
            return "前置"
        }
        switch camera.deviceType {
        case .builtInUltraWideCamera:
            return "超广角"
        case .builtInWideAngleCamera:
            return "广角"
        case .builtInTelephotoCamera:
            return "长焦"
        default:
            return "摄像头"
        }
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

/// Optimized camera preview
struct OptimizedCameraPreview: UIViewRepresentable {
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

/// Single camera viewer - ONLY ONE session at a time
class SingleCameraViewer: ObservableObject {
    @Published var cameras: [CameraDeviceInfo] = []
    @Published var currentIndex: Int = 0
    @Published var currentSession: AVCaptureSession?
    
    var currentCamera: CameraDeviceInfo? {
        guard currentIndex < cameras.count else { return nil }
        return cameras[currentIndex]
    }
    
    private let queue = DispatchQueue(label: "singleCameraQueue", qos: .userInitiated)
    
    func start() {
        print("📷 SingleCameraViewer: Starting...")
        
        // Detect cameras
        cameras = CameraDeviceDetector.getAllAvailableCameras()
        print("📷 Found \(cameras.count) cameras")
        
        // Start first camera
        if !cameras.isEmpty {
            switchTo(index: 0)
        }
    }
    
    func switchTo(index: Int) {
        guard index < cameras.count else { return }
        
        print("📷 Switching to camera \(index): \(cameras[index].displayName)")
        
        currentIndex = index
        
        // CRITICAL: Stop current session SYNCHRONOUSLY to avoid black screen
        if let oldSession = currentSession, oldSession.isRunning {
            print("📷 Stopping old session synchronously...")
            oldSession.stopRunning()
            print("✅ Old session stopped")
            
            // Clear immediately
            DispatchQueue.main.async {
                self.currentSession = nil
            }
            
            // Brief pause for cleanup
            Thread.sleep(forTimeInterval: 0.2)
        }
        
        // Start new session
        queue.async {
            self.startSession(for: self.cameras[index])
        }
    }
    
    private func startSession(for camera: CameraDeviceInfo) {
        print("📷 Starting session for: \(camera.displayName)")
        
        let session = AVCaptureSession()
        
        // Begin configuration
        session.beginConfiguration()
        
        // Use LOWEST possible preset
        if session.canSetSessionPreset(.cif352x288) {
            session.sessionPreset = .cif352x288  // 352x288 - 超低
            print("   Using CIF 352x288 preset (ultra low)")
        } else if session.canSetSessionPreset(.vga640x480) {
            session.sessionPreset = .vga640x480
            print("   Using VGA 640x480 preset")
        } else {
            session.sessionPreset = .low
            print("   Using LOW preset")
        }
        
        do {
            // CRITICAL: Configure device to disable auto focus/exposure
            try camera.device.lockForConfiguration()
            
            // Disable auto focus to reduce CPU usage (front camera may not support locked)
            if camera.device.isFocusModeSupported(.locked) {
                camera.device.focusMode = .locked
                print("   Auto focus DISABLED (locked)")
            } else if camera.device.isFocusModeSupported(.autoFocus) {
                camera.device.focusMode = .autoFocus
                print("   Focus mode: autoFocus (locked not supported)")
            }
            
            // Disable auto exposure
            if camera.device.isExposureModeSupported(.locked) {
                camera.device.exposureMode = .locked
                print("   Auto exposure DISABLED (locked)")
            } else if camera.device.isExposureModeSupported(.continuousAutoExposure) {
                camera.device.exposureMode = .continuousAutoExposure
                print("   Exposure mode: continuousAutoExposure (locked not supported)")
            }
            
            // Disable auto white balance
            if camera.device.isWhiteBalanceModeSupported(.locked) {
                camera.device.whiteBalanceMode = .locked
                print("   Auto white balance DISABLED (locked)")
            } else if camera.device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                camera.device.whiteBalanceMode = .continuousAutoWhiteBalance
                print("   White balance: continuousAutoWhiteBalance (locked not supported)")
            }
            
            // Set 15 FPS for lower CPU usage
            camera.device.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: 15)
            camera.device.activeVideoMaxFrameDuration = CMTimeMake(value: 1, timescale: 15)
            print("   Frame rate set to 15 FPS")
            
            camera.device.unlockForConfiguration()
            
            // Create input
            let input = try AVCaptureDeviceInput(device: camera.device)
            
            // Try to add input
            if session.canAddInput(input) {
                session.addInput(input)
                print("   Input added successfully")
            } else {
                print("❌ Cannot add input")
                session.commitConfiguration()
                return
            }
            
            // Commit configuration
            session.commitConfiguration()
            print("   Configuration committed")
            
            // Update on main thread
            DispatchQueue.main.async {
                self.currentSession = session
            }
            
            // Start running
            session.startRunning()
            
            // Verify
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if session.isRunning {
                    print("✅ Session running successfully")
                } else {
                    print("⚠️ Session not running")
                }
            }
            
        } catch {
            print("❌ Error: \(error.localizedDescription)")
            session.commitConfiguration()
        }
    }
    
    func stop() {
        print("📷 SingleCameraViewer: Stopping...")
        
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

#Preview {
    AllCamerasGridView(viewModel: CameraViewModel())
}
