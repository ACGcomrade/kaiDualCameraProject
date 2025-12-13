import AVFoundation
import UIKit
import Combine
import Photos

class CameraManager: NSObject, ObservableObject {
    // Shared singleton for lightweight preview consumers
    static let shared = CameraManager()
    // MARK: - Properties
    @Published var session: AVCaptureMultiCamSession?
    private let sessionQueue = DispatchQueue(label: "sessionQueue", qos: .userInitiated)
    private let backVideoDataQueue = DispatchQueue(label: "backVideoDataQueue", qos: .userInitiated)
    private let frontVideoDataQueue = DispatchQueue(label: "frontVideoDataQueue", qos: .userInitiated)
    private let audioDataQueue = DispatchQueue(label: "audioDataQueue", qos: .utility)
    private let settings = CameraSettings.shared
    // Reusable CIContext for converting sample buffers to UIImage (expensive to create repeatedly)
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])  // Use GPU for better performance
    // How many frames between published preview image updates (reduce CPU by updating less frequently)
    private let previewFrameInterval = 8  // Increased from 6 to reduce CPU load by ~30%
    
    @Published var capturedBackImage: UIImage? = nil
    @Published var capturedFrontImage: UIImage? = nil
    @Published var isFlashOn = false
    @Published var isDualCameraMode = true
    @Published var cameraMode: CameraMode = .dual  // Current camera mode
    @Published var currentFilter: FilterStyle = .none  // Current filter style
    @Published var isSessionRunning = false
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var zoomFactor: CGFloat = 1.0
    @Published var currentResolution: VideoResolution = .resolution_1080p  // Current video resolution
    @Published var currentFrameRate: FrameRate = .fps_30  // Current frame rate
    
    var backCameraInput: AVCaptureDeviceInput?
    var frontCameraInput: AVCaptureDeviceInput?
    var audioInput: AVCaptureDeviceInput?
    
    // Frame capture - stores latest frames from live preview
    private var lastBackFrame: CMSampleBuffer?
    private var lastFrontFrame: CMSampleBuffer?
    private let frameLock = NSLock()
    private var backFrameCount: Int = 0
    private var frontFrameCount: Int = 0
    
    // Video data outputs for frame capture
    private var backVideoDataOutput: AVCaptureVideoDataOutput?
    private var frontVideoDataOutput: AVCaptureVideoDataOutput?
    private var audioDataOutput: AVCaptureAudioDataOutput?
    
    // Video recording with AVAssetWriter
    private var backVideoWriter: AVAssetWriter?
    private var frontVideoWriter: AVAssetWriter?
    private var audioWriter: AVAssetWriter?
    private var backVideoWriterInput: AVAssetWriterInput?
    private var frontVideoWriterInput: AVAssetWriterInput?
    private var audioWriterInput: AVAssetWriterInput?
    private var recordingStartTime: CMTime?
    private var recordingTimer: Timer?
    private var backOutputURL: URL?
    private var frontOutputURL: URL?
    private var audioOutputURL: URL?
    
    // Session start flags
    private var backWriterSessionStarted = false
    private var frontWriterSessionStarted = false
    private var audioWriterSessionStarted = false
    
    private var backPreviewLayer: AVCaptureVideoPreviewLayer?
    private var frontPreviewLayer: AVCaptureVideoPreviewLayer?
    
    // Zoom constraints
    @Published var minZoomFactor: CGFloat = 1.0
    @Published var maxZoomFactor: CGFloat = 5.0
    
    // Focal length mapping
    var cameraInfo: FocalLengthMapper.CameraInfo?
    
    // SAFETY: Prevent infinite loop in session setup
    private var isConfiguringSession = false
    
    // Session state management (avoid re-initialization)
    private var isSessionConfigured = false
    
    override init() {
        super.init()
        print("🔵 CameraManager: Initialized")
        
        // Detect camera capabilities and set zoom range (ONE TIME ONLY)
        let capabilities = CameraCapabilityDetector.detectBackCameraZoomCapabilities()
        minZoomFactor = capabilities.minZoom
        maxZoomFactor = capabilities.maxZoom
        zoomFactor = capabilities.defaultZoom
        
        print("🔵 CameraManager: Zoom range set to \(minZoomFactor)x - \(maxZoomFactor)x")
        print("🔵 CameraManager: Ready for session setup (will only configure once)")
    }
    
    // MARK: - Multi-Camera Session Setup
    func setupSession(forceReconfigure: Bool = false) {
        print("🎥 CameraManager: setupSession called (forceReconfigure: \(forceReconfigure))")
        
        // OPTIMIZATION: Only configure once unless forced!
        if !forceReconfigure && isSessionConfigured && session != nil {
            print("✅ CameraManager: Session already configured - reusing existing session")
            
            if !session!.isRunning {
                sessionQueue.async {
                    self.session?.startRunning()
                    DispatchQueue.main.async {
                        self.isSessionRunning = true
                    }
                    print("✅ CameraManager: Restarted existing session")
                }
            } else {
                print("✅ CameraManager: Session already running")
            }
            return
        }
        
        // Force reconfiguration if mode changed
        if forceReconfigure {
            print("🔄 CameraManager: Forcing session reconfiguration for mode: \(cameraMode.displayName)")
            isSessionConfigured = false
            session = nil
        }
        
        guard !isConfiguringSession else {
            print("⚠️ CameraManager: Already configuring session, skipping")
            return
        }
        
        isConfiguringSession = true
        
        // Setup session on background queue
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Check if device supports multi-cam
            guard AVCaptureMultiCamSession.isMultiCamSupported else {
                print("❌ CameraManager: Multi-cam NOT supported on this device")
                self.isConfiguringSession = false
                return
            }
            
            print("✅ CameraManager: Multi-cam IS supported")
            self.configureSession()
            self.isConfiguringSession = false
        }
    }
    
    private func configureSession() {
        print("🎥 CameraManager: configureSession called for mode: \(cameraMode.displayName)")
        
        let newSession = AVCaptureMultiCamSession()
        newSession.beginConfiguration()
        
        // Setup cameras based on mode
        let shouldSetupBack = (cameraMode == .backOnly || cameraMode == .dual)
        let shouldSetupFront = (cameraMode == .frontOnly || cameraMode == .dual)
        
        // Setup back camera with best available camera (ultra-wide if available)
        if shouldSetupBack {
            print("📷 CameraManager: Setting up back camera...")
            if let backCamera = getBestBackCamera() {
            print("📷 CameraManager: Using back camera: \(backCamera.localizedName)")
            print("   Device type: \(backCamera.deviceType.rawValue)")
            print("   Zoom range: \(backCamera.minAvailableVideoZoomFactor)x - \(backCamera.maxAvailableVideoZoomFactor)x")
            
            do {
                let backInput = try AVCaptureDeviceInput(device: backCamera)
                if newSession.canAddInput(backInput) {
                    newSession.addInput(backInput)
                    backCameraInput = backInput
                    print("✅ CameraManager: Back camera input added")
                } else {
                    print("❌ CameraManager: Cannot add back camera input to session")
                }
                
                // Configure for multi-cam compatible format
                if let multiCamFormat = findMultiCamCompatibleFormat(for: backCamera) {
                    try? backCamera.lockForConfiguration()
                    backCamera.activeFormat = multiCamFormat
                    backCamera.unlockForConfiguration()
                    print("✅ CameraManager: Back camera using multi-cam compatible format")
                }
                
                // Add video data output for back camera
                let backVideoOutput = AVCaptureVideoDataOutput()
                backVideoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                backVideoOutput.setSampleBufferDelegate(self, queue: backVideoDataQueue)
                backVideoOutput.alwaysDiscardsLateVideoFrames = true
                
                if newSession.canAddOutput(backVideoOutput) {
                    newSession.addOutput(backVideoOutput)
                    backVideoDataOutput = backVideoOutput
                    print("✅ CameraManager: Back camera video data output added")
                }
                
                // Detect focal length mapping
                self.cameraInfo = FocalLengthMapper.detectCameraInfo(for: backCamera)
                
                // Verify zoom range matches what we detected in init()
                print("✅ CameraManager: Zoom range verification:")
                print("   Detected in init: \(self.minZoomFactor)x - \(self.maxZoomFactor)x")
                print("   Device actual: \(backCamera.minAvailableVideoZoomFactor)x - \(backCamera.maxAvailableVideoZoomFactor)x")
                
                // Set initial zoom to 1.0x (standard wide angle view)
                if backCamera.minAvailableVideoZoomFactor <= 1.0 && backCamera.maxAvailableVideoZoomFactor >= 1.0 {
                    try? backCamera.lockForConfiguration()
                    backCamera.videoZoomFactor = 1.0
                    backCamera.unlockForConfiguration()
                    DispatchQueue.main.async {
                        self.zoomFactor = 1.0
                    }
                    print("✅ CameraManager: Initial zoom set to 1.0x")
                }
            } catch {
                print("❌ CameraManager: Back camera setup failed: \(error.localizedDescription)")
            }
            } else {
                print("❌ CameraManager: Could not get back camera device")
            }
        }
        
        // Setup front camera with video data output
        if shouldSetupFront {
            print("📷 CameraManager: Setting up front camera...")
            if let frontCamera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
            print("📷 CameraManager: Front camera device found: \(frontCamera.localizedName)")
            do {
                let frontInput = try AVCaptureDeviceInput(device: frontCamera)
                if newSession.canAddInput(frontInput) {
                    newSession.addInput(frontInput)
                    frontCameraInput = frontInput
                    print("✅ CameraManager: Front camera input added")
                } else {
                    print("❌ CameraManager: Cannot add front camera input to session")
                }
                
                // Configure for multi-cam compatible format
                if let multiCamFormat = findMultiCamCompatibleFormat(for: frontCamera) {
                    try? frontCamera.lockForConfiguration()
                    frontCamera.activeFormat = multiCamFormat
                    frontCamera.unlockForConfiguration()
                    print("✅ CameraManager: Front camera using multi-cam compatible format")
                } else {
                    print("⚠️ CameraManager: No multi-cam compatible format found for front camera")
                }
                
                // Add video data output for front camera
                let frontVideoOutput = AVCaptureVideoDataOutput()
                frontVideoOutput.videoSettings = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
                ]
                frontVideoOutput.setSampleBufferDelegate(self, queue: frontVideoDataQueue)
                frontVideoOutput.alwaysDiscardsLateVideoFrames = true
                
                if newSession.canAddOutput(frontVideoOutput) {
                    newSession.addOutput(frontVideoOutput)
                    frontVideoDataOutput = frontVideoOutput
                    print("✅ CameraManager: Front camera video data output added")
                } else {
                    print("❌ CameraManager: Cannot add front camera video data output")
                }
            } catch {
                print("❌ CameraManager: Front camera setup failed: \(error.localizedDescription)")
            }
            } else {
                print("❌ CameraManager: Could not get front camera device")
            }
        }
        
        // Setup audio input with audio data output
        print("🎤 CameraManager: Setting up audio input...")
        if let audioDevice = AVCaptureDevice.default(for: .audio) {
            do {
                let audioInput = try AVCaptureDeviceInput(device: audioDevice)
                if newSession.canAddInput(audioInput) {
                    newSession.addInput(audioInput)
                    self.audioInput = audioInput
                    print("✅ CameraManager: Audio input added")
                    
                    // Add audio data output
                    let audioOutput = AVCaptureAudioDataOutput()
                    audioOutput.setSampleBufferDelegate(self, queue: audioDataQueue)
                    
                    if newSession.canAddOutput(audioOutput) {
                        newSession.addOutput(audioOutput)
                        audioDataOutput = audioOutput
                        print("✅ CameraManager: Audio data output added")
                    }
                }
            } catch {
                print("❌ CameraManager: Audio input setup failed: \(error.localizedDescription)")
            }
        } else {
            print("⚠️ CameraManager: Could not get audio device")
        }
        
        newSession.commitConfiguration()
        print("🔧 CameraManager: Session configuration committed")
        
        // DEBUG: Verify outputs and delegates
        print("🔍 CameraManager: Session has \(newSession.outputs.count) outputs")
        for (index, output) in newSession.outputs.enumerated() {
            if let videoOutput = output as? AVCaptureVideoDataOutput {
                print("🔍 CameraManager: Output \(index): AVCaptureVideoDataOutput, delegate: \(videoOutput.sampleBufferDelegate != nil)")
            }
        }
        
        // Assign session to published property FIRST
        DispatchQueue.main.sync {
            print("📱 CameraManager: Assigning session to published property")
            self.session = newSession
        }
        
        // Add session runtime error observer
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionRuntimeError),
            name: AVCaptureSession.runtimeErrorNotification,
            object: newSession
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionWasInterrupted),
            name: AVCaptureSession.wasInterruptedNotification,
            object: newSession
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(sessionInterruptionEnded),
            name: AVCaptureSession.interruptionEndedNotification,
            object: newSession
        )
        
        // Apply current resolution and frame rate settings BEFORE starting session
        print("🎬 CameraManager: Applying current settings - Resolution: \(currentResolution.displayName), FPS: \(currentFrameRate.displayName)")
        
        // Apply to back camera
        if let backDevice = self.backCameraInput?.device {
            self.applyFormatSettings(to: backDevice, resolution: self.currentResolution, frameRate: self.currentFrameRate)
            // Verify it was applied
            let actualFPS = 1.0 / CMTimeGetSeconds(backDevice.activeVideoMinFrameDuration)
            print("✅ Back camera actual FPS after apply: \(actualFPS)")
        }
        
        // Apply to front camera  
        if let frontDevice = self.frontCameraInput?.device {
            self.applyFormatSettings(to: frontDevice, resolution: self.currentResolution, frameRate: self.currentFrameRate)
            // Verify it was applied
            let actualFPS = 1.0 / CMTimeGetSeconds(frontDevice.activeVideoMinFrameDuration)
            print("✅ Front camera actual FPS after apply: \(actualFPS)")
        }
        
        // Start the session on the session queue
        print("▶️ CameraManager: Starting session (on sessionQueue)...")
        print("▶️ CameraManager: Current thread: \(Thread.current)")
        
        newSession.startRunning()
        
        // Check immediately if running (on same queue)
        let isRunning = newSession.isRunning
        let isInterrupted = newSession.isInterrupted
        
        print("✅ CameraManager: startRunning() called")
        print("🔍 CameraManager: Session isRunning = \(isRunning) (checked immediately)")
        print("🔍 CameraManager: Session isInterrupted = \(isInterrupted)")
        
        if !isRunning {
            print("❌ CameraManager: WARNING - Session NOT running after startRunning()!")
            print("❌ CameraManager: This usually means:")
            print("   - Camera permission not granted")
            print("   - Configuration error")
            print("   - Hardware resource conflict")
        }
        
        DispatchQueue.main.async { [weak self] in
            self?.isSessionRunning = isRunning
            self?.isConfiguringSession = false
            print("📱 CameraManager: isSessionRunning = \(isRunning)")
            
            if isRunning {
                print("✅✅✅ CameraManager: Session successfully started and running!")
                // Mark as configured to avoid re-initialization
                self?.isSessionConfigured = true
                print("🔒 CameraManager: Session marked as configured (will be reused)")
            }
        }
        
        // Check again after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak newSession] in
            guard let session = newSession else { return }
            print("🔍 CameraManager: [2s later] Session isRunning = \(session.isRunning)")
            print("🔍 CameraManager: [2s later] Session isInterrupted = \(session.isInterrupted)")
        }
    }
    
    @objc private func sessionRuntimeError(notification: NSNotification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else { return }
        print("❌ CameraManager: Session runtime error: \(error)")
        print("❌ CameraManager: Error code: \(error.code.rawValue)")
        print("❌ CameraManager: Error description: \(error.localizedDescription)")
    }
    
    @objc private func sessionWasInterrupted(notification: NSNotification) {
        print("⚠️ CameraManager: Session was interrupted")
        if let reason = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int {
            print("⚠️ CameraManager: Interruption reason: \(reason)")
        }
    }
    
    @objc private func sessionInterruptionEnded(notification: NSNotification) {
        print("✅ CameraManager: Session interruption ended")
    }
    
    // MARK: - Frame Access for Preview
    func getLatestFrames(completion: @escaping (UIImage?, UIImage?) -> Void) {
        frameLock.lock()
        let backFrame = lastBackFrame
        let frontFrame = lastFrontFrame
        frameLock.unlock()
        
        let backImage = imageFromSampleBuffer(backFrame, isFrontCamera: false)
        let frontImage = imageFromSampleBuffer(frontFrame, isFrontCamera: true)
        
        completion(backImage, frontImage)
    }
    
    // MARK: - TEST: Generate fake frames for UI testing
    func startTestMode() {
        print("🧪 CameraManager: Starting TEST MODE with fake frames")
        
        // Generate test images
        let backTestImage = createTestImage(color: .blue, text: "BACK CAMERA")
        let frontTestImage = createTestImage(color: .green, text: "FRONT CAMERA")
        
        // Simulate frame updates at 15fps (sufficient for preview testing, saves power)
        Timer.scheduledTimer(withTimeInterval: 1.0/15.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // Update test images directly
            DispatchQueue.main.async { [weak self] in
                self?.capturedBackImage = backTestImage
                self?.capturedFrontImage = frontTestImage
            }
        }
        
        DispatchQueue.main.async {
            self.isSessionRunning = true
        }
        
        print("✅ CameraManager: TEST MODE active - preview should show blue/green test patterns")
    }
    
    private func createTestImage(color: UIColor, text: String) -> UIImage {
        let size = CGSize(width: 400, height: 600)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            // Fill background
            color.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            
            // Draw text
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 32),
                .foregroundColor: UIColor.white
            ]
            
            let textSize = (text as NSString).size(withAttributes: attributes)
            let textRect = CGRect(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            
            (text as NSString).draw(in: textRect, withAttributes: attributes)
        }
    }
    
    // MARK: - Photo Capture (Frame Capture - INSTANT!)
    func captureDualPhotos(withFlash: Bool = false, completion: @escaping (UIImage?, UIImage?) -> Void) {
        print("📸 CameraManager: captureDualPhotos called - using frame capture")
        
        // Trigger flash if requested
        if withFlash {
            triggerFlashForCapture()
        }
        
        // Use background queue to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            autoreleasepool {
                guard let self = self else {
                    print("❌ CameraManager: self is nil")
                    DispatchQueue.main.async {
                        completion(nil, nil)
                    }
                    return
                }
                
                self.frameLock.lock()
                let backFrame = self.lastBackFrame
                let frontFrame = self.lastFrontFrame
                let backCount = self.backFrameCount
                let frontCount = self.frontFrameCount
                self.frameLock.unlock()
                
                print("📸 CameraManager: Frame status - Back: \(backFrame != nil) (count: \(backCount)), Front: \(frontFrame != nil) (count: \(frontCount))")
                print("📸 CameraManager: Converting frames to images...")
                let backImage = self.imageFromSampleBuffer(backFrame, isFrontCamera: false)
                let frontImage = self.imageFromSampleBuffer(frontFrame, isFrontCamera: true)
                
                print("📸 CameraManager: Back image: \(backImage != nil), Front image: \(frontImage != nil)")
                
                DispatchQueue.main.async {
                    completion(backImage, frontImage)
                }
            }
        }
    }
    
    // MARK: - Orientation Helpers
    private func getVideoTransform(isFrontCamera: Bool, orientation: UIDeviceOrientation) -> CGAffineTransform {
        var transform = CGAffineTransform.identity
        
        // AVAssetWriterInput的transform需要设置为逆时针旋转角度来修正视频方向
        
        if isFrontCamera {
            // Front camera needs horizontal mirroring + rotation
            switch orientation {
            case .portrait:
                // 竖屏：逆时针90度 + 水平镜像
                transform = CGAffineTransform(rotationAngle: -.pi / 2)
                transform = transform.scaledBy(x: -1, y: 1)
            case .portraitUpsideDown:
                // 倒竖屏：顺时针90度 + 水平镜像
                transform = CGAffineTransform(rotationAngle: .pi / 2)
                transform = transform.scaledBy(x: -1, y: 1)
            case .landscapeLeft:
                // 横屏左：180度 + 水平镜像
                transform = CGAffineTransform(rotationAngle: .pi)
                transform = transform.scaledBy(x: -1, y: 1)
            case .landscapeRight:
                // 横屏右：不旋转 + 水平镜像
                transform = CGAffineTransform(scaleX: -1, y: 1)
            default:
                // 默认竖屏
                transform = CGAffineTransform(rotationAngle: -.pi / 2)
                transform = transform.scaledBy(x: -1, y: 1)
            }
        } else {
            // Back camera - rotate counter-clockwise to correct orientation
            switch orientation {
            case .portrait:
                // 竖屏：逆时针90度
                transform = CGAffineTransform(rotationAngle: -.pi / 2)
            case .portraitUpsideDown:
                // 倒竖屏：顺时针90度
                transform = CGAffineTransform(rotationAngle: .pi / 2)
            case .landscapeLeft:
                // 横屏左：180度
                transform = CGAffineTransform(rotationAngle: .pi)
            case .landscapeRight:
                // 横屏右：不旋转
                transform = CGAffineTransform.identity
            default:
                // 默认竖屏
                transform = CGAffineTransform(rotationAngle: -.pi / 2)
            }
        }
        
        print("🎥 Transform for \(isFrontCamera ? "front" : "back") in \(orientation.rawValue): \(transform)")
        return transform
    }
    
    private func getImageOrientation(isFrontCamera: Bool) -> UIImage.Orientation {
        // Get device orientation
        let deviceOrientation = UIDevice.current.orientation
        
        // Determine image orientation based on device orientation and camera position
        if isFrontCamera {
            // Front camera mirrored behavior
            switch deviceOrientation {
            case .portrait:
                return .leftMirrored  // Portrait mode
            case .portraitUpsideDown:
                return .rightMirrored  // Upside down
            case .landscapeLeft:
                return .downMirrored  // Landscape left
            case .landscapeRight:
                return .upMirrored  // Landscape right
            default:
                return .leftMirrored  // Default to portrait
            }
        } else {
            // Back camera normal behavior
            switch deviceOrientation {
            case .portrait:
                return .right  // Portrait mode (90° CW)
            case .portraitUpsideDown:
                return .left  // Upside down (90° CCW)
            case .landscapeLeft:
                return .up  // Landscape left (0°)
            case .landscapeRight:
                return .down  // Landscape right (180°)
            default:
                return .right  // Default to portrait
            }
        }
    }
    
    private func imageFromSampleBuffer(_ sampleBuffer: CMSampleBuffer?, isFrontCamera: Bool = false) -> UIImage? {
        return autoreleasepool {
            guard let sampleBuffer = sampleBuffer,
                  let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                return nil
            }
            
            // Create CIImage from pixel buffer
            var ciImage = CIImage(cvPixelBuffer: imageBuffer)
            
            // Apply horizontal mirror flip for front camera (left-right flip)
            if isFrontCamera {
                // Get current device orientation
                var orientation = UIDevice.current.orientation
                if !orientation.isValidInterfaceOrientation {
                    orientation = .portrait
                }
                
                // For portrait orientations, flip vertically because the raw image is rotated
                // For landscape orientations, flip horizontally
                let flipTransform: CGAffineTransform
                let center: CGFloat
                let translateToOrigin: CGAffineTransform
                let translateBack: CGAffineTransform
                
                if orientation.isPortrait {
                    // Portrait: flip vertically (Y axis) for left-right mirror effect
                    flipTransform = CGAffineTransform(scaleX: 1, y: -1)
                    center = ciImage.extent.height / 2
                    translateToOrigin = CGAffineTransform(translationX: 0, y: -center)
                    translateBack = CGAffineTransform(translationX: 0, y: center)
                } else {
                    // Landscape: flip horizontally (X axis) for left-right mirror effect
                    flipTransform = CGAffineTransform(scaleX: -1, y: 1)
                    center = ciImage.extent.width / 2
                    translateToOrigin = CGAffineTransform(translationX: -center, y: 0)
                    translateBack = CGAffineTransform(translationX: center, y: 0)
                }
                
                ciImage = ciImage.transformed(by: translateToOrigin)
                    .transformed(by: flipTransform)
                    .transformed(by: translateBack)
            }
            
            // Apply filter BEFORE converting to CGImage for better performance
            if currentFilter != .none {
                ciImage = currentFilter.apply(to: ciImage)
            }
            
            // Convert to CGImage with optimized rect
            let extent = ciImage.extent
            guard let cgImage = self.ciContext.createCGImage(ciImage, from: extent) else {
                return nil
            }
            
            // Return UIImage without orientation (for preview)
            return UIImage(cgImage: cgImage)
        }
    }
    
    // MARK: - Video Recording (Frame Writing - NO FREEZE!)
    func startVideoRecording(completion: @escaping (URL?, URL?, Error?) -> Void) {
        print("🎥 CameraManager: startVideoRecording called")
        
        guard !isRecording else {
            print("⚠️ CameraManager: Already recording")
            return
        }
        
        // Update UI immediately on main thread for instant feedback
        isRecording = true
        recordingDuration = 0
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.recordingDuration += 0.2
        }
        print("✅ CameraManager: isRecording = true (UI updated immediately)")
        
        // Do all heavy work asynchronously
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Create output URLs
            let backURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("back_\(UUID().uuidString)")
                .appendingPathExtension("mov")
            
            let frontURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("front_\(UUID().uuidString)")
                .appendingPathExtension("mov")
            
            let audioURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("audio_\(UUID().uuidString)")
                .appendingPathExtension("m4a")
            
            self.backOutputURL = backURL
            self.frontOutputURL = frontURL
            self.audioOutputURL = audioURL
            
            print("🎥 CameraManager: Back URL: \(backURL)")
            print("🎥 CameraManager: Front URL: \(frontURL)")
            print("🎥 CameraManager: Audio URL: \(audioURL)")
            
            do {
                // Get device orientation for video transform
                // Use validDeviceOrientation to ensure we have a valid orientation
                var deviceOrientation = UIDevice.current.orientation
                if !deviceOrientation.isValidInterfaceOrientation {
                    deviceOrientation = .portrait
                }
                print("🎥 CameraManager: Starting recording with orientation: \(deviceOrientation.rawValue)")
                
                // Create back camera writer with current resolution and frame rate settings
                let backWriter = try AVAssetWriter(url: backURL, fileType: .mov)
                let dimensions = self.currentResolution.dimensions
                let fps = self.currentFrameRate.rawValue
                let backVideoSettings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: Int(dimensions.width),
                    AVVideoHeightKey: Int(dimensions.height),
                    AVVideoCompressionPropertiesKey: [
                        AVVideoAverageBitRateKey: Int(dimensions.width) * Int(dimensions.height) * 10,
                        AVVideoExpectedSourceFrameRateKey: fps,
                        AVVideoMaxKeyFrameIntervalKey: fps
                    ]
                ]
                print("🎥 CameraManager: Creating back writer with \(dimensions.width)x\(dimensions.height) @ \(fps)fps")
                let backVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: backVideoSettings)
                backVideoInput.expectsMediaDataInRealTime = true
                
                // Set transform for back camera based on device orientation
                backVideoInput.transform = self.getVideoTransform(isFrontCamera: false, orientation: deviceOrientation)
                
                if backWriter.canAdd(backVideoInput) {
                    backWriter.add(backVideoInput)
                    self.backVideoWriter = backWriter
                    self.backVideoWriterInput = backVideoInput
                    print("✅ CameraManager: Back video writer created with transform")
                }
                
                // Create front camera writer with same settings
                let frontWriter = try AVAssetWriter(url: frontURL, fileType: .mov)
                let frontVideoSettings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: Int(dimensions.width),
                    AVVideoHeightKey: Int(dimensions.height),
                    AVVideoCompressionPropertiesKey: [
                        AVVideoAverageBitRateKey: Int(dimensions.width) * Int(dimensions.height) * 10,
                        AVVideoExpectedSourceFrameRateKey: fps,
                        AVVideoMaxKeyFrameIntervalKey: fps
                    ]
                ]
                let frontVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: frontVideoSettings)
                frontVideoInput.expectsMediaDataInRealTime = true
                
                // Set transform for front camera based on device orientation
                frontVideoInput.transform = self.getVideoTransform(isFrontCamera: true, orientation: deviceOrientation)
                
                if frontWriter.canAdd(frontVideoInput) {
                    frontWriter.add(frontVideoInput)
                    self.frontVideoWriter = frontWriter
                    self.frontVideoWriterInput = frontVideoInput
                    print("✅ CameraManager: Front video writer created with transform")
                }
                
                // Create audio writer
                let audioWriter = try AVAssetWriter(url: audioURL, fileType: .m4a)
                let audioSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 44100,
                    AVNumberOfChannelsKey: 1
                ]
                let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
                audioInput.expectsMediaDataInRealTime = true
                
                if audioWriter.canAdd(audioInput) {
                    audioWriter.add(audioInput)
                    self.audioWriter = audioWriter
                    self.audioWriterInput = audioInput
                    print("✅ CameraManager: Audio writer created")
                }
                
                // Start writing
                backWriter.startWriting()
                frontWriter.startWriting()
                audioWriter.startWriting()
                
                print("✅ CameraManager: Writers started - status:")
                print("   Back: \(backWriter.status.rawValue)")
                print("   Front: \(frontWriter.status.rawValue)")
                print("   Audio: \(audioWriter.status.rawValue)")
                
                // Reset session start flags
                self.recordingStartTime = nil
                self.backWriterSessionStarted = false
                self.frontWriterSessionStarted = false
                self.audioWriterSessionStarted = false
                
                print("✅ CameraManager: Recording setup complete!")
                print("✅ CameraManager: Preview should continue running!")
                
                DispatchQueue.main.async {
                    completion(backURL, frontURL, nil)
                }
                
            } catch {
                print("❌ CameraManager: Failed to create asset writers: \(error)")
                DispatchQueue.main.async {
                    self.isRecording = false
                    self.recordingTimer?.invalidate()
                    self.recordingTimer = nil
                    completion(nil, nil, error)
                }
            }
        }
    }
    
    func stopVideoRecording(completion: @escaping (URL?, URL?, URL?) -> Void) {
        print("🎥 CameraManager: stopVideoRecording called")
        print("🎥 CameraManager: Current isRecording = \(isRecording)")
        
        guard isRecording else {
            print("⚠️ CameraManager: Not recording, nothing to stop")
            completion(nil, nil, nil)
            return
        }
        
        sessionQueue.async { [weak self] in
            guard let self = self else { 
                completion(nil, nil, nil)
                return 
            }
            
            print("🎥 CameraManager: Stopping recording on sessionQueue...")
            
            // Stop recording flag immediately for instant UI feedback
            DispatchQueue.main.async {
                self.isRecording = false
                self.recordingTimer?.invalidate()
                self.recordingTimer = nil
                print("✅ CameraManager: isRecording set to false, timer stopped")
            }
            
            // Wait briefly for final frames without blocking main thread
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.1) { [weak self] in
                guard let self = self else { return }
                
                // Finish writing
                print("🎥 CameraManager: Marking inputs as finished...")
                self.backVideoWriterInput?.markAsFinished()
                self.frontVideoWriterInput?.markAsFinished()
                self.audioWriterInput?.markAsFinished()
                
                let group = DispatchGroup()
                
                var finalBackURL: URL?
                var finalFrontURL: URL?
                var finalAudioURL: URL?
                
                // Finish back writer
                if let backWriter = self.backVideoWriter {
                    group.enter()
                    print("🎥 CameraManager: Finishing back writer (status: \(backWriter.status.rawValue))...")
                    backWriter.finishWriting {
                    if backWriter.status == .completed {
                        print("✅ CameraManager: Back video writing completed")
                        print("   URL: \(self.backOutputURL?.path ?? "nil")")
                        if let url = self.backOutputURL {
                            let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int ?? 0
                            print("   File size: \(fileSize) bytes")
                        }
                        finalBackURL = self.backOutputURL
                    } else {
                        print("❌ CameraManager: Back video writing failed")
                        print("   Status: \(backWriter.status.rawValue)")
                        print("   Error: \(String(describing: backWriter.error))")
                        }
                        group.leave()
                    }
                } else {
                    print("⚠️ CameraManager: No back writer found")
                }
                
                // Finish front writer
                if let frontWriter = self.frontVideoWriter {
                    group.enter()
                    print("🎥 CameraManager: Finishing front writer (status: \(frontWriter.status.rawValue))...")
                    frontWriter.finishWriting {
                    if frontWriter.status == .completed {
                        print("✅ CameraManager: Front video writing completed")
                        print("   URL: \(self.frontOutputURL?.path ?? "nil")")
                        if let url = self.frontOutputURL {
                            let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int ?? 0
                            print("   File size: \(fileSize) bytes")
                        }
                        finalFrontURL = self.frontOutputURL
                    } else {
                        print("❌ CameraManager: Front video writing failed")
                        print("   Status: \(frontWriter.status.rawValue)")
                        print("   Error: \(String(describing: frontWriter.error))")
                        }
                        group.leave()
                    }
                } else {
                    print("⚠️ CameraManager: No front writer found")
                }
                
                // Finish audio writer
                if let audioWriter = self.audioWriter {
                    group.enter()
                    audioWriter.finishWriting {
                    if audioWriter.status == .completed {
                        print("✅ CameraManager: Audio writing completed")
                        if let url = self.audioOutputURL {
                            let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int ?? 0
                            print("   Audio file size: \(fileSize) bytes")
                        }
                        finalAudioURL = self.audioOutputURL
                    } else {
                        print("❌ CameraManager: Audio writing failed: \(String(describing: audioWriter.error))")
                        }
                        group.leave()
                    }
                }
                
                group.notify(queue: .main) {
                    print("🎥 CameraManager: All recordings finished")
                    print("🎥 CameraManager: Back URL: \(finalBackURL?.path ?? "nil")")
                    print("🎥 CameraManager: Front URL: \(finalFrontURL?.path ?? "nil")")
                    print("🎥 CameraManager: Audio URL: \(finalAudioURL?.path ?? "nil")")
                    
                    // Return the video and audio URLs via completion
                    completion(finalBackURL, finalFrontURL, finalAudioURL)
                }
            }
            
            // Clean up
            self.backVideoWriter = nil
            self.frontVideoWriter = nil
            self.audioWriter = nil
            self.backVideoWriterInput = nil
            self.frontVideoWriterInput = nil
            self.audioWriterInput = nil
            self.recordingStartTime = nil
        }
    }
    
    // MARK: - Camera Controls
    func switchCamera() {
        isDualCameraMode.toggle()
    }
    
    func setFlashMode(_ mode: AVCaptureDevice.FlashMode) {
        isFlashOn = mode == .on
        
        sessionQueue.async { [weak self] in
            guard let self = self,
                  let device = self.backCameraInput?.device else {
                print("⚠️ CameraManager: Cannot set flash - no back camera device")
                return
            }
            
            do {
                try device.lockForConfiguration()
                
                // Use torch mode for continuous light (better for frame capture)
                if device.hasTorch {
                    if mode == .on {
                        if device.isTorchModeSupported(.on) {
                            try device.setTorchModeOn(level: 1.0)
                            print("✅ CameraManager: Torch ON")
                        }
                    } else {
                        if device.isTorchModeSupported(.off) {
                            device.torchMode = .off
                            print("✅ CameraManager: Torch OFF")
                        }
                    }
                } else {
                    print("⚠️ CameraManager: Device does not have torch")
                }
                
                device.unlockForConfiguration()
            } catch {
                print("❌ CameraManager: Failed to set flash mode: \(error)")
            }
        }
    }
    
    /// Trigger flash for single photo capture (auto mode)
    func triggerFlashForCapture() {
        sessionQueue.async { [weak self] in
            guard let self = self,
                  let device = self.backCameraInput?.device,
                  device.hasTorch else {
                print("⚠️ CameraManager: Cannot trigger flash - no torch")
                return
            }
            
            do {
                try device.lockForConfiguration()
                
                // Turn on torch briefly for capture
                if device.isTorchModeSupported(.on) {
                    try device.setTorchModeOn(level: 1.0)
                    print("⚡️ CameraManager: Flash triggered for capture")
                    
                    // Turn off after 0.2 seconds
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                        self?.sessionQueue.async { [weak self] in
                            guard let device = self?.backCameraInput?.device else { return }
                            try? device.lockForConfiguration()
                            device.torchMode = .off
                            device.unlockForConfiguration()
                            print("⚡️ CameraManager: Flash turned off")
                        }
                    }
                }
                
                device.unlockForConfiguration()
            } catch {
                print("❌ CameraManager: Failed to trigger flash: \(error)")
            }
        }
    }
    
    func stopSession() {
        sessionQueue.async { [weak self] in
            self?.session?.stopRunning()
        }
    }
    
    // MARK: - Format Settings Application
    private func applyFormatSettings(to device: AVCaptureDevice, resolution: VideoResolution, frameRate: FrameRate) {
        do {
            try device.lockForConfiguration()
            
            let targetDimensions = resolution.dimensions
            let targetFPS = Double(frameRate.rawValue)
            
            // Find format that matches both resolution and frame rate
            var bestFormat: AVCaptureDevice.Format?
            var smallestDiff = Int.max
            
            for format in device.formats {
                guard format.isMultiCamSupported else { continue }
                
                let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                let widthDiff = abs(Int(dimensions.width) - Int(targetDimensions.width))
                let heightDiff = abs(Int(dimensions.height) - Int(targetDimensions.height))
                let totalDiff = widthDiff + heightDiff
                
                // Check if this format supports the target frame rate
                var supportsFrameRate = false
                for range in format.videoSupportedFrameRateRanges {
                    if targetFPS >= range.minFrameRate && targetFPS <= range.maxFrameRate {
                        supportsFrameRate = true
                        break
                    }
                }
                
                if supportsFrameRate && totalDiff < smallestDiff {
                    bestFormat = format
                    smallestDiff = totalDiff
                }
            }
            
            if let format = bestFormat {
                device.activeFormat = format
                device.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: Int32(targetFPS))
                device.activeVideoMaxFrameDuration = CMTimeMake(value: 1, timescale: Int32(targetFPS))
                
                let actualDimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                print("✅ Applied \(actualDimensions.width)x\(actualDimensions.height) @ \(targetFPS)fps to \(device.position == .back ? "back" : "front") camera")
            } else {
                print("⚠️ No format found for \(resolution.displayName) @ \(frameRate.displayName) on \(device.position == .back ? "back" : "front") camera")
            }
            
            device.unlockForConfiguration()
        } catch {
            print("❌ Failed to apply format settings: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Frame Rate Configuration
    private func configureFrameRate(for device: AVCaptureDevice, fps: Int) {
        do {
            try device.lockForConfiguration()
            
            let targetFPS = Double(fps)
            var bestFormat: AVCaptureDevice.Format?
            var bestFrameRateRange: AVFrameRateRange?
            
            for format in device.formats {
                for range in format.videoSupportedFrameRateRanges {
                    if range.minFrameRate <= targetFPS && targetFPS <= range.maxFrameRate {
                        if bestFrameRateRange == nil || 
                           range.maxFrameRate >= (bestFrameRateRange?.maxFrameRate ?? 0) {
                            bestFormat = format
                            bestFrameRateRange = range
                        }
                    }
                }
            }
            
            if let format = bestFormat, let _ = bestFrameRateRange {
                device.activeFormat = format
                device.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: Int32(fps))
                device.activeVideoMaxFrameDuration = CMTimeMake(value: 1, timescale: Int32(fps))
                print("✅ Frame rate set to \(fps) FPS for device")
            } else {
                print("⚠️ Could not find suitable format for \(fps) FPS")
            }
            
            device.unlockForConfiguration()
        } catch {
            print("❌ Failed to configure frame rate: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Camera Selection
    /// Get the best back camera that supports multi-cam with front camera
    private func getBestBackCamera() -> AVCaptureDevice? {
        print("🔍 CameraManager: Searching for best back camera (multi-cam compatible)...")
        
        // First, try to get a virtual device that combines ultra-wide + wide
        // This works with front camera in multi-cam sessions
        if #available(iOS 13.0, *) {
            let discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInDualWideCamera, .builtInTripleCamera, .builtInWideAngleCamera, .builtInUltraWideCamera],
                mediaType: .video,
                position: .back
            )
            
            // Try to find ultra-wide camera first
            if let ultraWideCamera = discoverySession.devices.first(where: { $0.deviceType == .builtInUltraWideCamera }) {
                print("   ✅ Found ultra-wide camera (0.5x native)")
                print("   Device: \(ultraWideCamera.localizedName)")
                print("   Zoom range: \(ultraWideCamera.minAvailableVideoZoomFactor)x - \(ultraWideCamera.maxAvailableVideoZoomFactor)x")
                return ultraWideCamera
            }
            
            // Fallback to wide angle with digital zoom
            if let wideCamera = discoverySession.devices.first(where: { $0.deviceType == .builtInWideAngleCamera }) {
                print("   ✅ Found wide angle camera")
                print("   Device: \(wideCamera.localizedName)")
                print("   Zoom range: \(wideCamera.minAvailableVideoZoomFactor)x - \(wideCamera.maxAvailableVideoZoomFactor)x")
                return wideCamera
            }
        }
        
        print("   ❌ No back camera found")
        return nil
    }
    
    // MARK: - Multi-Cam Format Selection
    private func findMultiCamCompatibleFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
        print("🔍 CameraManager: Finding multi-cam compatible format for \(device.position == .back ? "back" : "front") camera")
        
        var bestFormat: AVCaptureDevice.Format?
        var bestWidth: Int32 = 0
        
        for format in device.formats {
            // Check if format supports multi-cam
            if #available(iOS 13.0, *) {
                if format.isMultiCamSupported {
                    let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                    let width = dimensions.width
                    
                    print("   Format: \(width)x\(dimensions.height), multi-cam: ✅")
                    
                    // Prefer 1080p or 720p for better performance
                    if width <= 1920 && width > bestWidth {
                        bestFormat = format
                        bestWidth = width
                    }
                }
            }
        }
        
        if let format = bestFormat {
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            print("✅ CameraManager: Selected format: \(dimensions.width)x\(dimensions.height)")
        } else {
            print("⚠️ CameraManager: No multi-cam compatible format found, using default")
        }
        
        return bestFormat
    }
    
    // MARK: - Zoom Control
    func setZoom(_ factor: CGFloat) {
        sessionQueue.async { [weak self] in
            guard let self = self,
                  let device = self.backCameraInput?.device else {
                print("⚠️ CameraManager: Cannot set zoom - no back camera device")
                return
            }
            
            do {
                try device.lockForConfiguration()
                
                let clampedZoom = max(device.minAvailableVideoZoomFactor,
                                    min(factor, device.maxAvailableVideoZoomFactor))
                
                device.videoZoomFactor = clampedZoom
                
                device.unlockForConfiguration()
                
                DispatchQueue.main.async {
                    self.zoomFactor = clampedZoom
                }
                
                print("📸 CameraManager: Zoom set to \(clampedZoom)x")
            } catch {
                print("❌ CameraManager: Failed to set zoom: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Focus and Exposure Control
    /// Focus and expose at a point in the preview (tap to focus)
    /// - Parameter point: Normalized point (0.0 to 1.0) in preview coordinates
    func focusAndExpose(at point: CGPoint) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Get the appropriate device based on camera mode
            let device: AVCaptureDevice?
            switch self.cameraMode {
            case .backOnly, .dual:
                device = self.backCameraInput?.device
            case .frontOnly:
                device = self.frontCameraInput?.device
            }
            
            guard let captureDevice = device else {
                print("⚠️ CameraManager: No camera device available for focus")
                return
            }
            
            do {
                try captureDevice.lockForConfiguration()
                
                // Set focus point of interest if supported
                if captureDevice.isFocusPointOfInterestSupported {
                    captureDevice.focusPointOfInterest = point
                    
                    // Use auto focus mode for smooth focusing
                    if captureDevice.isFocusModeSupported(.autoFocus) {
                        captureDevice.focusMode = .autoFocus
                    } else if captureDevice.isFocusModeSupported(.continuousAutoFocus) {
                        captureDevice.focusMode = .continuousAutoFocus
                    }
                    
                    print("📸 CameraManager: Focus point set to (\(point.x), \(point.y))")
                }
                
                // Set exposure point of interest if supported
                if captureDevice.isExposurePointOfInterestSupported {
                    captureDevice.exposurePointOfInterest = point
                    
                    // Use auto exposure mode
                    if captureDevice.isExposureModeSupported(.autoExpose) {
                        captureDevice.exposureMode = .autoExpose
                    } else if captureDevice.isExposureModeSupported(.continuousAutoExposure) {
                        captureDevice.exposureMode = .continuousAutoExposure
                    }
                    
                    print("📸 CameraManager: Exposure point set to (\(point.x), \(point.y))")
                }
                
                captureDevice.unlockForConfiguration()
                
                print("✅ CameraManager: Focus and exposure completed")
            } catch {
                print("❌ CameraManager: Failed to set focus/exposure: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Video Settings (Resolution & Frame Rate)
    /// Update video resolution
    func setResolution(_ resolution: VideoResolution) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            print("🎬 CameraManager: Changing resolution to \(resolution.displayName)")
            
            // Get back camera device
            guard let device = self.backCameraInput?.device else {
                print("⚠️ CameraManager: No back camera device for resolution change")
                return
            }
            
            do {
                try device.lockForConfiguration()
                
                // Find best format matching the desired resolution
                let targetDimensions = resolution.dimensions
                var bestFormat: AVCaptureDevice.Format?
                var smallestDiff = Int.max
                
                for format in device.formats {
                    let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                    let widthDiff = abs(Int(dimensions.width) - Int(targetDimensions.width))
                    let heightDiff = abs(Int(dimensions.height) - Int(targetDimensions.height))
                    let totalDiff = widthDiff + heightDiff
                    
                    // Prefer multi-cam compatible formats
                    if format.isMultiCamSupported && totalDiff < smallestDiff {
                        bestFormat = format
                        smallestDiff = totalDiff
                    }
                }
                
                if let format = bestFormat {
                    device.activeFormat = format
                    let actualDimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                    print("✅ CameraManager: Resolution set to \(actualDimensions.width)x\(actualDimensions.height)")
                    
                    DispatchQueue.main.async {
                        self.currentResolution = resolution
                    }
                } else {
                    print("⚠️ CameraManager: No suitable format found for \(resolution.displayName)")
                }
                
                device.unlockForConfiguration()
            } catch {
                print("❌ CameraManager: Failed to set resolution: \(error.localizedDescription)")
            }
        }
    }
    
    /// Update frame rate
    func setFrameRate(_ frameRate: FrameRate) {
        print("🎬 CameraManager: setFrameRate called with \(frameRate.displayName)")
        
        // Update UI immediately
        DispatchQueue.main.async { [weak self] in
            self?.currentFrameRate = frameRate
            print("✅ CameraManager: currentFrameRate updated to \(frameRate.displayName)")
        }
        
        // Then apply to devices
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            let targetFPS = Double(frameRate.rawValue)
            
            // Set back camera frame rate
            if let backDevice = self.backCameraInput?.device {
                do {
                    try backDevice.lockForConfiguration()
                    
                    let currentFormat = backDevice.activeFormat
                    let ranges = currentFormat.videoSupportedFrameRateRanges
                    
                    var supportedRange: AVFrameRateRange?
                    for range in ranges {
                        if targetFPS >= range.minFrameRate && targetFPS <= range.maxFrameRate {
                            supportedRange = range
                            break
                        }
                    }
                    
                    if let _ = supportedRange {
                        backDevice.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: Int32(targetFPS))
                        backDevice.activeVideoMaxFrameDuration = CMTimeMake(value: 1, timescale: Int32(targetFPS))
                        let actualFPS = 1.0 / CMTimeGetSeconds(backDevice.activeVideoMinFrameDuration)
                        print("✅ CameraManager: Back camera frame rate set to \(targetFPS) FPS (actual: \(actualFPS))")
                    } else {
                        print("⚠️ CameraManager: Back camera: Frame rate \(targetFPS) FPS not supported")
                        print("   Available ranges: \(ranges.map { "\($0.minFrameRate)-\($0.maxFrameRate)" }.joined(separator: ", "))")
                    }
                    
                    backDevice.unlockForConfiguration()
                } catch {
                    print("❌ CameraManager: Failed to set back camera frame rate: \(error.localizedDescription)")
                }
            }
            
            // Set front camera frame rate
            if let frontDevice = self.frontCameraInput?.device {
                do {
                    try frontDevice.lockForConfiguration()
                    
                    let currentFormat = frontDevice.activeFormat
                    let ranges = currentFormat.videoSupportedFrameRateRanges
                    
                    var supportedRange: AVFrameRateRange?
                    for range in ranges {
                        if targetFPS >= range.minFrameRate && targetFPS <= range.maxFrameRate {
                            supportedRange = range
                            break
                        }
                    }
                    
                    if let _ = supportedRange {
                        frontDevice.activeVideoMinFrameDuration = CMTimeMake(value: 1, timescale: Int32(targetFPS))
                        frontDevice.activeVideoMaxFrameDuration = CMTimeMake(value: 1, timescale: Int32(targetFPS))
                        let actualFPS = 1.0 / CMTimeGetSeconds(frontDevice.activeVideoMinFrameDuration)
                        print("✅ CameraManager: Front camera frame rate set to \(targetFPS) FPS (actual: \(actualFPS))")
                    } else {
                        print("⚠️ CameraManager: Front camera: Frame rate \(targetFPS) FPS not supported")
                        print("   Available ranges: \(ranges.map { "\($0.minFrameRate)-\($0.maxFrameRate)" }.joined(separator: ", "))")
                    }
                    
                    frontDevice.unlockForConfiguration()
                } catch {
                    print("❌ CameraManager: Failed to set front camera frame rate: \(error.localizedDescription)")
                }
            }
        }
    }
    
    // MARK: - Photo Library Saving
    func savePhotoToLibrary(_ image: UIImage, isFrontCamera: Bool, completion: @escaping (Bool, Error?) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                print("❌ CameraManager: Photo library permission denied")
                DispatchQueue.main.async {
                    completion(false, NSError(domain: "CameraManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Photo library access denied"]))
                }
                return
            }
            
            // Apply correct orientation before saving
            let correctedImage = self.correctImageOrientation(image, isFrontCamera: isFrontCamera)
            
            PHPhotoLibrary.shared().performChanges({
                PHAssetCreationRequest.creationRequestForAsset(from: correctedImage)
            }) { success, error in
                DispatchQueue.main.async {
                    if success {
                        print("✅ CameraManager: Photo saved successfully")
                        completion(true, nil)
                    } else {
                        print("❌ CameraManager: Failed to save photo: \(error?.localizedDescription ?? "unknown")")
                        completion(false, error)
                    }
                }
            }
        }
    }
    
    // Correct image orientation for saving (not for preview)
    private func correctImageOrientation(_ image: UIImage, isFrontCamera: Bool) -> UIImage {
        let orientation = getImageOrientation(isFrontCamera: isFrontCamera)
        
        // Create a new UIImage with correct orientation metadata
        guard let cgImage = image.cgImage else { return image }
        return UIImage(cgImage: cgImage, scale: image.scale, orientation: orientation)
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate & AVCaptureAudioDataOutputSampleBufferDelegate
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate {
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        // DEBUG: Log every call to verify delegate is working
        var callCount = 0
        callCount += 1
        if callCount == 1 {
            print("🎯 CameraManager: captureOutput DELEGATE CALLED! (first time)")
        }
        
        // Determine which camera by checking the connection's input device
        if output is AVCaptureVideoDataOutput {
            // Check camera position through connection
            if let inputPort = connection.inputPorts.first,
               let deviceInput = inputPort.input as? AVCaptureDeviceInput {
                
                let position = deviceInput.device.position
                
                if position == .back {
                    // Back camera frame
                    frameLock.lock()
                    lastBackFrame = sampleBuffer
                    backFrameCount += 1
                    if backFrameCount % 30 == 0 {
                        print("📹 CameraManager: Received \(backFrameCount) back camera frames")
                    }
                    frameLock.unlock()

                    // Publish a lightweight preview image at a reduced rate to save CPU
                    if backFrameCount % previewFrameInterval == 0 {
                        autoreleasepool {
                            if let previewImage = self.imageFromSampleBuffer(sampleBuffer, isFrontCamera: false) {
                                DispatchQueue.main.async { [weak self] in
                                    self?.capturedBackImage = previewImage
                                }
                            }
                        }
                    }
                    
                    // Write to video file if recording
                    if isRecording, let videoInput = backVideoWriterInput, videoInput.isReadyForMoreMediaData {
                        // Start writer session only when we have stable frames from both cameras
                        if !backWriterSessionStarted, let writer = backVideoWriter, writer.status == .writing,
                           frontFrameCount >= 3 {  // Wait for front camera to have at least 3 frames (skip black frames)
                            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                            writer.startSession(atSourceTime: timestamp)
                            recordingStartTime = timestamp
                            backWriterSessionStarted = true
                            print("✅ CameraManager: Back video writer session started at \(timestamp.seconds) (both cameras stable)")
                        }
                        // CRITICAL: Only append after session has started
                        if backWriterSessionStarted {
                            let success = videoInput.append(sampleBuffer)
                            if !success && backFrameCount % 30 == 0 {
                                print("⚠️ CameraManager: Failed to append back video frame")
                            }
                            if backFrameCount % 60 == 0 {
                                print("📹 CameraManager: Back video frames appended (count: \(backFrameCount))")
                            }
                        }
                    } else if isRecording && backFrameCount % 30 == 0 {
                        if frontFrameCount < 3 {
                            print("⏳ CameraManager: Waiting for front camera frames (\(frontFrameCount)/3)...")
                        }
                    }
                } else if position == .front {
                    // Front camera frame
                    frameLock.lock()
                    lastFrontFrame = sampleBuffer
                    frontFrameCount += 1
                    if frontFrameCount == 1 {
                        print("🎉 CameraManager: FIRST front camera frame received!")
                    }
                    if frontFrameCount % 30 == 0 {
                        print("📹 CameraManager: Received \(frontFrameCount) front camera frames")
                    }
                    frameLock.unlock()

                    // Publish a lightweight preview image at a reduced rate to save CPU
                    if frontFrameCount % previewFrameInterval == 0 {
                        autoreleasepool {
                            if let previewImage = self.imageFromSampleBuffer(sampleBuffer, isFrontCamera: true) {
                                DispatchQueue.main.async { [weak self] in
                                    self?.capturedFrontImage = previewImage
                                }
                            }
                        }
                    }
                    
                    // Write to video file if recording
                    if isRecording, let videoInput = frontVideoWriterInput, videoInput.isReadyForMoreMediaData {
                        // Use same start time as back camera
                        if !frontWriterSessionStarted, let writer = frontVideoWriter, writer.status == .writing, 
                           let startTime = recordingStartTime {
                            writer.startSession(atSourceTime: startTime)
                            frontWriterSessionStarted = true
                            print("✅ CameraManager: Front video writer session started at \(startTime.seconds)")
                        }
                        // CRITICAL: Only append after session has started
                        if frontWriterSessionStarted {
                            let success = videoInput.append(sampleBuffer)
                            if !success && frontFrameCount % 30 == 0 {
                                print("⚠️ CameraManager: Failed to append front video frame")
                            }
                        }
                    }
                }
            } else {
                print("⚠️ CameraManager: Could not determine camera position from connection")
            }
        } else if output is AVCaptureAudioDataOutput {
            // Audio data
            if isRecording, let audioInput = audioWriterInput, audioInput.isReadyForMoreMediaData {
                if !audioWriterSessionStarted, let writer = audioWriter, writer.status == .writing, let startTime = recordingStartTime {
                    writer.startSession(atSourceTime: startTime)
                    audioWriterSessionStarted = true
                    print("✅ CameraManager: Audio writer session started at \(startTime.seconds)")
                }
                if audioWriterSessionStarted {
                    audioInput.append(sampleBuffer)
                }
            }
        }
    }
}
