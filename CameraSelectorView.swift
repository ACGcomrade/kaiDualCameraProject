import SwiftUI
import SwiftUI
import AVFoundation
import Combine

/// Camera selector menu with live previews
struct CameraSelectorView: View {
    @StateObject private var viewModel = CameraSelectorViewModel()
    @Environment(\.dismiss) var dismiss
    
    let isCameraActive: Bool  // 传入参数：摄像头是否激活
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if viewModel.cameras.isEmpty {
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
                                    
                                    Text("摄像头已暂停")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    
                                    Text("当前画面已冻结，预览不可用")
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
                            
                            // Section: 后置摄像头
                            if !viewModel.backCameras.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("后置摄像头")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                        .padding(.horizontal)
                                    
                                    ForEach(viewModel.backCameras) { camera in
                                        CameraPreviewCard(
                                            camera: camera,
                                            previewSession: isCameraActive ? viewModel.getPreviewSession(for: camera) : nil,
                                            showPlaceholder: !isCameraActive
                                        )
                                        .padding(.horizontal)
                                    }
                                }
                                .padding(.top)
                            }
                            
                            // Section: 前置摄像头
                            if !viewModel.frontCameras.isEmpty {
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("前置摄像头")
                                        .font(.title2)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                        .padding(.horizontal)
                                    
                                    ForEach(viewModel.frontCameras) { camera in
                                        CameraPreviewCard(
                                            camera: camera,
                                            previewSession: isCameraActive ? viewModel.getPreviewSession(for: camera) : nil,
                                            showPlaceholder: !isCameraActive
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
            .navigationTitle("选择摄像头")
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
            viewModel.detectCameras(startPreviews: isCameraActive)
        }
        .onDisappear {
            viewModel.stopAllPreviews()
        }
    }
}

/// Single camera preview card
struct CameraPreviewCard: View {
    let camera: CameraDeviceInfo
    let previewSession: AVCaptureSession?
    let showPlaceholder: Bool  // 是否显示占位符（黑屏）
    
    var body: some View {
        VStack(spacing: 8) {
            // Live preview or placeholder
            ZStack {
                Color.black
                
                if showPlaceholder {
                    // Show placeholder when camera is inactive
                    VStack(spacing: 12) {
                        Image(systemName: "video.slash")
                            .font(.system(size: 50))
                            .foregroundColor(.gray)
                        
                        Text("预览不可用")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                } else if let session = previewSession {
                    CameraPreviewLayer(session: session)
                        .aspectRatio(4/3, contentMode: .fit)
                        .cornerRadius(12)
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                }
            }
            .frame(height: 200)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.3), lineWidth: 1)
            )
            
            // Camera info
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(camera.displayName)
                        .font(.headline)
                        .foregroundColor(.white)
                    
                    Text(camera.focalLength)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    
                    Text(camera.typeName)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                // Selection indicator (future feature)
                Image(systemName: "checkmark.circle")
                    .font(.title2)
                    .foregroundColor(.blue)
                    .opacity(0) // Hidden for now
            }
            .padding(.horizontal, 8)
        }
        .padding(12)
        .background(Color.white.opacity(0.1))
        .cornerRadius(16)
    }
}

/// UIViewRepresentable for camera preview
struct CameraPreviewLayer: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.addSublayer(previewLayer)
        
        // Store layer in context for updates
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

/// ViewModel for camera selector
class CameraSelectorViewModel: ObservableObject {
    @Published var cameras: [CameraDeviceInfo] = []
    @Published var backCameras: [CameraDeviceInfo] = []
    @Published var frontCameras: [CameraDeviceInfo] = []
    
    private var previewSessions: [String: AVCaptureSession] = [:]
    private let sessionQueue = DispatchQueue(label: "cameraSelectorQueue")
    
    func detectCameras(startPreviews: Bool = true) {
        print("📷 CameraSelectorViewModel: Detecting cameras... (startPreviews: \(startPreviews))")
        
        sessionQueue.async {
            let allCameras = CameraDeviceDetector.getAllAvailableCameras()
            
            DispatchQueue.main.async {
                self.cameras = allCameras
                self.backCameras = allCameras.filter { $0.position == .back }
                self.frontCameras = allCameras.filter { $0.position == .front }
                
                print("📷 CameraSelectorViewModel: Found \(self.backCameras.count) back cameras, \(self.frontCameras.count) front cameras")
                
                // Only start previews if camera is active
                if startPreviews {
                    print("📷 CameraSelectorViewModel: Starting previews for all cameras")
                    self.startPreviewsForAllCameras()
                } else {
                    print("📷 CameraSelectorViewModel: Skipping previews (camera inactive)")
                }
            }
        }
    }
    
    private func startPreviewsForAllCameras() {
        for camera in cameras {
            startPreview(for: camera)
        }
    }
    
    private func startPreview(for camera: CameraDeviceInfo) {
        sessionQueue.async {
            print("📷 Starting preview for: \(camera.displayName)")
            
            let session = AVCaptureSession()
            session.sessionPreset = .medium // Use medium quality for previews
            
            do {
                // Add camera input
                let input = try AVCaptureDeviceInput(device: camera.device)
                
                if session.canAddInput(input) {
                    session.addInput(input)
                    
                    // Start session
                    session.startRunning()
                    
                    DispatchQueue.main.async {
                        self.previewSessions[camera.id] = session
                        print("✅ Preview started for: \(camera.displayName)")
                    }
                } else {
                    print("❌ Cannot add input for: \(camera.displayName)")
                }
            } catch {
                print("❌ Error starting preview for \(camera.displayName): \(error)")
            }
        }
    }
    
    func getPreviewSession(for camera: CameraDeviceInfo) -> AVCaptureSession? {
        return previewSessions[camera.id]
    }
    
    func stopAllPreviews() {
        print("📷 CameraSelectorViewModel: Stopping all previews...")
        
        sessionQueue.async {
            for (id, session) in self.previewSessions {
                if session.isRunning {
                    session.stopRunning()
                    print("   Stopped preview: \(id)")
                }
            }
            
            DispatchQueue.main.async {
                self.previewSessions.removeAll()
            }
        }
    }
    
    deinit {
        stopAllPreviews()
    }
}

#Preview("Camera Active") {
    CameraSelectorView(isCameraActive: true)
}

#Preview("Camera Inactive") {
    CameraSelectorView(isCameraActive: false)
}
