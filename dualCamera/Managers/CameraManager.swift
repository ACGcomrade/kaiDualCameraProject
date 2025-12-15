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
    private let backVideoDataQueue = DispatchQueue(label: "backVideoDataQueue", qos: .default)  // Balanced performance/efficiency
    private let frontVideoDataQueue = DispatchQueue(label: "frontVideoDataQueue", qos: .default)  // Balanced performance/efficiency
    private let audioDataQueue = DispatchQueue(label: "audioDataQueue", qos: .utility)
    private let rotationQueue = DispatchQueue(label: "videoRotationQueue", qos: .userInitiated, attributes: .concurrent)  // High priority for rotation
    private let settings = CameraSettings.shared
    // Use shared CIContext from ImageUtils for better performance
    private var ciContext: CIContext { ImageUtils.sharedCIContext }
    // How many frames between published preview image updates (reduce CPU by updating less frequently)
    private let previewFrameInterval = 12  // Optimized for better battery life (updates ~2.5 times per second at 30fps)
    
    // Preview switcher reference (for PIP video recording)
    weak var previewSwitcher: PreviewSwitcher?
    
    // Preview capture manager for screen recording
    let previewCaptureManager = PreviewCaptureManager.shared
    
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
    private var pipVideoWriter: AVAssetWriter?  // PIP mode: single writer for composed output
    private var backVideoWriterInput: AVAssetWriterInput?
    private var frontVideoWriterInput: AVAssetWriterInput?
    private var audioWriterInput: AVAssetWriterInput?
    private var pipVideoWriterInput: AVAssetWriterInput?  // PIP mode input
    private var recordingStartTime: CMTime?
    private var recordingOrientation: UIDeviceOrientation = .portrait  // Store orientation for pixel rotation
    private var recordingTimer: Timer?
    private var backOutputURL: URL?
    private var frontOutputURL: URL?
    private var audioOutputURL: URL?
    private var pipOutputURL: URL?  // PIP mode output
    private var isPIPRecordingMode = false  // Flag to indicate PIP recording
    
    // Session start flags
    private var backWriterSessionStarted = false
    private var frontWriterSessionStarted = false
    private var audioWriterSessionStarted = false
    private var pipWriterSessionStarted = false  // PIP mode session flag
    
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
            
            if let session = session, !session.isRunning {
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
        let shouldSetupBack = (cameraMode == .backOnly || cameraMode == .dual || cameraMode == .picInPic)
        let shouldSetupFront = (cameraMode == .frontOnly || cameraMode == .dual || cameraMode == .picInPic)
        
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
                // Optimize for lower memory footprint
                if #available(iOS 17.0, *) {
                    backVideoOutput.automaticallyConfiguresOutputBufferDimensions = true
                }
                
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
                // Optimize for lower memory footprint
                if #available(iOS 17.0, *) {
                    frontVideoOutput.automaticallyConfiguresOutputBufferDimensions = true
                }
                
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
        print("📸 CameraManager: Current camera mode: \(cameraMode.displayName)")
        
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
                let currentMode = self.cameraMode
                self.frameLock.unlock()
                
                print("📸 CameraManager: Frame status - Back: \(backFrame != nil) (count: \(backCount)), Front: \(frontFrame != nil) (count: \(frontCount))")
                
                // Only capture frames based on current camera mode
                let backImage: UIImage?
                let frontImage: UIImage?
                
                switch currentMode {
                case .backOnly:
                    print("📸 CameraManager: Back only mode - capturing only back camera")
                    backImage = self.imageFromSampleBuffer(backFrame, isFrontCamera: false)
                    frontImage = nil
                    
                case .frontOnly:
                    print("📸 CameraManager: Front only mode - capturing only front camera")
                    backImage = nil
                    frontImage = self.imageFromSampleBuffer(frontFrame, isFrontCamera: true)
                    
                case .dual:
                    print("📸 CameraManager: Dual mode - capturing both cameras")
                    backImage = self.imageFromSampleBuffer(backFrame, isFrontCamera: false)
                    frontImage = self.imageFromSampleBuffer(frontFrame, isFrontCamera: true)
                    
                case .picInPic:
                    // This method shouldn't be called for PIP mode, but handle it
                    print("⚠️ CameraManager: PIP mode in captureDualPhotos (shouldn't happen)")
                    backImage = self.imageFromSampleBuffer(backFrame, isFrontCamera: false)
                    frontImage = self.imageFromSampleBuffer(frontFrame, isFrontCamera: true)
                }
                
                print("📸 CameraManager: Result - Back image: \(backImage != nil), Front image: \(frontImage != nil)")
                
                DispatchQueue.main.async {
                    completion(backImage, frontImage)
                }
            }
        }
    }
    
    /// Capture PIP photo - compose both cameras into single image
    func capturePIPPhoto(withFlash: Bool = false, completion: @escaping (UIImage?) -> Void) {
        print("📸 CameraManager: capturePIPPhoto - capturing preview screen (NEW METHOD)")
        
        // Trigger flash if requested
        if withFlash {
            triggerFlashForCapture()
            // Wait a moment for flash to activate
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
                self?.capturePreviewScreenshot(completion: completion)
            }
        } else {
            capturePreviewScreenshot(completion: completion)
        }
    }
    
    /// Capture current preview screen as photo (what user sees on screen)
    private func capturePreviewScreenshot(completion: @escaping (UIImage?) -> Void) {
        // Ensure we're on main thread since we're capturing UI
        DispatchQueue.main.async { [weak self] in
            guard let self = self else {
                completion(nil)
                return
            }
            
            // Capture preview screen
            guard let previewImage = self.previewCaptureManager.capturePreviewFrame() else {
                print("❌ CameraManager: Failed to capture preview screen")
                completion(nil)
                return
            }
            
            // Apply pre-rotation correction for PIP photos
            // Screen capture is already correctly oriented, but correctImageOrientation()
            // will rotate it by 90° CW. We need to pre-rotate 90° CCW to compensate.
            let correctedImage = self.preRotatePIPPhotoForSaving(previewImage)
            
            print("✅ CameraManager: PIP photo captured from preview screen")
            print("   Original size: \(previewImage.size)")
            print("   Corrected size: \(correctedImage.size)")
            print("   Applied pre-rotation to compensate for savePhotoToLibrary rotation")
            
            completion(correctedImage)
        }
    }
    
    /// Pre-rotate PIP photo 90° clockwise to compensate for correctImageOrientation()
    /// Screen captures are already in correct orientation, but savePhotoToLibrary will rotate
    /// them, so we pre-rotate 90° CW to end up with correct final orientation
    private func preRotatePIPPhotoForSaving(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        
        let deviceOrientation = UIDevice.current.orientation
        
        // Only apply compensation in portrait mode (where correctImageOrientation rotates)
        guard deviceOrientation == .portrait || !deviceOrientation.isValidInterfaceOrientation else {
            print("📸 CameraManager: No pre-rotation needed (non-portrait orientation)")
            return image
        }
        
        print("📸 CameraManager: Pre-rotating PIP photo 90° CW to compensate for save rotation")
        
        // Rotate 90° clockwise
        let width = cgImage.height
        let height = cgImage.width
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            print("❌ CameraManager: Failed to create graphics context for rotation")
            return image
        }
        
        // Rotate 90° clockwise: translate and rotate
        context.translateBy(x: CGFloat(width), y: 0)
        context.rotate(by: .pi / 2)
        
        // Draw the original image
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
        
        // Create rotated image
        guard let rotatedCGImage = context.makeImage() else {
            print("❌ CameraManager: Failed to create rotated image")
            return image
        }
        
        return UIImage(cgImage: rotatedCGImage, scale: image.scale, orientation: .up)
    }
    
    // MARK: - Orientation Helpers
    // Rotate sample buffer's pixel data for proper orientation
    private func rotateSampleBufferIfNeeded(_ sampleBuffer: CMSampleBuffer, orientation: UIDeviceOrientation, isFrontCamera: Bool) -> CMSampleBuffer {
        // Check if rotation is needed
        let needsRotation = orientation == .portrait || orientation == .portraitUpsideDown
        let needsFrontFlip = isFrontCamera && (orientation == .landscapeLeft || orientation == .landscapeRight)
        
        guard needsRotation || needsFrontFlip else {
            return sampleBuffer
        }
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            print("⚠️ Failed to get image buffer from sample")
            return sampleBuffer
        }
        
        // Create CIImage from pixel buffer
        var ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let originalExtent = ciImage.extent
        
        // Calculate center for transformations
        let centerX = originalExtent.midX
        let centerY = originalExtent.midY
        
        var transform = CGAffineTransform.identity
        
        if needsRotation {
            // Portrait orientations: rotate 90 degrees
            let rotationAngle: CGFloat = (orientation == .portrait) ? -.pi / 2 : .pi / 2
            
            // Rotate around center
            transform = CGAffineTransform(translationX: centerX, y: centerY)
            transform = transform.rotated(by: rotationAngle)
            transform = transform.translatedBy(x: -centerX, y: -centerY)
            
            ciImage = ciImage.transformed(by: transform)
            
            // Apply mirror for front camera AFTER rotation
            if isFrontCamera {
                let mirrorTransform = CGAffineTransform(scaleX: -1, y: 1)
                    .translatedBy(x: -ciImage.extent.width, y: 0)
                ciImage = ciImage.transformed(by: mirrorTransform)
            }
        } else if needsFrontFlip {
            // Landscape: front camera needs 180 degree flip (upside down correction)
            transform = CGAffineTransform(translationX: centerX, y: centerY)
            transform = transform.rotated(by: .pi)  // 180 degrees
            transform = transform.translatedBy(x: -centerX, y: -centerY)
            ciImage = ciImage.transformed(by: transform)
        }
        
        // Normalize extent to start at origin (0,0)
        let normalizedExtent = CGRect(x: 0, y: 0, width: ciImage.extent.width, height: ciImage.extent.height)
        ciImage = ciImage.transformed(by: CGAffineTransform(translationX: -ciImage.extent.minX, y: -ciImage.extent.minY))
        
        // Determine new dimensions based on orientation
        let originalWidth = CVPixelBufferGetWidth(imageBuffer)
        let originalHeight = CVPixelBufferGetHeight(imageBuffer)
        let newWidth = needsRotation ? originalHeight : originalWidth  // Swap for portrait only
        let newHeight = needsRotation ? originalWidth : originalHeight
        
        var rotatedPixelBuffer: CVPixelBuffer?
        let pixelBufferAttributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ]
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            newWidth,
            newHeight,
            kCVPixelFormatType_32BGRA,
            pixelBufferAttributes as CFDictionary,
            &rotatedPixelBuffer
        )
        
        guard status == kCVReturnSuccess, let outputBuffer = rotatedPixelBuffer else {
            print("⚠️ Failed to create rotated pixel buffer: \(status)")
            return sampleBuffer
        }
        
        // Render rotated image to new buffer at origin (uses GPU acceleration)
        autoreleasepool {
            ciContext.render(ciImage, to: outputBuffer, bounds: normalizedExtent, colorSpace: CGColorSpaceCreateDeviceRGB())
        }
        
        // Create new sample buffer using shared utility method
        guard let rotatedSample = ImageUtils.createSampleBuffer(from: outputBuffer, copying: sampleBuffer) else {
            print("⚠️ Failed to create rotated sample buffer")
            return sampleBuffer
        }
        
        return rotatedSample
    }
    
    private func getVideoTransform(isFrontCamera: Bool, orientation: UIDeviceOrientation) -> CGAffineTransform {
        var transform = CGAffineTransform.identity
        
        // AVAssetWriter transform说明：
        // - 相机原始输出：LandscapeRight（横向，home键在右）
        // Use shared utility method for consistent video transform
        transform = ImageUtils.videoTransform(for: orientation, isFrontCamera: isFrontCamera)
        
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
                
                // For portrait: swap dimensions to create vertical video container (1080x1920)
                let isPortrait = deviceOrientation == .portrait || deviceOrientation == .portraitUpsideDown
                let videoWidth = isPortrait ? Int(dimensions.height) : Int(dimensions.width)
                let videoHeight = isPortrait ? Int(dimensions.width) : Int(dimensions.height)
                
                let backVideoSettings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: videoWidth,
                    AVVideoHeightKey: videoHeight,
                    AVVideoCompressionPropertiesKey: [
                        AVVideoAverageBitRateKey: videoWidth * videoHeight * 6,  // Reduced from 10 for better efficiency
                        AVVideoExpectedSourceFrameRateKey: fps,
                        AVVideoMaxKeyFrameIntervalKey: fps * 2,  // Allow more GOP flexibility
                        AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel  // Baseline profile for efficiency
                    ]
                ]
                print("🎥 CameraManager: Creating back writer with \(videoWidth)x\(videoHeight) @ \(fps)fps (portrait: \(isPortrait))")
                let backVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: backVideoSettings)
                backVideoInput.expectsMediaDataInRealTime = true
                
                // No transform needed - we'll rotate the pixel data itself
                backVideoInput.transform = CGAffineTransform.identity
                
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
                    AVVideoWidthKey: videoWidth,
                    AVVideoHeightKey: videoHeight,
                    AVVideoCompressionPropertiesKey: [
                        AVVideoAverageBitRateKey: videoWidth * videoHeight * 6,  // Reduced from 10 for better efficiency
                        AVVideoExpectedSourceFrameRateKey: fps,
                        AVVideoMaxKeyFrameIntervalKey: fps * 2,  // Allow more GOP flexibility
                        AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel  // Baseline profile for efficiency
                    ]
                ]
                let frontVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: frontVideoSettings)
                frontVideoInput.expectsMediaDataInRealTime = true
                
                // No transform needed - we'll rotate the pixel data itself
                frontVideoInput.transform = CGAffineTransform.identity
                
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
                
                // Store current orientation for pixel rotation during recording
                self.recordingOrientation = deviceOrientation
                
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
    
    // MARK: - PIP Video Recording
    func startPIPVideoRecording(completion: @escaping (URL?, Error?) -> Void) {
        print("🎥 CameraManager: startPIPVideoRecording called (FRAME COMPOSITION MODE)")
        
        guard !isRecording else {
            print("⚠️ CameraManager: Already recording")
            return
        }
        
        // Clean up any previous writers first
        cleanupWriters()
        
        // Set recording flags on main thread (Published properties should be set on main)
        DispatchQueue.main.async { [weak self] in
            self?.isRecording = true
            self?.isPIPRecordingMode = true
            self?.recordingDuration = 0
            self?.recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
                self?.recordingDuration += 0.2
            }
            print("✅ CameraManager: PIP recording started (frame composition mode)")
        }
        
        // Do all heavy work asynchronously
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Create output URLs
            let pipURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("pip_\(UUID().uuidString)")
                .appendingPathExtension("mov")
            
            let audioURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("audio_\(UUID().uuidString)")
                .appendingPathExtension("m4a")
            
            self.pipOutputURL = pipURL
            self.audioOutputURL = audioURL
            print("🎥 CameraManager: PIP URL: \(pipURL)")
            print("🎥 CameraManager: Audio URL: \(audioURL)")
            
            do {
                // Get recording settings
                let dimensions = self.currentResolution.dimensions
                let fps = self.currentFrameRate.rawValue
                
                // Get device orientation
                var deviceOrientation = UIDevice.current.orientation
                if !deviceOrientation.isValidInterfaceOrientation {
                    deviceOrientation = .portrait
                }
                print("🎥 CameraManager: PIP recording orientation: \(deviceOrientation.rawValue)")
                
                // Calculate video dimensions based on orientation
                let isPortrait = deviceOrientation == .portrait || deviceOrientation == .portraitUpsideDown
                let videoWidth = isPortrait ? Int(dimensions.height) : Int(dimensions.width)
                let videoHeight = isPortrait ? Int(dimensions.width) : Int(dimensions.height)
                
                print("🎥 CameraManager: Video resolution: \(videoWidth)x\(videoHeight) at \(fps)fps")
                
                // Create PIP video writer (for composed frames)
                let pipWriter = try AVAssetWriter(url: pipURL, fileType: .mov)
                
                let pipVideoSettings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: videoWidth,
                    AVVideoHeightKey: videoHeight,
                    AVVideoCompressionPropertiesKey: [
                        AVVideoAverageBitRateKey: videoWidth * videoHeight * 10,
                        AVVideoExpectedSourceFrameRateKey: fps,
                        AVVideoMaxKeyFrameIntervalKey: fps * 2,
                        AVVideoProfileLevelKey: AVVideoProfileLevelH264BaselineAutoLevel
                    ]
                ]
                
                let pipVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: pipVideoSettings)
                pipVideoInput.expectsMediaDataInRealTime = true
                pipVideoInput.transform = CGAffineTransform.identity
                
                if pipWriter.canAdd(pipVideoInput) {
                    pipWriter.add(pipVideoInput)
                    self.pipVideoWriter = pipWriter
                    self.pipVideoWriterInput = pipVideoInput
                    print("✅ CameraManager: PIP video writer created")
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
                pipWriter.startWriting()
                audioWriter.startWriting()
                
                // Reset flags
                self.recordingStartTime = nil
                self.pipWriterSessionStarted = false
                self.audioWriterSessionStarted = false
                self.recordingOrientation = deviceOrientation
                
                print("✅ CameraManager: PIP recording setup complete! (frame composition mode)")
                
                DispatchQueue.main.async {
                    completion(pipURL, nil)
                }
                
            } catch {
                print("❌ CameraManager: Failed to setup PIP recording: \(error)")
                DispatchQueue.main.async {
                    self.isRecording = false
                    self.isPIPRecordingMode = false
                    self.recordingTimer?.invalidate()
                    self.recordingTimer = nil
                    completion(nil, error)
                }
            }
        }
    }
    
    func stopVideoRecording(completion: @escaping (URL?, URL?, URL?) -> Void) {
        print("🎥 CameraManager: stopVideoRecording called")
        print("🎥 CameraManager: Current isRecording = \(isRecording)")
        print("🎥 CameraManager: isPIPRecordingMode = \(isPIPRecordingMode)")
        
        guard isRecording else {
            print("⚠️ CameraManager: Not recording, nothing to stop")
            completion(nil, nil, nil)
            return
        }
        
        // Check if this is PIP recording mode
        if isPIPRecordingMode {
            stopPIPVideoRecording(completion: completion)
            return
        }
        
        sessionQueue.async { [weak self] in
            guard let self = self else { 
                completion(nil, nil, nil)
                return 
            }
            
            print("🎥 CameraManager: Stopping recording on sessionQueue...")
            
            // Stop recording flag immediately for instant UI feedback
            // Use synchronous assignment on sessionQueue to ensure thread safety
            self.isRecording = false
            DispatchQueue.main.async {
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
                    
                    // Clean up writers after completion
                    self.backVideoWriter = nil
                    self.frontVideoWriter = nil
                    self.audioWriter = nil
                    self.backVideoWriterInput = nil
                    self.frontVideoWriterInput = nil
                    self.audioWriterInput = nil
                    self.recordingStartTime = nil
                    
                    // Return the video and audio URLs via completion
                    completion(finalBackURL, finalFrontURL, finalAudioURL)
                }
            }
        }
    }
    
    private func stopPIPVideoRecording(completion: @escaping (URL?, URL?, URL?) -> Void) {
        print("🎥 CameraManager: stopPIPVideoRecording called (frame composition mode)")
        print("🎥 CameraManager: Current isRecording = \(isRecording)")
        
        // Stop timer on main thread
        // Stop recording flags immediately on main thread
        DispatchQueue.main.async { [weak self] in
            self?.isRecording = false
            self?.isPIPRecordingMode = false
            self?.recordingTimer?.invalidate()
            self?.recordingTimer = nil
            print("✅ CameraManager: Recording flags cleared and timer stopped")
        }
        
        print("🎥 CameraManager: Stopping PIP recording...")
        
        sessionQueue.async { [weak self] in
            guard let self = self else {
                completion(nil, nil, nil)
                return
            }
            
            print("🎥 CameraManager: Marking PIP inputs as finished...")
            
            // Mark inputs as finished with safety check
            if let pipInput = self.pipVideoWriterInput, let pipWriter = self.pipVideoWriter, pipWriter.status == .writing {
                pipInput.markAsFinished()
            }
            if let audioInput = self.audioWriterInput, let audioWriter = self.audioWriter, audioWriter.status == .writing {
                audioInput.markAsFinished()
            }
            
            var pipVideoURL: URL?
            var audioURL: URL?
            
            let group = DispatchGroup()
            
            // Finish PIP video writing
            if let pipWriter = self.pipVideoWriter {
                group.enter()
                pipWriter.finishWriting {
                    if pipWriter.status == .completed {
                        print("✅ CameraManager: PIP video writing completed")
                        pipVideoURL = self.pipOutputURL
                    } else if let error = pipWriter.error {
                        print("❌ CameraManager: PIP video writing failed: \(error)")
                    } else {
                        print("❌ CameraManager: PIP video writing failed with unknown error")
                    }
                    group.leave()
                }
            } else {
                print("⚠️ CameraManager: No PIP video writer")
            }
            
            // Finish audio writing
            if let audioWriter = self.audioWriter {
                group.enter()
                audioWriter.finishWriting {
                    if audioWriter.status == .completed {
                        print("✅ CameraManager: Audio writing completed")
                        audioURL = self.audioOutputURL
                    } else {
                        print("❌ CameraManager: Audio writing failed")
                    }
                    group.leave()
                }
            } else {
                print("⚠️ CameraManager: No audio writer")
            }
            
            // Wait for all writers to finish
            group.wait()
            
            // Clean up
            self.pipVideoWriter = nil
            self.pipVideoWriterInput = nil
            self.audioWriter = nil
            self.audioWriterInput = nil
            
            DispatchQueue.main.async {
                print("🎥 CameraManager: PIP recording save complete")
                print("   PIP Video URL: \(pipVideoURL?.path ?? "nil")")
                print("   Audio URL: \(audioURL?.path ?? "nil")")
                completion(pipVideoURL, nil, audioURL)
            }
        }
    }
    
    // MARK: - Camera Controls
    func switchCamera() {
        isDualCameraMode.toggle()
    }
    
    /// Toggle preview camera (swap main and PIP displays)
    func togglePreviewCamera() {
        print("🔄 CameraManager: Toggle preview camera requested")
        // This will be handled by DualCameraPreview's PreviewSwitcher
        // Just need to trigger a notification to the preview layer
        NotificationCenter.default.post(name: NSNotification.Name("TogglePreviewCamera"), object: nil)
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
        print("🛑 CameraManager: stopSession called")
        
        // Force stop any ongoing recording
        if isRecording {
            print("⚠️ CameraManager: Force stopping recording in stopSession")
            isRecording = false
            isPIPRecordingMode = false
            DispatchQueue.main.async { [weak self] in
                self?.recordingTimer?.invalidate()
                self?.recordingTimer = nil
            }
        }
        
        // Clean up all writers
        cleanupWriters()
        
        sessionQueue.async { [weak self] in
            self?.session?.stopRunning()
            print("✅ CameraManager: Session stopped")
        }
    }
    
    // MARK: - Writer Cleanup
    private func cleanupWriters() {
        print("🧹 CameraManager: Cleaning up writers...")
        
        // Cancel PIP video writer
        if let pipWriter = self.pipVideoWriter {
            if pipWriter.status == .writing {
                self.pipVideoWriterInput?.markAsFinished()
                pipWriter.cancelWriting()
                print("🧹 CameraManager: Cancelled pipVideoWriter")
            }
        }
        self.pipVideoWriter = nil
        self.pipVideoWriterInput = nil
        
        // Cancel audio writer
        if let audioWriter = self.audioWriter {
            if audioWriter.status == .writing {
                self.audioWriterInput?.markAsFinished()
                audioWriter.cancelWriting()
                print("🧹 CameraManager: Cancelled audioWriter")
            }
        }
        self.audioWriter = nil
        self.audioWriterInput = nil
        
        // Cancel back video writer  
        if let backWriter = self.backVideoWriter {
            if backWriter.status == .writing {
                self.backVideoWriterInput?.markAsFinished()
                backWriter.cancelWriting()
                print("🧹 CameraManager: Cancelled backVideoWriter")
            }
        }
        self.backVideoWriter = nil
        self.backVideoWriterInput = nil
        
        // Cancel front video writer
        if let frontWriter = self.frontVideoWriter {
            if frontWriter.status == .writing {
                self.frontVideoWriterInput?.markAsFinished()
                frontWriter.cancelWriting()
                print("🧹 CameraManager: Cancelled frontVideoWriter")
            }
        }
        self.frontVideoWriter = nil
        self.frontVideoWriterInput = nil
        
        // Reset session flags
        self.backWriterSessionStarted = false
        self.frontWriterSessionStarted = false
        self.pipWriterSessionStarted = false
        self.audioWriterSessionStarted = false
        
        print("✅ CameraManager: All writers cleaned up")
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
            case .backOnly, .dual, .picInPic:
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
    
    // MARK: - Filter Application for Video
    /// Apply current filter to a sample buffer for video recording
    private func applyFilterToSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> CMSampleBuffer? {
        guard currentFilter != .none,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return sampleBuffer
        }
        
        // Apply filter to CIImage
        var ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        ciImage = currentFilter.apply(to: ciImage)
        
        // Create new pixel buffer with filtered image
        var filteredPixelBuffer: CVPixelBuffer?
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let attributes: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ]
        
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes as CFDictionary,
            &filteredPixelBuffer
        )
        
        guard status == kCVReturnSuccess, let outputBuffer = filteredPixelBuffer else {
            return sampleBuffer
        }
        
        // Render filtered image to pixel buffer
        ciContext.render(ciImage, to: outputBuffer)
        
        // Create new sample buffer with filtered pixel buffer
        return ImageUtils.createSampleBuffer(from: outputBuffer, copying: sampleBuffer) ?? sampleBuffer
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
        
        // Determine which camera by checking the connection's input device
        if output is AVCaptureVideoDataOutput {
            // Capture recording state once at the beginning to avoid multiple property accesses
            let currentlyRecording = isRecording
            let currentlyPIPMode = isPIPRecordingMode
            
            // Check camera position through connection
            guard let inputPort = connection.inputPorts.first,
                  let deviceInput = inputPort.input as? AVCaptureDeviceInput else {
                print("⚠️ CameraManager: Could not determine camera position from connection")
                return
            }
            
            let position = deviceInput.device.position
            
            switch position {
            case .back:
                // Back camera frame - wrap in autoreleasepool for better memory management
                autoreleasepool {
                        frameLock.lock()
                        lastBackFrame = sampleBuffer
                        backFrameCount += 1
                        // Reduce logging frequency to save CPU
                        if backFrameCount % 300 == 0 {
                            print("📹 CameraManager: Received \(backFrameCount) back camera frames")
                        }
                        frameLock.unlock()

                        // Publish a lightweight preview image at a reduced rate to save CPU
                        if backFrameCount % previewFrameInterval == 0 {
                            if let previewImage = self.imageFromSampleBuffer(sampleBuffer, isFrontCamera: false) {
                                DispatchQueue.main.async { [weak self] in
                                    self?.capturedBackImage = previewImage
                                }
                            }
                        }
                    }
                    
                    // Write to video file if recording
                    // CRITICAL: Check isRecording AND writer status to prevent race condition crashes
                    
                    if currentlyRecording && currentlyPIPMode {
                        // PIP recording mode - compose both cameras
                        // Log first frame to confirm we're entering this code path
                        if backFrameCount == 1 {
                            print("🎬 CameraManager: FIRST back frame in PIP recording mode")
                        }
                        
                        // Extra safety: verify writer exists and is in valid state
                        if let videoInput = pipVideoWriterInput,
                           let writer = pipVideoWriter,
                           writer.status == .writing,
                           videoInput.isReadyForMoreMediaData,
                           frontFrameCount >= 3 {  // Wait for front camera
                                
                                if backFrameCount <= 5 {
                                    print("🎬 CameraManager: Processing PIP frame #\(backFrameCount), front frames: \(frontFrameCount)")
                                }
                                
                                // Start writer session
                                if !pipWriterSessionStarted {
                                    let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                                    if writer.status == .writing {
                                        writer.startSession(atSourceTime: timestamp)
                                        recordingStartTime = timestamp
                                        pipWriterSessionStarted = true
                                        print("✅ CameraManager: PIP writer session started at \(timestamp.seconds)")
                                    }
                                }
                                
                                // Compose and append PIP frame
                                if pipWriterSessionStarted && currentlyRecording && writer.status == .writing {
                                    // Get front camera buffer
                                    frameLock.lock()
                                    let frontFrame = lastFrontFrame
                                    frameLock.unlock()
                                    
                                    if let frontFrame = frontFrame,
                                       let backPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer),
                                       let frontPixelBuffer = CMSampleBufferGetImageBuffer(frontFrame) {
                                        
                                        // Rotate both buffers first
                                        let rotatedBackBuffer = self.rotateSampleBufferIfNeeded(sampleBuffer, orientation: self.recordingOrientation, isFrontCamera: false)
                                        let rotatedFrontBuffer = self.rotateSampleBufferIfNeeded(frontFrame, orientation: self.recordingOrientation, isFrontCamera: true)
                                        
                                        if let rotatedBackPixel = CMSampleBufferGetImageBuffer(rotatedBackBuffer),
                                           let rotatedFrontPixel = CMSampleBufferGetImageBuffer(rotatedFrontBuffer) {
                                            
                                            // Determine orientation
                                            let isLandscape = self.recordingOrientation == .landscapeLeft || self.recordingOrientation == .landscapeRight
                                            
                                            // Get current preview switcher state (thread-safe read)
                                            let isBackMain = self.previewSwitcher?.isBackCameraMain ?? true
                                            
                                            // Compose PIP frame with current switcher state and filter
                                            let composeStart = CFAbsoluteTimeGetCurrent()
                                            if let composedBuffer = PIPComposer.composePIPVideoFrame(
                                                backBuffer: rotatedBackPixel,
                                                frontBuffer: rotatedFrontPixel,
                                                isLandscape: isLandscape,
                                                isBackCameraMain: isBackMain,
                                                ciContext: self.ciContext,
                                                filter: self.currentFilter
                                            ) {
                                                let composeTime = (CFAbsoluteTimeGetCurrent() - composeStart) * 1000
                                                if backFrameCount <= 10 || composeTime > 50 {
                                                    print("⏱️ PIP compose took \(String(format: "%.1f", composeTime))ms")
                                                }
                                                // Create new sample buffer with composed pixel buffer
                                                var timingInfo = CMSampleTimingInfo()
                                                timingInfo.presentationTimeStamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                                                timingInfo.duration = CMSampleBufferGetDuration(sampleBuffer)
                                                timingInfo.decodeTimeStamp = CMSampleBufferGetDecodeTimeStamp(sampleBuffer)
                                                
                                                var formatDescription: CMFormatDescription?
                                                CMVideoFormatDescriptionCreateForImageBuffer(
                                                    allocator: kCFAllocatorDefault,
                                                    imageBuffer: composedBuffer,
                                                    formatDescriptionOut: &formatDescription
                                                )
                                                
                                                if let format = formatDescription {
                                                    var newSampleBuffer: CMSampleBuffer?
                                                    CMSampleBufferCreateReadyWithImageBuffer(
                                                        allocator: kCFAllocatorDefault,
                                                        imageBuffer: composedBuffer,
                                                        formatDescription: format,
                                                        sampleTiming: &timingInfo,
                                                        sampleBufferOut: &newSampleBuffer
                                                    )
                                                    
                                                    if let pipSample = newSampleBuffer,
                                                       videoInput.isReadyForMoreMediaData && writer.status == .writing {
                                                        let success = videoInput.append(pipSample)
                                                        if backFrameCount <= 5 {
                                                            print("✅ CameraManager: PIP frame #\(backFrameCount) appended: \(success)")
                                                        }
                                                        if !success && backFrameCount % 300 == 0 {
                                                            print("⚠️ CameraManager: Failed to append PIP frame")
                                                        }
                                                        if backFrameCount % 300 == 0 {
                                                            print("📹 CameraManager: PIP frames appended (count: \(backFrameCount))")
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            } else if backFrameCount % 300 == 0 {
                                if frontFrameCount < 3 {
                                    print("⏳ CameraManager: PIP waiting for front camera frames (\(frontFrameCount)/3)...")
                                }
                            }
                        } else {
                            // Normal dual recording mode
                            if let videoInput = backVideoWriterInput, 
                               let writer = backVideoWriter,
                               writer.status == .writing,
                               videoInput.isReadyForMoreMediaData {
                                // Start writer session only when we have stable frames from both cameras
                                // Use original buffer timestamp for session start
                                if !backWriterSessionStarted, frontFrameCount >= 3 {  // Wait for front camera to have at least 3 frames (skip black frames)
                                    let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                                    if writer.status == .writing {  // Double check writer is still ready
                                        writer.startSession(atSourceTime: timestamp)
                                        recordingStartTime = timestamp
                                        backWriterSessionStarted = true
                                        print("✅ CameraManager: Back video writer session started at \(timestamp.seconds) (both cameras stable)")
                                    } else {
                                        print("⚠️ CameraManager: Cannot start session, writer status: \(writer.status.rawValue)")
                                    }
                                }
                                // CRITICAL: Only append after session has started and verify recording still active
                                if backWriterSessionStarted && currentlyRecording && writer.status == .writing {
                                    // Rotate pixel buffer if in portrait mode
                                    var rotatedBuffer = self.rotateSampleBufferIfNeeded(sampleBuffer, orientation: self.recordingOrientation, isFrontCamera: false)
                                    // Apply filter if enabled
                                    if let filteredBuffer = self.applyFilterToSampleBuffer(rotatedBuffer) {
                                        rotatedBuffer = filteredBuffer
                                    }
                                    // Double check writer is still ready after rotation and filter
                                    if videoInput.isReadyForMoreMediaData && writer.status == .writing {
                                        let success = videoInput.append(rotatedBuffer)
                                        if !success && backFrameCount % 300 == 0 {
                                            print("⚠️ CameraManager: Failed to append back video frame, writer status: \(writer.status.rawValue)")
                                        }
                                        if backFrameCount % 300 == 0 {
                                            print("📹 CameraManager: Back video frames appended (count: \(backFrameCount))")
                                        }
                                    }
                                }
                            } else if backFrameCount % 30 == 0 {
                                if frontFrameCount < 3 {
                                    print("⏳ CameraManager: Waiting for front camera frames (\(frontFrameCount)/3)...")
                                }
                            }
                        }
                    
            case .front:
                // Front camera frame - wrap in autoreleasepool for better memory management
                autoreleasepool {
                        frameLock.lock()
                        lastFrontFrame = sampleBuffer
                        frontFrameCount += 1
                        if frontFrameCount == 1 {
                            print("🎉 CameraManager: FIRST front camera frame received!")
                        }
                        // Reduce logging frequency to save CPU
                        if frontFrameCount % 300 == 0 {
                            print("📹 CameraManager: Received \(frontFrameCount) front camera frames")
                        }
                        frameLock.unlock()

                        // Publish a lightweight preview image at a reduced rate to save CPU
                        if frontFrameCount % previewFrameInterval == 0 {
                            if let previewImage = self.imageFromSampleBuffer(sampleBuffer, isFrontCamera: true) {
                                DispatchQueue.main.async { [weak self] in
                                    self?.capturedFrontImage = previewImage
                                }
                            }
                        }
                    }
                    
                    // Write to video file if recording
                    // CRITICAL: Check isRecording AND writer status to prevent race condition crashes
                    // Reuse captured recording state from back camera section
                    if currentlyRecording && !currentlyPIPMode {
                        if let videoInput = frontVideoWriterInput,
                           let writer = frontVideoWriter,
                           writer.status == .writing,
                           videoInput.isReadyForMoreMediaData {
                            // Use same start time as back camera
                            if !frontWriterSessionStarted, let startTime = recordingStartTime {
                                if writer.status == .writing {  // Double check writer is still ready
                                    writer.startSession(atSourceTime: startTime)
                                    frontWriterSessionStarted = true
                                    print("✅ CameraManager: Front video writer session started at \(startTime.seconds)")
                                } else {
                                    print("⚠️ CameraManager: Cannot start front session, writer status: \(writer.status.rawValue)")
                                }
                            }
                            // CRITICAL: Only append after session has started and verify recording still active
                            if frontWriterSessionStarted && currentlyRecording && writer.status == .writing {
                                // Rotate pixel buffer if in portrait mode
                                var rotatedBuffer = self.rotateSampleBufferIfNeeded(sampleBuffer, orientation: self.recordingOrientation, isFrontCamera: true)
                                // Apply filter if enabled
                                if let filteredBuffer = self.applyFilterToSampleBuffer(rotatedBuffer) {
                                    rotatedBuffer = filteredBuffer
                                }
                                // Double check writer is still ready after rotation and filter
                                if videoInput.isReadyForMoreMediaData && writer.status == .writing {
                                    let success = videoInput.append(rotatedBuffer)
                                    if !success && frontFrameCount % 300 == 0 {
                                        print("⚠️ CameraManager: Failed to append front video frame, writer status: \(writer.status.rawValue)")
                                    }
                                }
                            }
                        }
                    }
                
            case .unspecified:
                break
                
            @unknown default:
                break
            }
        }
        // End of: if output is AVCaptureVideoDataOutput
        
        // Check for audio output
        if output is AVCaptureAudioDataOutput {
            // Audio data
            // CRITICAL: Check isRecording AND writer status to prevent race condition crashes
            // Capture recording state once
            let currentlyRecording = isRecording
            
            if currentlyRecording {
                if let audioInput = audioWriterInput,
                   let writer = audioWriter,
                   writer.status == .writing,
                   audioInput.isReadyForMoreMediaData {
                    if !audioWriterSessionStarted, let startTime = recordingStartTime {
                        writer.startSession(atSourceTime: startTime)
                        audioWriterSessionStarted = true
                        print("✅ CameraManager: Audio writer session started at \(startTime.seconds)")
                    }
                    // CRITICAL: Verify recording still active before append
                    if audioWriterSessionStarted && currentlyRecording {
                        audioInput.append(sampleBuffer)
                    }
                }
            }
        }
    }
}

