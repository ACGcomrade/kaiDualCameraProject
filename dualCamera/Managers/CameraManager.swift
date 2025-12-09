import AVFoundation
import UIKit
import Combine
import Photos

class CameraManager: NSObject, ObservableObject {
    // MARK: - Properties
    @Published var session: AVCaptureMultiCamSession?
    private let sessionQueue = DispatchQueue(label: "sessionQueue")
    private let backVideoDataQueue = DispatchQueue(label: "backVideoDataQueue")
    private let frontVideoDataQueue = DispatchQueue(label: "frontVideoDataQueue")
    private let audioDataQueue = DispatchQueue(label: "audioDataQueue")
    private let settings = CameraSettings.shared
    
    @Published var capturedBackImage: UIImage? = nil
    @Published var capturedFrontImage: UIImage? = nil
    @Published var isFlashOn = false
    @Published var isDualCameraMode = true
    @Published var isSessionRunning = false
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var zoomFactor: CGFloat = 1.0
    
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
    func setupSession() {
        print("🎥 CameraManager: setupSession called")
        
        // OPTIMIZATION: Only configure once!
        if isSessionConfigured && session != nil {
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
        print("🎥 CameraManager: configureSession called")
        
        let newSession = AVCaptureMultiCamSession()
        newSession.beginConfiguration()
        
        // Setup back camera with best available camera (ultra-wide if available)
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
        
        // Setup front camera with video data output
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
        
        let backImage = imageFromSampleBuffer(backFrame)
        let frontImage = imageFromSampleBuffer(frontFrame)
        
        completion(backImage, frontImage)
    }
    
    // MARK: - TEST: Generate fake frames for UI testing
    func startTestMode() {
        print("🧪 CameraManager: Starting TEST MODE with fake frames")
        
        // Generate test images
        let backTestImage = createTestImage(color: .blue, text: "BACK CAMERA")
        let frontTestImage = createTestImage(color: .green, text: "FRONT CAMERA")
        
        // Simulate frame updates at 30fps
        Timer.scheduledTimer(withTimeInterval: 1.0/30.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            // Update test images directly
            DispatchQueue.main.async {
                self.capturedBackImage = backTestImage
                self.capturedFrontImage = frontTestImage
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
            guard let self = self else {
                print("❌ CameraManager: self is nil")
                completion(nil, nil)
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
            let backImage = self.imageFromSampleBuffer(backFrame)
            let frontImage = self.imageFromSampleBuffer(frontFrame)
            
            print("📸 CameraManager: Back image: \(backImage != nil), Front image: \(frontImage != nil)")
            
            DispatchQueue.main.async {
                completion(backImage, frontImage)
            }
        }
    }
    
    private func imageFromSampleBuffer(_ sampleBuffer: CMSampleBuffer?) -> UIImage? {
        guard let sampleBuffer = sampleBuffer,
              let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }
        
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        let context = CIContext()
        
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        
        return UIImage(cgImage: cgImage)
    }
    
    // MARK: - Video Recording (Frame Writing - NO FREEZE!)
    func startVideoRecording(completion: @escaping (URL?, URL?, Error?) -> Void) {
        print("🎥 CameraManager: startVideoRecording called")
        
        guard !isRecording else {
            print("⚠️ CameraManager: Already recording")
            return
        }
        
        // Set isRecording FIRST to reduce UI lag
        DispatchQueue.main.async {
            self.isRecording = true
            self.recordingDuration = 0
            
            self.recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                self?.recordingDuration += 0.1
            }
            print("✅ CameraManager: isRecording = true (UI updated)")
        }
        
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
                // Create back camera writer
                let backWriter = try AVAssetWriter(url: backURL, fileType: .mov)
                let backVideoSettings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: 1920,
                    AVVideoHeightKey: 1080
                ]
                let backVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: backVideoSettings)
                backVideoInput.expectsMediaDataInRealTime = true
                
                if backWriter.canAdd(backVideoInput) {
                    backWriter.add(backVideoInput)
                    self.backVideoWriter = backWriter
                    self.backVideoWriterInput = backVideoInput
                    print("✅ CameraManager: Back video writer created")
                }
                
                // Create front camera writer
                let frontWriter = try AVAssetWriter(url: frontURL, fileType: .mov)
                let frontVideoInput = AVAssetWriterInput(mediaType: .video, outputSettings: backVideoSettings)
                frontVideoInput.expectsMediaDataInRealTime = true
                
                if frontWriter.canAdd(frontVideoInput) {
                    frontWriter.add(frontVideoInput)
                    self.frontVideoWriter = frontWriter
                    self.frontVideoWriterInput = frontVideoInput
                    print("✅ CameraManager: Front video writer created")
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
            
            DispatchQueue.main.async {
                self.isRecording = false
                self.recordingTimer?.invalidate()
                self.recordingTimer = nil
                print("✅ CameraManager: isRecording set to false, timer stopped")
            }
            
            // Give time for last frames to be written
            Thread.sleep(forTimeInterval: 0.5)
            
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
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        self.sessionQueue.async {
                            guard let device = self.backCameraInput?.device else { return }
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
    
    // MARK: - Photo Library Saving
    func savePhotoToLibrary(_ image: UIImage, completion: @escaping (Bool, Error?) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                print("❌ CameraManager: Photo library permission denied")
                DispatchQueue.main.async {
                    completion(false, NSError(domain: "CameraManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Photo library access denied"]))
                }
                return
            }
            
            PHPhotoLibrary.shared().performChanges({
                PHAssetCreationRequest.creationRequestForAsset(from: image)
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
                    
                    // Write to video file if recording
                    if isRecording, let videoInput = backVideoWriterInput, videoInput.isReadyForMoreMediaData {
                        if !backWriterSessionStarted, let writer = backVideoWriter, writer.status == .writing {
                            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                            writer.startSession(atSourceTime: timestamp)
                            recordingStartTime = timestamp
                            backWriterSessionStarted = true
                            print("✅ CameraManager: Back video writer session started at \(timestamp.seconds)")
                        }
                        if backWriterSessionStarted {
                            _ = videoInput.append(sampleBuffer)
                            if backFrameCount % 60 == 0 {
                                print("📹 CameraManager: Back video frames appended (count: \(backFrameCount))")
                            }
                        }
                    } else if isRecording && backFrameCount % 30 == 0 {
                        print("⚠️ CameraManager: Back recording but cannot write - ready: \(backVideoWriterInput?.isReadyForMoreMediaData ?? false), writer: \(backVideoWriter != nil)")
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
                    
                    // Write to video file if recording
                    if isRecording, let videoInput = frontVideoWriterInput, videoInput.isReadyForMoreMediaData {
                        if !frontWriterSessionStarted, let writer = frontVideoWriter, writer.status == .writing, let startTime = recordingStartTime {
                            writer.startSession(atSourceTime: startTime)
                            frontWriterSessionStarted = true
                            print("✅ CameraManager: Front video writer session started at \(startTime.seconds)")
                        }
                        if frontWriterSessionStarted {
                            videoInput.append(sampleBuffer)
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
